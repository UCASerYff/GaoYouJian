import AppKit
import SwiftUI

@main @MainActor struct GaoYouJianApp: App {
    @NSApplicationDelegateAdaptor(MailAppDelegate.self) private var delegate
    @StateObject private var store: MailStore
    @StateObject private var floating: MailFloatingController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    init() {
        var root: URL?
        #if DEBUG_TESTING
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GaoYouJian-Testing-" + String(ProcessInfo.processInfo.processIdentifier),isDirectory:true)
        if let i = CommandLine.arguments.firstIndex(of:"--data-dir"), CommandLine.arguments.count > i+1 {
            root = URL(fileURLWithPath:CommandLine.arguments[i+1],isDirectory:true)
        }
        #endif
        let mailStore = MailStore(root:root)
        _store = StateObject(wrappedValue:mailStore)
        var floatingDefaults = UserDefaults.standard
        #if DEBUG_TESTING
        if let root { floatingDefaults = UserDefaults(suiteName:"GaoYouJian.FloatingTest." + root.lastPathComponent) ?? .standard }
        #endif
        _floating = StateObject(wrappedValue:MailFloatingController(store:mailStore, defaults:floatingDefaults))
        MailAppearance.current.apply()
    }

    var body: some Scene {
        Window("搞邮件 V" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "?"),id:"main") {
            RootView(store:store,showFloating:{floating.show()})
                .frame(minWidth:1040,minHeight:720)
                .modifier(MailWindowToolbarBackground())
                .onAppear {
                    delegate.store = store
                    delegate.reopenMainWindow = {openWindow(id:"main"); Self.activateMainWindow()}
                    floating.onOpenInbox = {accountID,messageID in
                        store.openCachedInbox(accountID:accountID,messageID:messageID)
                        showMain()
                    }
                    floating.onCompose = {accountID in showMain(); store.newDraft(accountID:accountID)}
                    floating.onOpenSettings = {
                        NSApp.activate(ignoringOtherApps:true)
                        openSettings()
                        DispatchQueue.main.async {NotificationCenter.default.post(name:.mailSettingsTab,object:"appearance")}
                    }
                    floating.restoreIfNeeded()
                }
                .task {await store.syncAll()}
                .onReceive(NotificationCenter.default.publisher(for:Notification.Name("GaoYouJian.showWindow"))) { _ in
                    openWindow(id:"main"); Self.activateMainWindow()
                }
        }
        .defaultSize(width:1380,height:860)
        .commands {
            CommandGroup(after:.newItem) {
                Button("写邮件") {showMain(); store.newDraft()}.keyboardShortcut("n")
                Button("同步所有邮箱") {Task {await store.syncAll()}}.keyboardShortcut("r")
                    .disabled(!store.busy.isEmpty || !store.library.accounts.contains(where:{$0.enabled}))
                Button("搜索") {showMain(); DispatchQueue.main.async {NotificationCenter.default.post(name:.mailFocusSearch,object:nil)}}.keyboardShortcut("f")
                Button("邮箱别名助手…") {showMain(); DispatchQueue.main.async {NotificationCenter.default.post(name:.mailOpenAliasHelper,object:nil)}}.keyboardShortcut("a",modifiers:[.command,.option])
            }
            CommandGroup(after:.toolbar) {
                Button("显示 / 隐藏侧边栏") {showMain(); DispatchQueue.main.async {NotificationCenter.default.post(name:.mailToggleSidebar,object:nil)}}
                    .keyboardShortcut("s",modifiers:[.command,.control])
                Button("显示主窗口") {showMain()}.keyboardShortcut("0")
                Button(floating.isVisible ? "隐藏悬浮窗" : "显示悬浮窗") {floating.toggle()}
                    .keyboardShortcut("m",modifiers:[.command,.control])
            }
            CommandMenu("数据") {
                Button("导出资料备份…",action:store.exportBackup)
                Button("恢复资料备份…",action:store.restoreBackup)
                Divider()
                Button("导入平台 CSV…",action:store.importCSV)
                Button("导出平台 CSV…",action:store.exportCSV)
                Divider()
                Button("数据设置…") {openSettings(); DispatchQueue.main.async {NotificationCenter.default.post(name:.mailSettingsTab,object:"data")}}
            }
            CommandGroup(replacing:.help) {
                Button("搞邮件使用说明") {
                    if let url = Bundle.main.url(forResource:"使用说明",withExtension:"txt") {NSWorkspace.shared.open(url)}
                }
            }
        }
        Settings {MailSettingsView(store:store,floating:floating).frame(width:820,height:740)}
    }

    private func showMain() {openWindow(id:"main"); Self.activateMainWindow()}
    private static func activateMainWindow() {
        NSApp.activate(ignoringOtherApps:true)
        if let window = NSApp.windows.first(where:{$0.identifier?.rawValue == "main"}) {
            if window.isMiniaturized {window.deminiaturize(nil)}
            window.makeKeyAndOrderFront(nil)
            if let sheet = window.attachedSheet {sheet.makeKeyAndOrderFront(nil)}
        }
    }
}

@MainActor final class MailAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: MailStore?
    var reopenMainWindow: (() -> Void)?
    func applicationDidFinishLaunching(_ notification:Notification) {
        #if !DEBUG_TESTING
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier:"com.gaoseries.GaoYouJian").first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) {
            other.activate(options:[.activateAllWindows]); NSApp.terminate(nil)
        }
        #endif
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        reopenMainWindow?(); return true
    }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        if store?.sending == true {
            let alert = NSAlert(); alert.messageText = "邮件正在发送"; alert.informativeText = "请等待发送结果后退出，避免无法确认服务商是否已接受邮件。"; alert.addButton(withTitle:"继续等待"); alert.runModal(); return .terminateCancel
        }
        if let draft = store?.compose {
            do {try store?.saveDraft(draft)} catch {
                let alert = NSAlert(); alert.messageText = "草稿尚未保存"; alert.informativeText = error.localizedDescription; alert.addButton(withTitle:"返回继续编辑"); alert.runModal(); return .terminateCancel
            }
        }
        return .terminateNow
    }
}

private struct MailWindowToolbarBackground: ViewModifier {
    func body(content:Content) -> some View {
        if #available(macOS 15.0,*) {content.toolbarBackground(Color(nsColor:.windowBackgroundColor),for:.windowToolbar).toolbarBackgroundVisibility(.visible,for:.windowToolbar)}
        else {content.toolbarBackground(Color(nsColor:.windowBackgroundColor),for:.windowToolbar)}
    }
}
