import Foundation

@main
@MainActor
struct StoreTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(name)") }
    }
    static func expectError(_ name: String, _ work: () throws -> Void) {
        do { try work(); fatalError("FAIL: \(name)") } catch { checks += 1 }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GaoMailStoreTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        expect(store.library.accounts.isEmpty && store.messages.isEmpty, "new store starts without invented data")
        let identity = MailIdentity(name: "科研", symbol: "flask", color: "123456")
        try store.saveIdentity(identity)
        var account = MailAccount(name: "实验邮箱", email: "personal@example.invalid", identityID: identity.id)
        try store.saveAccount(account, password: nil)
        account = store.account(account.id)!
        expect(account.username == account.email && !account.enabled, "registration-only account normalization")
        let before = store.library.accounts
        var renamedAddress = account
        renamedAddress.email = "someoneelse@example.invalid"
        expectError("account email cannot mutate existing identity") { try store.saveAccount(renamedAddress, password: nil) }
        expect(store.library.accounts == before, "failed account edit has no partial effects")
        var duplicate = account
        duplicate.id = UUID()
        duplicate.email = "PERSONAL@example.invalid"
        expectError("case-insensitive duplicate account rejected") { try store.saveAccount(duplicate, password: nil) }
        var invalidAlias = account
        invalidAlias.aliases = "valid@example.invalid, malformed"
        expectError("invalid alias rejected") { try store.saveAccount(invalidAlias, password: nil) }
        var platform = PlatformRecord(accountID: account.id, name: "论文系统", url: "example.invalid/submit", username: "researcher")
        try store.savePlatform(platform)
        platform = store.library.platforms.first!
        expect(platform.address == account.email && platform.url == "https://example.invalid/submit", "platform inherits address and normalizes URL")
        platform.status = "已换绑"
        platform.address = "new@example.invalid"
        try store.savePlatform(platform)
        expect(store.library.platforms[0].history.count == 2 && store.library.platforms[0].history.last!.text.contains("personal@example.invalid → new@example.invalid"), "platform change history preserves original binding")
        let invalidURL = PlatformRecord(accountID: account.id, name: "Bad", url: "javascript:alert(1)")
        expectError("active URL schemes rejected") { try store.savePlatform(invalidURL) }
        store.identityFilter = identity.id
        store.search = "论文系统"
        expect(store.filteredPlatforms.count == 1, "platform reverse lookup respects identity")
        var draft = MailDraft(accountID: account.id, from: account.email, to: "recipient@example.invalid", subject: "草稿", body: "第一版")
        try store.saveDraft(draft)
        draft.body = "第二版"
        try store.saveDraft(draft)
        expect(store.library.drafts.count == 1 && store.library.drafts[0].body == "第二版", "autosave replaces one draft without duplicating")
        let source = TransportMessage(uid: 9, uidValidity: 123, subject: "实际邮件", from: "Sender <from@example.invalid>", to: account.email, cc: "", replyTo: "Replies <reply@example.invalid>", date: Date(), body: "正文", attachments: [TransportAttachment(filename: "附件.txt", mimeType: "text/plain", data: Data([1, 2, 3]))], isRead: false, isFlagged: true, messageID: "<stable@example.invalid>", bodyLoaded: true)
        let mapped = store.cached(source, accountID: account.id, folder: "INBOX")
        expect(mapped.uidValidity == 123 && mapped.id.contains("|123|9") && mapped.replyTo == source.replyTo, "UID generation and Reply-To survive cache mapping")
        expect(mapped.attachments[0].data == Data([1, 2, 3]) && mapped.loaded && mapped.isFlagged, "cache maps attachment payload and flags")
        var anotherGeneration = source
        anotherGeneration.uidValidity = 124
        expect(store.cached(anotherGeneration, accountID: account.id, folder: "INBOX").id != mapped.id, "same UID different mailbox generation has different identity")
        store.reply(mapped)
        expect(store.compose?.to == "reply@example.invalid" && store.compose?.from == account.email && store.compose?.inReplyTo == source.messageID, "reply respects reply address and original receiving identity")
        store.compose = nil
        store.messages = [mapped]
        store.search = "正文"
        expect(store.filteredMessages.count == 1, "cached body remains searchable")
        store.busy.insert(account.id)
        expectError("active account edit blocked") { try store.saveAccount(account, password: nil) }
        store.busy.remove(account.id)
        let persisted = store.storage.load()
        expect(persisted.platforms.count == 1 && persisted.drafts.count == 1 && persisted.accounts[0].identityID == identity.id, "metadata survives reload")
        store.deleteIdentity(identity.id)
        expect(store.account(account.id)?.identityID == nil && store.library.platforms.count == 1, "identity removal retains mailbox and platform data")
        store.deleteDraft(draft.id)
        expect(store.library.drafts.isEmpty, "draft deletion persists")
        do { try await store.send(draft); fatalError("Disabled mailbox sent") } catch { checks += 1 }
        expect(!store.sending, "rejected send never enters active sending state")
        print("PASS: \(checks) Store assertions; temporary data only, no keychain access or network calls")
    }
}
