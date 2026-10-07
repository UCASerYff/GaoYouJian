import Foundation

@main
struct ModelTests {
    static var checks = 0
    static var failures: [String] = []
    static func check(_ condition: @autoclosure () throws -> Bool, _ description: String) {
        checks += 1
        do { if try !condition() { failures.append(description) } }
        catch { failures.append("\(description): \(error.localizedDescription)") }
    }
    static func rejects(_ description: String, _ body: () throws -> Void) {
        checks += 1
        do { try body(); failures.append(description) } catch { }
    }
    static func test(_ title: String, _ body: () throws -> Void) {
        do { try body() } catch { failures.append("\(title): \(error.localizedDescription)") }
    }
    static func fixture() -> MailLibrary {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var library = MailLibrary()
        library.identities = [MailIdentity(name: "科研 / 学校", symbol: "graduationcap.fill", color: "6366F1")]
        var account = MailAccount()
        account.email = "research@example.edu.cn"; account.username = account.email
        account.identityID = library.identities[0].id; account.name = "学校邮箱"
        account.aliases = "alias@example.edu.cn"; account.lastSync = date
        library.accounts = [account]
        library.platforms = [PlatformRecord(accountID: account.id, name: "投稿平台，测试", url: "https://example.org/login", username: "研究者 \"甲\"", address: "alias@example.edu.cn", kind: "网站", loginMethod: "邮箱登录", roles: ["登录", "找回"], status: "使用中", notes: "第一行\r\n第二行😀\n第三行\"引用\",逗号", checkedAt: date, updatedAt: date, history: [PlatformHistory(date: date, text: "曾换绑旧邮箱")])]
        library.drafts = [MailDraft(accountID: account.id, from: account.email, to: "colleague@example.org", cc: "", bcc: "", subject: "草稿主题", body: "未发送正文\n保留原文😀", attachments: [DraftAttachment(path: "/tmp/example-not-a-real-attachment.pdf")], inReplyTo: "<thread@example.org>", references: "<thread@example.org>", updatedAt: date)]
        return library
    }
    static func main() {
        test("Address validation") {
            check(MailValidation.address("研究者@example.edu.cn"), "Unicode email local-part rejected")
            check(MailValidation.address("first.last+tag@example.cn"), "Tagged address rejected")
            for bad in ["name", "a@@example.cn", "a b@example.cn", "a@example", "<a@example.cn>", "a@example.cn\r\nBcc: b@example.cn"] {
                check(!MailValidation.address(bad), "Malformed address accepted: \(bad)")
            }
            check(MailValidation.recipients(" a@example.cn，b@example.cn; c@example.cn\n") == ["a@example.cn", "b@example.cn", "c@example.cn"], "Recipient separators not normalized")
            check(MailValidation.bareAddress("张三 <a@example.cn>") == "a@example.cn", "Mailbox display name extraction")
            check(MailValidation.webURL("example.org/path")?.absoluteString == "https://example.org/path", "Default HTTPS URL missing")
            for bad in ["file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.org", "data:text/plain,hello", ""] {
                check(MailValidation.webURL(bad) == nil, "Unsafe or empty URL accepted: \(bad)")
            }
        }
        test("Library validation") {
            let valid = fixture()
            try MailValidation.validate(valid)
            checks += 1
            var bad = valid; bad.schemaVersion = 999
            rejects("Unsupported schema accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts.append(bad.accounts[0])
            rejects("Duplicate account IDs accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.identities.append(bad.identities[0])
            rejects("Duplicate identity IDs accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.platforms.append(bad.platforms[0])
            rejects("Duplicate platform IDs accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.drafts.append(bad.drafts[0])
            rejects("Duplicate draft IDs accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts[0].identityID = UUID()
            rejects("Orphan mailbox identity accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.platforms[0].accountID = UUID()
            rejects("Orphan platform mailbox accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts[0].smtpPort = 70000
            rejects("Invalid SMTP port accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.platforms[0].name = " \n"
            rejects("Blank platform accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.drafts[0].accountID = UUID()
            rejects("Orphan draft mailbox accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts[0].auth = "arbitrary-provider"
            rejects("Unknown auth method accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts[0].imapTLS = "plaintext"
            rejects("Unknown TLS mode accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts[0].aliases = "not-an-email"
            rejects("Invalid alias accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.platforms[0].address = "not-an-email"
            rejects("Invalid platform address accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.platforms[0].url = "file:///etc/passwd"
            rejects("Unsafe imported platform URL accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.preferences.fetchLimit = 0
            rejects("Nonpositive fetch limit accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.preferences.syncMinutes = 0
            rejects("Nonpositive sync interval accepted") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts[0].enabled = true
            rejects("Enabled account without servers accepted") { try MailValidation.validate(bad) }
            bad.accounts[0].imapHost = "imap.example.edu.cn"; bad.accounts[0].smtpHost = "smtp.example.edu.cn"
            try MailValidation.validate(bad); checks += 1
            bad.accounts[0].imapHost = "imap.example.cn/path"
            rejects("Enabled account with URL/path host accepted") { try MailValidation.validate(bad) }
            bad = valid; var duplicate = bad.accounts[0]; duplicate.id = UUID(); duplicate.email = duplicate.email.uppercased(); bad.accounts.append(duplicate)
            rejects("Duplicate mailbox email accepted with different record ID") { try MailValidation.validate(bad) }
            bad = valid; bad.accounts[0].sentFolder = "已发送 / Sent Items"
            try MailValidation.validate(bad); checks += 1
            bad.accounts[0].sentFolder = "Sent\r\nUID STORE"
            rejects("Folder control characters accepted") { try MailValidation.validate(bad) }
        }
        test("CSV Unicode/quotes/newlines") {
            let library = fixture()
            let encoded = PlatformCSV.encode(library.platforms, accounts: library.accounts)
            check(encoded.hasPrefix("\u{FEFF}"), "CSV UTF-8 BOM absent")
            let rows = try PlatformCSV.parse(encoded)
            check(rows.count == 2, "Exported CSV row count changed")
            if rows.count == 2 {
                check(rows[0] == PlatformCSV.headers, "CSV headers changed")
                check(rows[1].count == 9, "CSV quoted fields split into extra columns")
                if rows[1].count == 9 {
                    check(rows[1][0] == library.platforms[0].name, "CSV Unicode/comma title changed")
                    check(rows[1][2] == library.platforms[0].username, "CSV quoted username changed")
                    check(rows[1][8] == library.platforms[0].notes, "CSV multiline/Unicode note changed")
                }
            }
            check(try PlatformCSV.parse("a,b\r\nc,d\r\n") == [["a","b"],["c","d"]], "Unquoted CRLF parsing")
            check(try PlatformCSV.parse("a,b\nc,d\n") == [["a","b"],["c","d"]], "LF parsing")
            check(try PlatformCSV.parse("\"a,b\",\"say \"\"hi\"\"\"\n") == [["a,b","say \"hi\""]], "Doubled quote parsing")
            check(try PlatformCSV.parse("a,b,") == [["a","b",""]], "Trailing empty field lost")
            for malformed in ["\"unclosed", "\"closed\"extra,next", "a\"b,c"] {
                rejects("Malformed CSV accepted: \(malformed)") { _ = try PlatformCSV.parse(malformed) }
            }
        }
        test("CSV spreadsheet formula safety") {
            for formula in ["=HYPERLINK(\"https://example.org\")", "+1", "-2", "@SUM(A1)", "\t=1"] {
                var record = PlatformRecord(); record.name = formula
                let text = PlatformCSV.encode([record], accounts: [])
                check(text.contains("\"'" + formula.replacingOccurrences(of: "\"", with: "\"\"")), "CSV executable formula not escaped")
            }
        }
        test("Backup schema and roundtrip") {
            let library = fixture()
            let data = try MailStorage.encoder.encode(library)
            let decoded = try MailStorage.decoder.decode(MailLibrary.self, from: data)
            check(decoded.accounts == library.accounts, "Account data changed in backup")
            check(decoded.identities == library.identities, "Identity data changed in backup")
            check(decoded.platforms == library.platforms, "Platform history or relationships changed in backup")
            check(decoded.drafts == library.drafts, "Draft text/attachments/threads changed in backup")
            let object = try JSONSerialization.jsonObject(with: data)
            let forbidden = Set(["password", "clientSecret", "accessToken", "refreshToken", "oauthToken", "googleClientSecret"])
            func containsSecretKey(_ object: Any) -> Bool {
                if let dictionary = object as? [String: Any] { return !Set(dictionary.keys).isDisjoint(with: forbidden) || dictionary.values.contains(where: containsSecretKey) }
                if let list = object as? [Any] { return list.contains(where: containsSecretKey) }
                return false
            }
            check(!containsSecretKey(object), "Backup contains credential fields")
            // Optional additions remain compatible with JSON produced before the fields existed.
            var accountJSON = try JSONSerialization.jsonObject(with: MailStorage.encoder.encode(library.accounts[0])) as! [String: Any]
            accountJSON.removeValue(forKey: "sentFolder")
            let accountData = try JSONSerialization.data(withJSONObject: accountJSON)
            check(try MailStorage.decoder.decode(MailAccount.self, from: accountData).sentFolder == nil, "Missing optional sent folder breaks decode")
            let message = CachedMessage(id: "fixture", accountID: library.accounts[0].id, folder: "INBOX", uid: 42, subject: "Cache", from: "sender@example.cn", to: library.accounts[0].email, cc: "", date: Date(timeIntervalSince1970: 1_800_000_000), preview: "", body: "", isRead: false, isFlagged: false, attachments: [], loaded: false)
            var messageJSON = try JSONSerialization.jsonObject(with: MailStorage.encoder.encode(message)) as! [String: Any]
            messageJSON.removeValue(forKey: "uidValidity"); messageJSON.removeValue(forKey: "replyTo")
            let messageData = try JSONSerialization.data(withJSONObject: messageJSON)
            let restoredMessage = try MailStorage.decoder.decode(CachedMessage.self, from: messageData)
            check(restoredMessage.uidValidity == nil && restoredMessage.replyTo == nil, "Old cache optional fields break decode")
        }
        test("Atomic storage, corruption, and restore") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("GaoYouJian-ModelTests-" + UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = MailStorage(root: root)
            var library = fixture()
            try store.save(library)
            let initial = try Data(contentsOf: store.libraryURL)
            check(store.load().platforms == library.platforms, "Saved platform data not loaded")
            library.platforms[0].notes += "\n更新"
            try store.save(library)
            check(try Data(contentsOf: root.appendingPathComponent("Library.previous.json")) == initial, "Previous valid snapshot lost")
            let corrupt = Data("{ broken json original must survive".utf8)
            try corrupt.write(to: store.libraryURL)
            _ = store.load()
            check(store.readFailure != nil, "Corrupt library did not block saving")
            rejects("Corrupt library overwritten by empty defaults") { try store.save(MailLibrary()) }
            check(try Data(contentsOf: store.libraryURL) == corrupt, "Original corrupt bytes were overwritten")
            var invalid = library; invalid.accounts[0].identityID = UUID()
            rejects("Invalid restore accepted") { try store.restore(invalid) }
            check(try Data(contentsOf: store.libraryURL) == corrupt, "Invalid restore overwrote original")
            try store.restore(library)
            check(store.readFailure == nil, "Successful restore did not clear read lock")
            check(store.load().drafts == library.drafts, "Restore lost draft content")
            let snapshots = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("BeforeRestore-") }
            check(snapshots.count == 1, "Restore did not keep previous file")
            if let snapshot = snapshots.first { check(try Data(contentsOf: snapshot) == corrupt, "Restore recovery snapshot did not preserve original bytes") }
            try store.restore(library)
            let afterSecondRestore = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("BeforeRestore-") }
            check(afterSecondRestore.count == 2, "Quick successive restores collided or overwrote recovery copy")
            try store.saveMessages([])
            let rootMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
            check(rootMode?.intValue == 0o700, "Private storage directory permissions")
            for file in [store.libraryURL, root.appendingPathComponent("Library.previous.json"), root.appendingPathComponent("MailCache.json")] + afterSecondRestore {
                let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
                check(mode?.intValue == 0o600, "Private file permissions: \(file.lastPathComponent)")
            }
        }
        test("Corrupt cache quarantine preserves local sent receipts") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("GaoYouJian-CacheTests-" + UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = MailStorage(root: root)
            try store.saveMessages([])
            let cache = root.appendingPathComponent("MailCache.json")
            let corrupt = Data("[{broken __local_sent__ receipt must survive".utf8)
            try corrupt.write(to: cache)
            check(store.loadMessages().isEmpty, "Corrupt cache unexpectedly decoded")
            check(store.cacheWarning != nil, "Corrupt cache warning not surfaced")
            let preserved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("MailCache.corrupt.") }
            check(preserved.count == 1, "Corrupt cache was not quarantined")
            if let snapshot = preserved.first {
                check(try Data(contentsOf: snapshot) == corrupt, "Corrupt cache bytes lost")
                let mode = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.posixPermissions] as? NSNumber
                check(mode?.intValue == 0o600, "Corrupt cache snapshot not private")
            }
            try store.saveMessages([])
            if let snapshot = preserved.first { check(try Data(contentsOf: snapshot) == corrupt, "Sync destroyed quarantined local sent receipt") }
            // A non-file cache cannot be safely quarantined; writes must remain blocked.
            try FileManager.default.removeItem(at: cache)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
            let marker = cache.appendingPathComponent("keep-this-record")
            try Data("keep".utf8).write(to: marker)
            let blocked = MailStorage(root: root)
            _ = blocked.loadMessages()
            check(blocked.cacheWarning != nil, "Unpreservable cache lacked warning")
            rejects("Unpreservable cache write was allowed") { try blocked.saveMessages([]) }
            check(try String(contentsOf: marker, encoding: .utf8) == "keep", "Write attempt destroyed unpreserved cache path")
            try FileManager.default.removeItem(at: cache)
            try corrupt.write(to: cache)
            try blocked.restore(fixture()) // Successful preservation now permits explicit restoration.
            try blocked.saveMessages([])
            check(blocked.cacheWarning == nil && blocked.loadMessages().isEmpty, "Successful restore did not clear repaired cache write block")
        }
        test("Restore preserves local sent receipts before clearing cache") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("GaoYouJian-RestoreMailTests-" + UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = MailStorage(root: root)
            let library = fixture()
            try store.save(library)
            let receipt = CachedMessage(id: "local-receipt", accountID: library.accounts[0].id, folder: "__local_sent__", uid: 0, subject: "已发送的唯一副本", from: library.accounts[0].email, to: "colleague@example.org", cc: "", date: Date(timeIntervalSince1970: 1_800_000_000), preview: "唯一正文", body: "唯一正文\n与服务器缓存一起保全", isRead: true, isFlagged: false, messageID: "<receipt@example.org>", attachments: [], loaded: true)
            try store.saveMessages([receipt])
            let cacheURL = root.appendingPathComponent("MailCache.json")
            let receiptBytes = try Data(contentsOf: cacheURL)
            var incoming = library; incoming.platforms[0].notes = "恢复后的资料"
            try store.restore(incoming)
            try store.saveMessages([]) // Matches the application's explicit restore flow.
            let snapshots = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("MailCache.beforeRestore.") }
            check(snapshots.count == 1, "Restore did not preserve current mail cache")
            if let snapshot = snapshots.first {
                check(try Data(contentsOf: snapshot) == receiptBytes, "Restore changed original local sent bytes")
                check(try MailStorage.decoder.decode([CachedMessage].self, from: Data(contentsOf: snapshot)) == [receipt], "Local sent receipt cannot be recovered")
                let mode = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.posixPermissions] as? NSNumber
                check(mode?.intValue == 0o600, "Restore mail snapshot not private")
            }
            check(store.loadMessages().isEmpty, "Explicit restore did not permit cleared cache")
            // If the current cache cannot be safely preserved, restore must not replace the library.
            let savedLibrary = try Data(contentsOf: store.libraryURL)
            try FileManager.default.removeItem(at: cacheURL)
            try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: false)
            rejects("Restore replaced library without preserving unsafe cache") { try store.restore(library) }
            check(try Data(contentsOf: store.libraryURL) == savedLibrary, "Failed cache snapshot allowed library replacement")
        }
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            fputs("Model tests: \(failures.count) failures in \(checks) checks.\n", stderr)
            exit(1)
        }
        print("Model tests passed: \(checks) checks; temporary data cleaned.")
    }
}
