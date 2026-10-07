import AppKit
import Combine
import UserNotifications
import UniformTypeIdentifiers

@MainActor final class MailStore: ObservableObject {
    @Published var library: MailLibrary
    @Published var messages: [CachedMessage]
    @Published var folders: [UUID: [TransportFolder]] = [:]
    @Published var busy = Set<UUID>()
    @Published var detailBusy = Set<String>()
    @Published var sending = false
    @Published var notice: String?
    @Published var problem: String?
    @Published var compose: MailDraft?
    @Published var route = "overview"
    @Published var identityFilter: UUID?
    @Published var mailboxFilter: UUID?
    @Published var folder = "INBOX"
    @Published var search = ""
    @Published var selectedMessageID: String?
    let storage: MailStorage
    let oauth = OAuthManager()
    private var timer: Timer?
    private var ticks = 0
    init(root: URL? = nil) {
        storage = MailStorage(root: root)
        library = storage.load(); messages = storage.loadMessages()
        problem = storage.readFailure ?? storage.cacheWarning
        timer = Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.ticks += 1
            if self.ticks >= max(1,self.library.preferences.syncMinutes) { self.ticks = 0; await self.syncAll() }
        } }
    }
    var filteredAccounts: [MailAccount] { library.accounts.filter { identityFilter == nil || $0.identityID == identityFilter } }
    var filteredMessages: [CachedMessage] {
        let ids = Set(filteredAccounts.map(\.id)); let query = search.trimmingCharacters(in:.whitespacesAndNewlines)
        return messages.filter { m in ids.contains(m.accountID) && (mailboxFilter == nil || m.accountID == mailboxFilter) && m.folder == folder && (query.isEmpty || [m.subject,m.from,m.to,m.body,m.preview].joined(separator:" ").localizedCaseInsensitiveContains(query)) }.sorted {$0.date > $1.date}
    }
    var filteredPlatforms: [PlatformRecord] {
        let ids = Set(filteredAccounts.map(\.id))
        return library.platforms.filter { p in
            (identityFilter == nil || (p.accountID != nil && ids.contains(p.accountID!))) && (mailboxFilter == nil || p.accountID == mailboxFilter) && (search.isEmpty || [p.name,p.username,p.address,p.url,p.notes,p.status,account(p.accountID)?.email ?? ""].joined(separator:" ").localizedCaseInsensitiveContains(search))
        }.sorted {$0.updatedAt > $1.updatedAt}
    }
    func account(_ id: UUID?) -> MailAccount? { library.accounts.first {$0.id == id} }
    func identity(_ id: UUID?) -> MailIdentity? { library.identities.first {$0.id == id} }
    func identityName(for account: MailAccount?) -> String { identity(account?.identityID)?.name ?? "未分类" }
    func commit(_ value: MailLibrary) throws { try storage.save(value); library = value }
    func publish(_ error: Error) { problem = error.localizedDescription }
    func updatePreferences(_ preferences: MailPreferences) throws {
        var v = library; v.preferences = preferences; try commit(v); notice = "设置已保存"
    }
    func saveIdentity(_ identity: MailIdentity) throws {
        guard !identity.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw MailAppError.message("请填写身份名称。") }
        var v = library
        if let i = v.identities.firstIndex(where:{$0.id == identity.id}) { v.identities[i] = identity } else { v.identities.append(identity) }
        try commit(v)
    }
    func deleteIdentity(_ id: UUID) {
        do { var v = library; v.identities.removeAll {$0.id == id}; for i in v.accounts.indices where v.accounts[i].identityID == id { v.accounts[i].identityID = nil }; try commit(v); if identityFilter == id { identityFilter = nil } } catch { publish(error) }
    }
    func saveAccount(_ input: MailAccount, password: String?) throws {
        var a = input; a.email = a.email.trimmingCharacters(in:.whitespacesAndNewlines); a.username = a.username.trimmingCharacters(in:.whitespacesAndNewlines)
        if a.username.isEmpty { a.username = a.email }
        guard !busy.contains(a.id), !sending, !detailBusy.contains(where:{$0.hasPrefix(a.id.uuidString + "|")}) else { throw MailAppError.message("此邮箱正在收发或读取邮件，请稍后再保存。") }
        let oldAccount = account(a.id)
        if let oldAccount, oldAccount.email.lowercased() != a.email.lowercased() { throw MailAppError.message("已有邮箱地址不能直接更换。请另行添加新邮箱，以保留正确的邮件和平台归属。") }
        let connectionChanged = oldAccount.map { $0.username != a.username || $0.imapHost != a.imapHost || $0.imapPort != a.imapPort || $0.imapTLS != a.imapTLS || $0.auth != a.auth } ?? false
        if connectionChanged { a.lastSync = nil; a.syncError = nil }
        guard MailValidation.address(a.email) else { throw MailAppError.message("请填写有效的完整邮箱地址。") }
        guard !library.accounts.contains(where:{$0.id != a.id && $0.email.lowercased() == a.email.lowercased()}) else { throw MailAppError.message("这个邮箱已经添加过了。") }
        if a.enabled && (a.imapHost.isEmpty || a.smtpHost.isEmpty) { throw MailAppError.message("请填写收件和发件服务器，或选择仅登记资料。") }
        for alias in a.allowedAddresses where !MailValidation.address(alias) { throw MailAppError.message("邮箱别名格式不正确：" + alias) }
        let key = "account." + a.id.uuidString + ".password"
        let previous = password == nil ? nil : try Vault.read(key)
        if let password, !password.isEmpty { try Vault.save(password,for:key) }
        do {
            var v = library
            if let i = v.accounts.firstIndex(where:{$0.id == a.id}) { v.accounts[i] = a } else { v.accounts.append(a) }
            try commit(v)
        } catch {
            if password != nil { if let previous { try? Vault.save(previous,for:key) } else { try? Vault.delete(key) } }
            throw error
        }
        if connectionChanged {
            messages.removeAll {$0.accountID == a.id && $0.folder != "__local_sent__"}; folders[a.id] = nil
            do { try storage.saveMessages(messages) } catch { publish(error) }
        }
        notice = "邮箱资料已保存"
    }
    func deleteAccount(_ id: UUID) {
        do {
            guard !busy.contains(id) && !sending && !detailBusy.contains(where:{$0.hasPrefix(id.uuidString + "|")}) else { throw MailAppError.message("邮箱正在同步、读取或发送，请稍后再移除。") }
            var v = library; v.accounts.removeAll {$0.id == id}
            for i in v.platforms.indices where v.platforms[i].accountID == id { v.platforms[i].accountID = nil; v.platforms[i].history.append(PlatformHistory(text:"已移除原邮箱，保留平台记录")) }
            for i in v.drafts.indices where v.drafts[i].accountID == id { v.drafts[i].accountID = nil }
            try commit(v); messages.removeAll {$0.accountID == id}; try storage.saveMessages(messages)
            try Vault.delete("account." + id.uuidString + ".password"); try oauth.disconnect(accountID:id.uuidString)
            if mailboxFilter == id { mailboxFilter = nil }; notice = "邮箱已移除，平台记录已保留"
        } catch { publish(error) }
    }
    func savePlatform(_ input: PlatformRecord) throws {
        var p = input; p.name = p.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !p.name.isEmpty else { throw MailAppError.message("请填写平台名称。") }
        if !p.url.isEmpty { guard let u = MailValidation.webURL(p.url) else { throw MailAppError.message("平台网址应为有效的 http / https 地址。") }; p.url = u.absoluteString }
        if p.address.isEmpty { p.address = account(p.accountID)?.email ?? "" }
        if !p.address.isEmpty && !MailValidation.address(p.address) { throw MailAppError.message("实际关联邮箱地址格式不正确。") }
        p.updatedAt = Date()
        var v = library
        if let i = v.platforms.firstIndex(where:{$0.id == p.id}) {
            let old = v.platforms[i]
            var changes: [String] = []
            if old.address != p.address { changes.append("邮箱：\(old.address) → \(p.address)") }
            if old.status != p.status { changes.append("状态：\(old.status) → \(p.status)") }
            if old.loginMethod != p.loginMethod { changes.append("登录方式：\(p.loginMethod)") }
            p.history = old.history
            p.history.append(PlatformHistory(text:changes.isEmpty ? "更新了平台资料" : changes.joined(separator:"；")))
            v.platforms[i] = p
        } else { p.history = [PlatformHistory(text:"手动登记关联平台")]; v.platforms.append(p) }
        try commit(v); notice = "平台关联已保存"
    }
    func deletePlatform(_ id: UUID) { do { var v = library; v.platforms.removeAll {$0.id == id}; try commit(v) } catch { publish(error) } }
    func saveDraft(_ input: MailDraft) throws {
        var d = input; d.updatedAt = Date(); var v = library
        if let i = v.drafts.firstIndex(where:{$0.id == d.id}) { v.drafts[i] = d } else { v.drafts.append(d) }
        try commit(v)
    }
    func deleteDraft(_ id: UUID) { do { var v = library; v.drafts.removeAll {$0.id == id}; try commit(v) } catch { publish(error) } }
    func newDraft(accountID: UUID? = nil) {
        guard compose == nil else {return}
        let a = account(accountID ?? mailboxFilter) ?? filteredAccounts.first(where:{$0.enabled}) ?? filteredAccounts.first
        compose = MailDraft(accountID:a?.id,from:a?.email ?? "",body:a?.signature.isEmpty == false ? "\n\n" + a!.signature : "")
    }
    func reply(_ m: CachedMessage, all: Bool = false, forward: Bool = false) {
        guard compose == nil else {return}
        let a = account(m.accountID)
        let own = Set(a?.allowedAddresses.map{$0.lowercased()} ?? [])
        let source = MailValidation.bareAddress(m.replyTo ?? m.from)
        var recipients = own.contains(source.lowercased()) ? MailValidation.recipients(m.to).map(MailValidation.bareAddress) : [source]
        if all { recipients += MailValidation.recipients(m.to + "," + m.cc).map(MailValidation.bareAddress) }
        var seen = Set<String>(); recipients = recipients.filter{MailValidation.address($0) && !own.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted}
        let prefix = forward ? "Fwd: " : "Re: "
        let quoted = m.body.components(separatedBy:"\n").map{"> " + $0}.joined(separator:"\n")
        let text = "\n\n" + (a?.signature ?? "") + "\n\n—— 原邮件 · \(m.from) ——\n" + quoted
        compose = MailDraft(accountID:m.accountID,from:a?.email ?? "",to:forward ? "" : recipients.joined(separator:", "),subject:m.subject.lowercased().hasPrefix(prefix.lowercased()) ? m.subject : prefix + m.subject,body:text,inReplyTo:forward ? nil : m.messageID,references:forward ? nil : [m.references,m.messageID].compactMap{$0}.joined(separator:" "))
    }
    func oauthConfiguration(for a: MailAccount) throws -> OAuthConfiguration {
        let p = library.preferences
        if a.auth == "google" { return OAuthConfiguration(provider:.google,clientID:p.googleClientID,clientSecret:try Vault.read("oauth.googleClientSecret")) }
        return OAuthConfiguration(provider:.microsoft,clientID:p.microsoftClientID,tenant:p.microsoftTenant)
    }
    func authorize(_ a: MailAccount) async throws { _ = try await oauth.authorize(accountID:a.id.uuidString,configuration:oauthConfiguration(for:a),loginHint:a.email) }
    func connection(for a: MailAccount, overridePassword: String? = nil) async throws -> TransportConnection {
        var password = ""; var token: String?
        if a.auth == "password" {
            password = try overridePassword ?? Vault.read("account." + a.id.uuidString + ".password") ?? ""
            guard !password.isEmpty else { throw MailAppError.message("请编辑邮箱并填写客户端授权码或专用密码。") }
        } else { token = try await oauth.validAccessToken(accountID:a.id.uuidString,configuration:oauthConfiguration(for:a)) }
        return TransportConnection(imapHost:a.imapHost,imapPort:a.imapPort,imapSecurity:TransportSecurity(rawValue:a.imapTLS) ?? .tls,smtpHost:a.smtpHost,smtpPort:a.smtpPort,smtpSecurity:TransportSecurity(rawValue:a.smtpTLS) ?? .tls,username:a.username.isEmpty ? a.email : a.username,password:password,oauthToken:token)
    }
    func test(_ a: MailAccount, password: String?) async throws {
        let c = try await connection(for:a,overridePassword:password)
        try await MailTransport.testConnection(c)
    }
    func syncAll() async {
        for a in library.accounts where a.enabled { await sync(a.id,folder:"INBOX") }
    }
    func sync(_ id: UUID, folder target: String = "INBOX") async {
        guard target != "__local_sent__", let a = account(id), a.enabled, !busy.contains(id), !detailBusy.contains(where:{$0.hasPrefix(id.uuidString + "|")}), storage.readFailure == nil else { return }
        busy.insert(id); defer { busy.remove(id) }
        do {
            let c = try await connection(for:a)
            let remoteFolders = try await MailTransport.listFolders(c); folders[id] = remoteFolders
            let fetched = try await MailTransport.fetchMessages(c,folder:target,limit:library.preferences.fetchLimit)
            let old = messages.filter{$0.accountID == id && $0.folder == target}
            let mapped = fetched.map { item -> CachedMessage in
                var m = cached(item,accountID:id,folder:target)
                if let previous = old.first(where:{$0.uid == item.uid && $0.uidValidity != nil && $0.uidValidity == item.uidValidity && $0.messageID == item.messageID}), previous.loaded && !m.loaded {
                    m.body = previous.body; m.html = previous.html; m.attachments = previous.attachments; m.loaded = true; m.preview = previous.preview
                }
                return m
            }
            var next = messages.filter{!($0.accountID == id && $0.folder == target)}; next += mapped
            try storage.saveMessages(next); messages = next
            var v = library; if let i = v.accounts.firstIndex(where:{$0.id == id}) { v.accounts[i].lastSync = Date(); v.accounts[i].syncError = nil }; try commit(v)
            let fresh = mapped.filter { m in !m.isRead && !old.contains(where:{$0.id == m.id}) }
            if a.lastSync != nil && target == "INBOX" && !fresh.isEmpty && library.preferences.notifyNewMail { notify(count:fresh.count,account:a) }
            notice = "\(a.displayName) 已同步 \(mapped.count) 封邮件"
        } catch {
            var v = library; if let i = v.accounts.firstIndex(where:{$0.id == id}) { v.accounts[i].syncError = error.localizedDescription }
            do { try commit(v) } catch { publish(error) }
            notice = "\(a.displayName) 同步失败，请查看邮箱状态"
        }
    }
    func cached(_ m: TransportMessage, accountID: UUID, folder: String) -> CachedMessage {
        var result = CachedMessage(id:accountID.uuidString + "|" + folder + "|" + String(m.uidValidity ?? 0) + "|" + String(m.uid),accountID:accountID,folder:folder,uid:m.uid,subject:m.subject,from:m.from,to:m.to,cc:m.cc,date:m.date,preview:String(m.body.replacingOccurrences(of:"\n",with:" ").prefix(150)),body:m.body,html:m.html,isRead:m.isRead,isFlagged:m.isFlagged,messageID:m.messageID,references:m.references,attachments:m.attachments.map{CachedAttachment(filename:$0.filename,mimeType:$0.mimeType,data:$0.data)},loaded:m.bodyLoaded)
        result.uidValidity = m.uidValidity; result.replyTo = m.replyTo
        return result
    }
    func loadMessage(_ id: String) async {
        guard let existing = messages.first(where:{$0.id == id}), existing.folder != "__local_sent__", let a = account(existing.accountID), a.enabled, !detailBusy.contains(id), !busy.contains(a.id) else { return }
        detailBusy.insert(id); defer { detailBusy.remove(id) }
        do {
            guard let validity = existing.uidValidity else { throw MailAppError.message("请先重新同步此文件夹，再读取或修改邮件。") }
            let c = try await connection(for:a)
            if !existing.loaded {
                let fetched = try await MailTransport.fetchMessage(c,folder:existing.folder,uid:existing.uid,expectedUIDValidity:validity)
                if let i = messages.firstIndex(where:{$0.id == id}) { messages[i] = cached(fetched,accountID:a.id,folder:existing.folder) }
            }
            if !existing.isRead { try await MailTransport.setRead(c,folder:existing.folder,uids:[existing.uid],read:true,expectedUIDValidity:validity); if let i = messages.firstIndex(where:{$0.id == id}) { messages[i].isRead = true } }
            try storage.saveMessages(messages)
        } catch { publish(error) }
    }
    func changeFlag(_ m: CachedMessage, read: Bool? = nil, flag: Bool? = nil) async {
        guard let a = account(m.accountID), !busy.contains(a.id), !detailBusy.contains(m.id) else { return }
        detailBusy.insert(m.id); defer {detailBusy.remove(m.id)}
        do {
            if m.folder != "__local_sent__" {
                guard a.enabled, let validity = m.uidValidity else { throw MailAppError.message("请启用邮箱并重新同步后再修改邮件状态。") }
                let c = try await connection(for:a)
                if let read { try await MailTransport.setRead(c,folder:m.folder,uids:[m.uid],read:read,expectedUIDValidity:validity) }
                if let flag { try await MailTransport.setFlagged(c,folder:m.folder,uids:[m.uid],flagged:flag,expectedUIDValidity:validity) }
            }
            if let i = messages.firstIndex(where:{$0.id == m.id}) { if let read { messages[i].isRead = read }; if let flag { messages[i].isFlagged = flag } }
            try storage.saveMessages(messages)
        } catch { publish(error) }
    }
    func moveMessage(_ m: CachedMessage, destination: String) async {
        guard m.folder != "__local_sent__", let a = account(m.accountID), a.enabled, !busy.contains(a.id), !detailBusy.contains(m.id) else { return }
        detailBusy.insert(m.id); defer {detailBusy.remove(m.id)}
        do {
            guard let validity = m.uidValidity else { throw MailAppError.message("请重新同步后再移动邮件。") }
            let c = try await connection(for:a)
            try await MailTransport.move(c,folder:m.folder,uid:m.uid,destination:destination,expectedUIDValidity:validity)
            messages.removeAll{$0.id == m.id}; selectedMessageID = nil; try storage.saveMessages(messages); notice = "邮件已移至 \(destination)"
        } catch { publish(error) }
    }
    func send(_ draft: MailDraft) async throws {
        guard !sending, let a = account(draft.accountID), a.enabled else { throw MailAppError.message("请选择已启用收发的邮箱。") }
        let to = MailValidation.recipients(draft.to), cc = MailValidation.recipients(draft.cc), bcc = MailValidation.recipients(draft.bcc)
        guard !(to+cc+bcc).isEmpty, (to+cc+bcc).allSatisfy(MailValidation.address) else { throw MailAppError.message("请检查收件人地址，多个地址使用逗号分隔。") }
        guard a.allowedAddresses.contains(where:{$0.lowercased() == draft.from.lowercased()}) else { throw MailAppError.message("发件地址必须属于此邮箱或已登记的别名。") }
        try saveDraft(draft)
        sending = true; defer { sending = false }
        var attachments: [TransportAttachment] = []
        var total = 0
        for file in draft.attachments {
            let url = URL(fileURLWithPath:file.path)
            let info = try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            guard info.isRegularFile == true, let size = info.fileSize, size < 24_000_000 - total else { throw MailAppError.message("附件必须为普通文件，附件总大小请控制在 24 MB 以内。") }
            let handle = try FileHandle(forReadingFrom:url)
            let data: Data
            do { data = try handle.read(upToCount:24_000_000 - total) ?? Data(); try handle.close() } catch { try? handle.close(); throw error }
            total += data.count
            guard total < 24_000_000 else { throw MailAppError.message("附件总大小超过 24 MB，请减少附件。") }
            attachments.append(TransportAttachment(filename:file.name,data:data))
        }
        let outgoing = TransportOutgoing(from:draft.from,fromName:a.name,to:to,cc:cc,bcc:bcc,subject:draft.subject,body:draft.body,attachments:attachments,inReplyTo:draft.inReplyTo,references:draft.references)
        let c = try await connection(for:a)
        let sentFolder = a.sentFolder?.trimmingCharacters(in:.whitespacesAndNewlines)
        let result = try await MailTransport.send(c,message:outgoing,sentFolder:sentFolder?.isEmpty == false ? sentFolder : nil)
        // Once SMTP accepts, never report a later local save error as send failure.
        let receipt = CachedMessage(id:a.id.uuidString + "|local|" + draft.id.uuidString,accountID:a.id,folder:"__local_sent__",uid:0,subject:draft.subject,from:draft.from,to:to.joined(separator:", "),cc:cc.joined(separator:", "),date:Date(),preview:String(draft.body.prefix(150)),body:draft.body,html:nil,isRead:true,isFlagged:false,messageID:nil,references:draft.references,attachments:attachments.map{CachedAttachment(filename:$0.filename,mimeType:$0.mimeType,data:$0.data)},loaded:true)
        messages.append(receipt)
        do {try storage.saveMessages(messages)} catch {problem = "邮件服务商已接受发送，但本地已发送副本保存失败。请勿重复发送。"}
        var v = library; v.drafts.removeAll{$0.id == draft.id}
        do { try commit(v) } catch { problem = "邮件服务商已接受发送，但本地草稿清理失败，请勿重复发送。" }
        notice = "邮件服务商已接受发送"
        if let warning = result.sentCopyWarning { problem = warning }
    }
    private func notify(count: Int, account: MailAccount) {
        let content = UNMutableNotificationContent(); content.title = "搞邮件 · " + identityName(for:account); content.body = "\(account.displayName) 收到 \(count) 封新邮件"; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:UUID().uuidString,content:content,trigger:nil))
    }
    func askNotifications() { UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]) { _,_ in } }
    func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "搞邮件-资料备份.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try MailStorage.encoder.encode(library).write(to:url,options:.atomic); notice = "资料备份已导出（不含密码与邮件缓存）" } catch { publish(error) }
    }
    func restoreBackup() {
        guard busy.isEmpty && detailBusy.isEmpty && !sending && compose == nil else { problem = "请关闭写信窗口，并等待当前收发和读取结束。"; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var incoming = try MailStorage.decoder.decode(MailLibrary.self,from:Data(contentsOf:url)); try MailValidation.validate(incoming)
            let alert = NSAlert(); alert.messageText = "恢复资料备份？"; alert.informativeText = "将替换当前的身份、邮箱资料、平台记录和草稿，并清空当前邮件视图。备份内有 \(incoming.accounts.count) 个邮箱、\(incoming.platforms.count) 条平台记录。当前资料和邮件缓存（含本机发送记录）会先保存恢复前副本，存放在数据文件夹中。恢复后邮箱设为仅登记，请重新检查收发授权。"; alert.addButton(withTitle:"恢复"); alert.addButton(withTitle:"取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            for i in incoming.accounts.indices { incoming.accounts[i].enabled = false; incoming.accounts[i].syncError = nil; incoming.accounts[i].lastSync = nil }
            try storage.restore(incoming); library = incoming; messages = []; try storage.saveMessages([]); identityFilter = nil; mailboxFilter = nil; notice = "资料已恢复，请重新检查邮箱授权"
        } catch { publish(error) }
    }
    func exportCSV() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "搞邮件-关联平台.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try PlatformCSV.encode(library.platforms,accounts:library.accounts).write(to:url,atomically:true,encoding:.utf8); notice = "平台清单已导出" } catch { publish(error) }
    }
    func importCSV() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText,.plainText]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let rows = try PlatformCSV.parse(String(contentsOf:url,encoding:.utf8))
            guard let header = rows.first, header == PlatformCSV.headers else { throw MailAppError.message("CSV 表头不匹配。请先导出一份平台清单作为模板。") }
            var additions: [PlatformRecord] = []; var skipped = 0
            for (index,row) in rows.dropFirst().enumerated() {
                guard row.count == 9 else { throw MailAppError.message("CSV 第 \(index+2) 行列数不正确，未导入任何记录。") }
                guard !row[0].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw MailAppError.message("CSV 第 \(index+2) 行缺少平台名称。") }
                if !row[1].isEmpty && !MailValidation.address(row[1]) { throw MailAppError.message("CSV 第 \(index+2) 行邮箱格式不正确。") }
                if !row[3].isEmpty && MailValidation.webURL(row[3]) == nil { throw MailAppError.message("CSV 第 \(index+2) 行网址格式不正确。") }
                if (library.platforms + additions).contains(where:{$0.name == row[0] && $0.address == row[1] && $0.username == row[2]}) { skipped += 1; continue }
                let a = library.accounts.first {$0.allowedAddresses.contains(where:{$0.lowercased() == row[1].lowercased()})}
                additions.append(PlatformRecord(accountID:a?.id,name:row[0],url:row[3],username:row[2],address:row[1],kind:row[4],loginMethod:row[5],roles:row[6].components(separatedBy:" / "),status:row[7],notes:row[8],history:[PlatformHistory(text:"从 CSV 导入")]))
            }
            let alert = NSAlert(); alert.messageText = "导入 \(additions.count) 条平台关联？"; alert.informativeText = "跳过 \(skipped) 条重复记录。无法匹配到已添加邮箱的记录会保留地址，显示为未关联。"; alert.addButton(withTitle:"导入"); alert.addButton(withTitle:"取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            var v = library; v.platforms += additions; try commit(v); notice = "平台记录已导入"
        } catch { publish(error) }
    }
}
