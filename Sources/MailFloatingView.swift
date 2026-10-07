import AppKit
import SwiftUI

struct MailFloatingView: View {
    @ObservedObject var store: MailStore
    @ObservedObject var controller: MailFloatingController
    @State private var selectedAccountID: UUID?

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
        VStack(spacing: 10) {
            header
            if controller.isCompact { compactContent }
            else { expandedContent }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))
        .tint(.indigo)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
                .frame(height: 28)
                .overlay(MailFloatingDragHandle().accessibilityHidden(true))
                .help("拖动顶部空白移动悬浮窗，松手吸附左右边缘")
            FloatingMailIcon(symbol: controller.isPinned ? "pin.fill" : "pin", title: controller.isPinned ? "取消固定" : "固定展开悬浮窗", active: controller.isPinned) {
                controller.isPinned.toggle()
            }
            FloatingMailIcon(symbol: controller.isCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", title: controller.isCompact ? "展开悬浮窗" : "切换紧凑模式") {
                controller.isCompact.toggle()
            }
            Menu {
                Toggle("显示邮件预览", isOn: $controller.showPreviews)
                Toggle("固定展开悬浮窗", isOn: $controller.isPinned)
                Toggle("紧凑模式", isOn: $controller.isCompact)
                Menu("透明度") {
                    ForEach([1.0, 0.9, 0.8, 0.65], id: \.self) { value in
                        Button { controller.opacity = value } label: {
                            if abs(controller.opacity - value) < 0.001 { Label("\(Int(value * 100))%", systemImage: "checkmark") }
                            else { Text("\(Int(value * 100))%") }
                        }
                    }
                }
                Button("重置悬浮窗位置", action: controller.resetPosition)
                Button("收起到屏幕边缘", action:controller.collapse)
                Divider()
                Button("悬浮窗设置…", action: controller.openSettings)
                Button("隐藏悬浮窗", action: controller.hide)
            } label: {
                Image(systemName: "ellipsis").frame(width: 25, height: 28).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("悬浮窗选项").accessibilityLabel("悬浮窗选项")
            FloatingMailIcon(symbol: "xmark", title: "收起到屏幕边缘") { controller.collapse() }
        }
        .frame(height: 28)
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
        .accessibilityLabel("切换悬浮窗邮箱")
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            accountPicker
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(summary.unreadCount)).font(.system(size: 46, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("缓存未读 · 收件箱").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    statusBadge
                    Text("\(summary.enabledCount) 个启用 · \(summary.registeredCount) 个仅登记")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 75)
            .padding(.horizontal, 4)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if summary.accounts.isEmpty { emptyAccounts }
                    else if controller.showPreviews { previews }
                    else { privateSummary }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
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

    private var compactContent: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 7) {
                Button { controller.openInbox(accountID: summary.selectedAccount?.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(String(summary.unreadCount)).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("缓存未读").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).help("打开收件箱")
                Spacer(minLength: 0)
                FloatingMailIcon(symbol: "arrow.clockwise", title: "同步邮箱") { sync() }.disabled(!canSync)
                FloatingMailIcon(symbol: "square.and.pencil", title: "写邮件") { controller.compose(accountID: summary.selectedAccount?.id) }
            }
            HStack {
                Text(summary.selectedAccount?.displayName ?? "全部邮箱").lineLimit(1)
                Spacer(minLength: 8)
                compactStatus
            }.font(.system(size: 10)).foregroundStyle(.secondary)
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

    @ViewBuilder private var compactStatus: some View {
        if syncing { Text("正在同步…") }
        else if summary.errorCount > 0 || store.problem != nil { Label("待检查", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
        else { TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(MailFloatingSummary(library: store.library, messages: store.messages, accountID: selectedAccountID, now: context.date).latestSyncLabel)
        } }
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
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "envelope.badge").font(.system(size: 22)).foregroundStyle(.indigo)
            Text("把邮箱带到桌面").font(.system(size: 13, weight: .semibold))
            Text("添加邮箱后，在这里查看未读数量和同步状态。学校、工作和生活，各有自己的位置。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("可拖动顶部移动，或切换紧凑模式。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.indigo.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private var privateSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("邮件预览已隐藏", systemImage: "eye.slash")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(summary.unreadCount > 0 ? "有 \(summary.unreadCount) 封缓存未读邮件，打开收件箱查看。" : "当前缓存中没有未读邮件。")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Text("在右上角选项中开启预览，可显示最近三封邮件的发件人和主题。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if summary.errorCount > 0 || store.problem != nil { checkAccounts }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private var previews: some View {
        if summary.unreadMessages.isEmpty {
            Label("暂无缓存未读邮件", systemImage: "envelope.open").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 16)
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

private struct FloatingMailIcon: View {
    let symbol: String
    let title: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? Color.indigo : Color.secondary)
                .frame(width: 25, height: 28).contentShape(Rectangle())
                .background(active ? Color.indigo.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}
