import AppKit
import SwiftUI

struct MailFloatingView: View {
    @ObservedObject var store: MailStore
    @ObservedObject var controller: MailFloatingController
    @State private var selectedAccountID: UUID?
    private static let dragAreaHeight: CGFloat = 18

    private var summary: MailFloatingSummary {
        MailFloatingSummary(library: store.library, messages: store.messages, accountID: selectedAccountID)
    }
    private var syncing: Bool { !store.busy.isDisjoint(with: Set(summary.scopeAccounts.map(\.id))) }
    private var canSync: Bool { summary.enabledCount > 0 && !syncing }

    var body: some View {
        Group {
            if controller.isExpanded { card }
            else {
                let all = MailFloatingSummary(library:store.library,messages:store.messages)
                MailFloatingRailView(controller:controller,unreadCount:all.unreadCount,errorCount:all.errorCount + (store.problem == nil ? 0 : 1))
            }
        }
        .onChange(of: store.library.accounts.map(\.id)) { _, ids in
            if let selectedAccountID, !ids.contains(selectedAccountID) { self.selectedAccountID = nil }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            dragArea
            ScrollView(.vertical) {
                expandedContent
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: MailFloatingHeightPreferenceKey.self, value: geometry.size.height + Self.dragAreaHeight)
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: max(controller.expandedHeight - Self.dragAreaHeight, 0))
        }
        .frame(maxWidth: .infinity)
        .frame(height: controller.expandedHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .circular))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .circular).stroke(Color.primary.opacity(0.09), lineWidth: 1))
        .tint(.indigo)
        .onPreferenceChange(MailFloatingHeightPreferenceKey.self) { height in
            guard height.isFinite, height > 0 else { return }
            let ideal = ceil(height)
            controller.updateExpandedHeight(ideal)
        }
    }

    private var dragArea: some View {
        Color.clear.frame(maxWidth: .infinity).frame(height: min(Self.dragAreaHeight, controller.expandedHeight))
            .overlay(MailFloatingDragHandle().accessibilityHidden(true))
            .help("拖动顶部空白自由移动悬浮窗，靠近左右边缘时吸附")
    }

    private var accountPicker: some View {
        Menu {
            Button("全部邮箱 · \(MailFloatingSummary(library: store.library, messages: store.messages).unreadCount) 封缓存未读") { selectedAccountID = nil }
            if !summary.accounts.isEmpty { Divider() }
            ForEach(summary.accounts) { account in
                Button("\(account.displayName) · \(summary.unreadCount(for: account.id))") { selectedAccountID = account.id }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: summary.selectedAccount.map { store.identity($0.identityID)?.symbol ?? "envelope" } ?? "tray.full")
                    .foregroundStyle(.indigo)
                Text(summary.selectedAccount?.displayName ?? "全部邮箱").lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 29)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .background(MailFloatingMenuRegion())
        .accessibilityLabel("切换悬浮窗邮箱")
    }

    private var expandedContent: some View {
        VStack(spacing: 6) {
            accountPicker
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(summary.unreadCount)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("缓存未读 · 收件箱").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    statusBadge
                    Text("\(summary.enabledCount) 个启用 · \(summary.registeredCount) 个仅登记")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 64)
            .padding(.horizontal, 4)
            .background(MailFloatingDragHandle().allowsHitTesting(false).accessibilityHidden(true))
            .help("拖动未读统计区域自由移动悬浮窗，靠近左右边缘时吸附")
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                if summary.accounts.isEmpty { emptyAccounts }
                else if controller.showPreviews { previews }
                else { privateSummary }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Button { controller.openInbox(accountID: summary.selectedAccount?.id) } label: {
                    Label(summary.accounts.isEmpty ? "添加邮箱" : "收件箱", systemImage: summary.accounts.isEmpty ? "plus" : "tray")
                }.buttonStyle(.borderedProminent)
                Spacer(minLength: 0)
                Button { sync() } label: { Label("同步", systemImage: "arrow.clockwise") }
                    .disabled(!canSync).help("同步当前选择的已启用邮箱")
                Button { controller.compose(accountID: summary.selectedAccount?.id) } label: { Label("写信", systemImage: "square.and.pencil") }
            }
            .font(.system(size: 11)).controlSize(.small)
            footer
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            if syncing { ProgressView().controlSize(.mini) }
            else { Image(systemName: summary.errorCount > 0 || store.problem != nil ? "exclamationmark.circle" : "tray") }
            Text(syncing ? "正在同步" : summary.errorCount > 0 ? "\(summary.errorCount) 个邮箱待检查" : store.problem != nil ? "操作待处理" : "本机缓存")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle((summary.errorCount > 0 || store.problem != nil) && !syncing ? Color.orange : Color.indigo)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(((summary.errorCount > 0 || store.problem != nil) && !syncing ? Color.orange : Color.indigo).opacity(0.08), in: Capsule())
    }

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(MailFloatingSummary(library: store.library, messages: store.messages, accountID: selectedAccountID, now: context.date).latestSyncLabel)
            }
            Spacer(minLength: 8)
            Text("最近同步范围").help("只统计已缓存的收件箱邮件，并非服务商的完整未读总数")
        }.font(.system(size: 9)).foregroundStyle(.secondary)
    }

    private var emptyAccounts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("把邮箱带到桌面").font(.system(size: 13, weight: .semibold))
            Text("添加邮箱后，在这里查看缓存未读数量和同步状态。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.indigo.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private var privateSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("邮件预览已隐藏", systemImage: "eye.slash")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(summary.unreadCount > 0 ? "有 \(summary.unreadCount) 封缓存未读邮件，打开收件箱查看。" : "当前缓存中没有未读邮件。")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Text("在设置的外观页开启邮件预览，可显示最近三封邮件的发件人和主题。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if summary.errorCount > 0 || store.problem != nil { checkAccounts }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private var previews: some View {
        if summary.unreadMessages.isEmpty {
            Label("暂无缓存未读邮件", systemImage: "envelope.open").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
        } else {
            ForEach(summary.unreadMessages) { message in
                Button { controller.openInbox(accountID: message.accountID, messageID: message.id) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.indigo).frame(width: 5, height: 5).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(message.from.isEmpty ? "未知发件人" : message.from).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(message.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Text(message.subject.isEmpty ? "（无主题）" : message.subject).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(store.account(message.accountID)?.displayName ?? "").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityLabel("打开邮件：" + message.subject)
            }
        }
        if summary.errorCount > 0 || store.problem != nil { checkAccounts }
    }

    private var checkAccounts: some View {
        Button(store.problem != nil ? "查看操作提示" : "查看邮箱状态") {
            controller.openInbox(accountID: summary.selectedAccount?.id)
            if store.problem == nil { store.route = "accounts" }
        }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.orange)
    }

    private func sync() {
        guard canSync else { return }
        let accountID = summary.selectedAccount?.id
        Task {
            if let accountID { await store.sync(accountID) }
            else { await store.syncAll() }
        }
    }
}

/// Read the intrinsic expanded content only; the 104-point edge rail never publishes a card height.
private struct MailFloatingHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
