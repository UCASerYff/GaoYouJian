import Foundation

@main
struct FloatingSummaryTests {
    static var checks = 0
    static var failures: [String] = []
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        checks += 1
        if !condition() { failures.append(description) }
    }

    static func message(_ id: String, account: MailAccount, folder: String = "INBOX", read: Bool = false, secondsAgo: TimeInterval = 100) -> CachedMessage {
        CachedMessage(id: id, accountID: account.id, folder: folder, uid: 1,
                      subject: "本地测试", from: "sender@example.org", to: account.email, cc: "",
                      date: now.addingTimeInterval(-secondsAgo), preview: "隔离测试摘要", body: "",
                      isRead: read, isFlagged: false, attachments: [], loaded: false)
    }

    static func main() {
        var school = MailAccount()
        school.name = "学校"; school.email = "school@example.edu.cn"; school.enabled = true
        school.identityID = MailIdentity.defaults[0].id
        school.lastSync = now.addingTimeInterval(-120)
        var work = MailAccount()
        work.name = "工作"; work.email = "work@example.cn"; work.enabled = true
        work.identityID = MailIdentity.defaults[1].id
        work.syncError = "授权已失效"
        var life = MailAccount()
        life.name = "生活"; life.email = "life@example.org"
        life.identityID = MailIdentity.defaults[2].id
        life.lastSync = now.addingTimeInterval(-3_600)
        life.syncError = " \n "
        let removed = MailAccount()
        var library = MailLibrary()
        library.accounts = [school, work, life]

        let messages = [
            message("c", account: school, secondsAgo: 100),
            message("b", account: school, folder: "inbox", secondsAgo: 100),
            message("a", account: life, folder: "InBoX", secondsAgo: 100),
            message("d", account: work, secondsAgo: 200),
            message("e", account: school, secondsAgo: 300),
            message("already-read", account: school, read: true, secondsAgo: 1),
            message("sent", account: school, folder: "Sent", secondsAgo: 1),
            message("nested-inbox", account: school, folder: "INBOX/News", secondsAgo: 1),
            message("spaced-inbox", account: school, folder: " INBOX ", secondsAgo: 1),
            message("orphan", account: removed, secondsAgo: 1)
        ]
        let all = MailFloatingSummary(library: library, messages: messages, now: now)
        check(all.accounts.map(\.id) == library.accounts.map(\.id), "Mailbox selector preserves registration order")
        check(all.selectedAccount == nil, "All-mailbox scope has no selected account")
        check(all.scopeAccounts.count == 3, "All identities contribute to default floating summary")
        check(all.unreadCount == 5, "Unread excludes read, non-INBOX and removed-account cache")
        check(all.unreadCount(for: school.id) == 3, "INBOX matching is case insensitive")
        check(all.unreadCount(for: life.id) == 1, "Disabled mailbox retains real cached unread")
        check(all.unreadCount(for: removed.id) == 0, "Orphan cache does not create mailbox badge")
        check(all.enabledCount == 2, "Enabled count is configuration, without assuming authorization")
        check(all.registeredCount == 1, "Registration-only count excludes enabled accounts")
        check(all.errorCount == 1, "Empty or whitespace sync errors are not counted")
        check(all.latestSync == school.lastSync, "Latest sync ignores accounts that have never synced")
        check(all.latestSyncLabel == "2 分钟前同步", "Sync label uses injected current time")
        check(all.unreadMessages.map(\.id) == ["a", "b", "c"], "Preview cap is three and timestamp ties sort by ID")
        let reversed = MailFloatingSummary(library: library, messages: messages.reversed(), now: now)
        check(reversed.unreadMessages.map(\.id) == all.unreadMessages.map(\.id), "Preview ordering is stable across cache ordering")

        let selected = MailFloatingSummary(library: library, messages: messages, accountID: school.id, now: now)
        check(selected.selectedAccount?.id == school.id, "Existing mailbox selection is retained")
        check(selected.accounts.count == 3 && selected.scopeAccounts.count == 1, "Selection narrows stats while keeping all selector choices")
        check(selected.unreadCount == 3, "Selected mailbox excludes other identity inboxes")
        check(selected.unreadMessages.map(\.id) == ["b", "c", "e"], "Selected mailbox previews include only its cache")
        check(selected.enabledCount == 1 && selected.registeredCount == 0, "Enabled status respects selected scope")
        check(selected.errorCount == 0, "Other-mailbox error does not pollute selected summary")
        check(selected.unreadCount(for: life.id) == 1, "Other-mailbox picker badges remain available in selected scope")

        let unsynced = MailFloatingSummary(library: library, messages: messages, accountID: work.id, now: now)
        check(unsynced.latestSync == nil && unsynced.latestSyncLabel == "尚未同步", "Enabled but unsynced account has no invented sync date")
        check(unsynced.errorCount == 1 && unsynced.unreadCount == 1, "Error and cached mail can coexist accurately")
        let disabled = MailFloatingSummary(library: library, messages: messages, accountID: life.id, now: now)
        check(disabled.enabledCount == 0 && disabled.registeredCount == 1, "Disabled selection is registration only")
        check(disabled.latestSync == life.lastSync && disabled.latestSyncLabel == "1 小时前同步", "Historical disabled-account sync remains visible")

        var afterDeletion = library
        afterDeletion.accounts.removeAll { $0.id == school.id }
        let deletion = MailFloatingSummary(library: afterDeletion, messages: messages, accountID: school.id, now: now)
        check(deletion.selectedAccount == nil && deletion.scopeAccounts.count == 2, "Deleted selected mailbox falls back to all remaining accounts")
        check(deletion.unreadCount == 2 && deletion.unreadCount(for: school.id) == 0, "Deleted-account messages immediately disappear from summary")
        check(deletion.latestSync == life.lastSync, "Deleted mailbox cannot supply latest sync")
        let unknown = MailFloatingSummary(library: library, messages: messages, accountID: removed.id, now: now)
        check(unknown.selectedAccount == nil && unknown.unreadCount == all.unreadCount, "Unknown stale selection falls back to all known accounts")
        let empty = MailFloatingSummary(library: MailLibrary(), messages: messages, now: now)
        check(empty.unreadCount == 0 && empty.unreadMessages.isEmpty, "Empty library ignores all orphan messages")
        check(empty.enabledCount == 0 && empty.registeredCount == 0 && empty.errorCount == 0, "Empty library has zero configuration counts")
        check(empty.latestSync == nil && empty.latestSyncLabel == "尚未同步", "Empty library has no fake sync")

        for (secondsAgo, expected) in [(0.0, "刚刚同步"), (59.0, "刚刚同步"), (60.0, "1 分钟前同步"), (86_400.0, "1 天前同步"), (-600.0, "刚刚同步")] {
            var timed = library
            timed.accounts = [school]
            timed.accounts[0].lastSync = now.addingTimeInterval(-secondsAgo)
            let summary = MailFloatingSummary(library: timed, messages: [], now: now)
            check(summary.latestSyncLabel == expected, "Relative sync boundary \(secondsAgo)")
        }
        var old = library
        old.accounts = [school]
        old.accounts[0].lastSync = now.addingTimeInterval(-604_800)
        check(MailFloatingSummary(library: old, messages: [], now: now).latestSyncLabel.hasPrefix("同步于 "), "Old sync displays actual calendar timestamp")

        if failures.isEmpty { print("Floating summary tests passed (\(checks) checks)") }
        else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
