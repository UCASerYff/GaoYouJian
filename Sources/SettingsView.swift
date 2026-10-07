import SwiftUI
import AppKit

struct MailSettingsView: View {
    @ObservedObject var store: MailStore
    @ObservedObject var floating: MailFloatingController
    @State private var preferences = MailPreferences()
    @State private var googleSecret = ""
    @State private var feedback: String?
    @State private var selectedTab = "module"
    @State private var settingsWindowActive = false
    @AppStorage("gaoyoujian.appearance") private var appearance = "system"

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                moduleSettings
                    .tabItem { Label("模块设置", systemImage: "slider.horizontal.3") }
                    .tag("module")
                appearanceSettings
                    .tabItem { Label("外观", systemImage: "paintpalette") }
                    .tag("appearance")
                dataSettings
                    .tabItem { Label("数据", systemImage: "externaldrive") }
                    .tag("data")
            }
            if let feedback {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text(feedback).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 12)
                    Button { self.feedback = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .help("关闭提示")
                        .accessibilityLabel("关闭操作提示")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 820, height: 740)
        .onAppear {
            preferences = store.library.preferences
            settingsWindowActive = NSApp.keyWindow?.identifier?.rawValue.contains("Settings") == true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, let identifier = window.identifier?.rawValue {
                settingsWindowActive = identifier.contains("Settings")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mailSettingsTab)) { notification in
            if let tab = (notification.object as? String) ?? (notification.userInfo?["tab"] as? String),
               ["module", "appearance", "data"].contains(tab) {
                selectedTab = tab
            }
        }
        .onChange(of: store.library.preferences) { _, value in preferences = value }
        .onChange(of: appearance) { _, _ in MailAppearance.current.apply() }
        .alert("操作未完成", isPresented: Binding(
            get: { store.problem != nil && settingsWindowActive },
            set: { if !$0 && settingsWindowActive { store.problem = nil } }
        )) {
            Button("知道了") { store.problem = nil }
        } message: {
            Text(store.problem ?? "")
        }
    }

    private var moduleSettings: some View {
        Form {
            Section("同步与通知") {
                Picker("自动同步间隔", selection: $preferences.syncMinutes) {
                    ForEach(syncIntervals, id: \.self) { Text("\($0) 分钟").tag($0) }
                }
                Picker("每个文件夹同步最近", selection: $preferences.fetchLimit) {
                    ForEach(fetchLimits, id: \.self) { Text("\($0) 封邮件").tag($0) }
                }
                Toggle("新邮件通知", isOn: $preferences.notifyNewMail)
                Text("通知只显示邮箱与数量。应用运行时自动同步；邮件正文和附件在打开邮件时缓存。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Google / Microsoft 授权") {
                Text("使用 Google 或微软登录前，填写自己注册应用的客户端 ID。QQ、网易等使用客户端授权码的邮箱无需填写。")
                    .font(.callout).foregroundStyle(.secondary)
                settingsField("Google 客户端 ID", value: $preferences.googleClientID)
                LabeledContent("Google 客户端密钥") {
                    SecureField("留空保留已保存的密钥", text: $googleSecret)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                }
                settingsField("Microsoft 客户端 ID", value: $preferences.microsoftClientID)
                settingsField("Microsoft 租户", value: $preferences.microsoftTenant)
                Text("租户通常填写 common；有组织限制时填写管理员提供的租户 ID。微软账号需允许 IMAP / SMTP，Exchange ActiveSync 专用账号暂不支持。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("查看授权配置说明…", action: openAuthorizationGuide)
                    Spacer()
                    Button("清除 Google 客户端密钥", action: clearGoogleSecret)
                }
            }
            Section {
                HStack {
                    Text(hasUnsavedPreferences ? "有未保存的设置" : "设置已与本机资料同步")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("保存设置", action: savePreferences)
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasUnsavedPreferences)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceSettings: some View {
        Form {
            Section {
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                LabeledContent("版本", value: "V" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
            }
            Section("悬浮窗") {
                Toggle("显示悬浮窗", isOn: Binding(get:{floating.isVisible},set:{$0 ? floating.show() : floating.hide()}))
                Toggle("显示邮件预览", isOn: $floating.showPreviews)
                Text("默认只显示本机缓存未读数。开启预览后显示最近三封未读邮件的发件人和主题；展开悬浮窗不会将邮件标为已读。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("平时只显示屏幕边缘竖线；鼠标移入后展开，移出后自动收起。拖动及选择邮箱期间保持展开，Esc 可立即收起；关闭“显示悬浮窗”才完全隐藏。")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("透明度") {
                    HStack {
                        Slider(value:$floating.opacity,in:0.65...1).frame(width:210).accessibilityLabel("悬浮窗透明度")
                        Text("\(Int(floating.opacity * 100))%").monospacedDigit().frame(width:45,alignment:.trailing)
                    }
                }
                Button("重置悬浮窗位置", action:floating.resetPosition)
                Text("从菜单栏信封或 ⌃⌘M 重新打开。悬浮窗的位置、显示状态和外观设置会自动保存。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dataSettings: some View {
        Form {
            Section("资料备份") {
                Text("包含身份、邮箱配置、平台关联、变更记录及草稿文字。密码、登录令牌、邮件缓存和附件文件不包含在备份中。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("导出资料备份…") { perform(store.exportBackup) }
                Button("恢复资料备份…") { perform(store.restoreBackup) }
                Text("恢复会替换当前资料，并保留恢复前副本。恢复后的邮箱需要重新检查收发授权。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("关联平台清单") {
                Button("导入 CSV…") { perform(store.importCSV) }
                Button("导出 CSV…") { perform(store.exportCSV) }
                Text("可先导出一份清单作为导入模板。导入、编辑关联记录不会更改网站或 App 的实际邮箱绑定。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("数据目录") {
                Button("打开数据文件夹", action: openDataFolder)
                Text("身份与平台资料保存在本机，邮箱密码和授权令牌保存在系统钥匙串。升级应用会保留这些资料。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // Restored backups may use a valid custom value that is not one of the presets.
    private var syncIntervals: [Int] { Array(Set([1, 3, 5, 15, 30, preferences.syncMinutes])).sorted() }
    private var fetchLimits: [Int] { Array(Set([30, 80, 150, 300, preferences.fetchLimit])).sorted() }
    private var hasUnsavedPreferences: Bool { preferences != store.library.preferences || !googleSecret.isEmpty }

    private func settingsField(_ title: String, value: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: value)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
        }
    }

    private func savePreferences() {
        feedback = nil
        let previouslyNotified = store.library.preferences.notifyNewMail
        let newSecret = googleSecret
        var previousSecret: String?
        var secretChanged = false
        do {
            if !newSecret.isEmpty {
                previousSecret = try Vault.read("oauth.googleClientSecret")
                try Vault.save(newSecret, for: "oauth.googleClientSecret")
                secretChanged = true
            }
            var updated = preferences
            updated.googleClientID = updated.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.microsoftClientID = updated.microsoftClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.microsoftTenant = updated.microsoftTenant.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.updatePreferences(updated)
            preferences = updated
            googleSecret = ""
            feedback = "设置已保存"
            if updated.notifyNewMail && !previouslyNotified { store.askNotifications() }
        } catch {
            if secretChanged {
                do {
                    if let previousSecret { try Vault.save(previousSecret, for: "oauth.googleClientSecret") }
                    else { try Vault.delete("oauth.googleClientSecret") }
                } catch {
                    store.problem = "设置保存未完成，客户端密钥的回退也未完成。请重新检查 Google 客户端密钥。"
                    return
                }
            }
            store.publish(error)
        }
    }

    private func clearGoogleSecret() {
        feedback = nil
        do {
            try Vault.delete("oauth.googleClientSecret")
            googleSecret = ""
            feedback = "Google 客户端密钥已清除"
        } catch { store.publish(error) }
    }

    private func openAuthorizationGuide() {
        guard let url = Bundle.main.url(forResource: "OAuthSetup", withExtension: "txt", subdirectory: "Docs")
            ?? Bundle.main.url(forResource: "OAuthSetup", withExtension: "txt") else {
            store.problem = "未找到应用内的授权配置说明，请检查安装包。"
            return
        }
        if !NSWorkspace.shared.open(url) { store.problem = "无法打开授权配置说明。" }
    }

    private func perform(_ action: () -> Void) {
        feedback = nil
        store.notice = nil
        action()
        feedback = store.notice
    }

    private func openDataFolder() {
        feedback = nil
        do {
            try FileManager.default.createDirectory(at: store.storage.root, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(store.storage.root) else { throw MailAppError.message("无法打开数据文件夹。") }
            feedback = "数据文件夹已打开"
        } catch { store.publish(error) }
    }
}

enum MailAppearance: String {
    case system, light, dark

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "gaoyoujian.appearance") ?? "system") ?? .system
    }

    func apply() {
        guard let app = NSApp else {
            DispatchQueue.main.async { self.apply() }
            return
        }
        app.appearance = self == .system ? nil : NSAppearance(named: self == .dark ? .darkAqua : .aqua)
    }
}
