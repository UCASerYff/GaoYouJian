import Foundation

final class MailStorage {
    let root: URL
    let libraryURL: URL
    var readFailure: String?
    var cacheWarning: String?
    private var cacheWriteBlocked: String?
    static var encoder: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted,.sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GaoSeries/GaoYouJian",isDirectory:true)
        libraryURL = self.root.appendingPathComponent("Library.json")
    }
    func load() -> MailLibrary {
        guard FileManager.default.fileExists(atPath:libraryURL.path) else { return MailLibrary() }
        do { let library = try Self.decoder.decode(MailLibrary.self, from: Data(contentsOf:libraryURL)); try MailValidation.validate(library); return library }
        catch { readFailure = "本地资料读取失败，已停止写入以保护原文件。请从备份恢复，或在设置中打开数据文件夹。\n" + error.localizedDescription; return MailLibrary() }
    }
    func save(_ library: MailLibrary) throws {
        guard readFailure == nil else { throw MailAppError.message(readFailure!) }
        try MailValidation.validate(library)
        try prepareRoot()
        if FileManager.default.fileExists(atPath:libraryURL.path) {
            let previous = try Data(contentsOf:libraryURL)
            let previousURL = root.appendingPathComponent("Library.previous.json")
            try previous.write(to:previousURL,options:.atomic)
            try makePrivate(previousURL)
        }
        try Self.encoder.encode(library).write(to:libraryURL,options:.atomic)
        try makePrivate(libraryURL)
    }
    func loadMessages() -> [CachedMessage] {
        let u = root.appendingPathComponent("MailCache.json")
        guard FileManager.default.fileExists(atPath:u.path) else { return [] }
        do {
            let messages = try Self.decoder.decode([CachedMessage].self,from:Data(contentsOf:u))
            guard Set(messages.map(\.id)).count == messages.count else { throw MailAppError.message("邮件缓存含有重复标识。") }
            cacheWarning = nil; cacheWriteBlocked = nil
            return messages
        } catch {
            // Local sent receipts may be unique. Preserve even undecodable bytes before any new sync.
            do {
                let values = try u.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw MailAppError.message("邮件缓存路径不是普通文件。") }
                try prepareRoot()
                let snapshot = root.appendingPathComponent("MailCache.corrupt." + UUID().uuidString + ".json")
                try FileManager.default.copyItem(at:u,to:snapshot)
                try makePrivate(snapshot)
                cacheWriteBlocked = nil
                cacheWarning = "邮件缓存无法读取，原文件已保留为 \(snapshot.lastPathComponent)。可以重新同步服务器邮件；本地已发送记录可能只存在于保留文件中。"
            } catch {
                let reason = "邮件缓存无法读取，且无法保存原文件，已停止写入缓存以保护邮件和本地已发送记录。请检查数据文件夹权限后重启应用。\n" + error.localizedDescription
                cacheWarning = reason; cacheWriteBlocked = reason
            }
            return []
        }
    }
    func saveMessages(_ messages: [CachedMessage]) throws {
        guard cacheWriteBlocked == nil else { throw MailAppError.message(cacheWriteBlocked!) }
        try prepareRoot()
        let u = root.appendingPathComponent("MailCache.json")
        try Self.encoder.encode(messages).write(to:u,options:.atomic)
        try makePrivate(u)
    }
    func restore(_ library: MailLibrary) throws {
        try MailValidation.validate(library)
        try prepareRoot()
        let encoded = try Self.encoder.encode(library)
        if FileManager.default.fileExists(atPath:libraryURL.path) {
            let name = "BeforeRestore-" + String(Int(Date().timeIntervalSince1970)) + "-" + UUID().uuidString + ".json"
            let snapshot = root.appendingPathComponent(name)
            try FileManager.default.copyItem(at:libraryURL,to:snapshot)
            try makePrivate(snapshot)
        }
        let currentCache = root.appendingPathComponent("MailCache.json")
        if FileManager.default.fileExists(atPath:currentCache.path) {
            let values = try currentCache.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw MailAppError.message("当前邮件缓存无法安全保存恢复前副本。资料尚未替换，请检查数据文件夹。")
            }
            let snapshot = root.appendingPathComponent("MailCache.beforeRestore." + UUID().uuidString + ".json")
            try FileManager.default.copyItem(at:currentCache,to:snapshot)
            try makePrivate(snapshot)
        }
        try encoded.write(to:libraryURL,options:.atomic)
        try makePrivate(libraryURL)
        readFailure = nil
        cacheWriteBlocked = nil
        cacheWarning = nil
    }
    private func prepareRoot() throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)
    }
    private func makePrivate(_ url: URL) throws { try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path) }
}
