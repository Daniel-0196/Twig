import Foundation

public enum StoreBackup {
    /// 启动时调用：把 twig.store*（含 wal/shm）复制到 backups/<时间戳>/，只留最近 keep 份
    public static func backupNow(storeURL: URL = TwigPaths.storeURL,
                                 backupsDir: URL = TwigPaths.backupsDir,
                                 keep: Int = 3,
                                 supportDir: URL = TwigPaths.supportDir,
                                 fm: FileManager = .default) throws {
        guard fm.fileExists(atPath: storeURL.path) else { return }
        try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destDir = backupsDir.appendingPathComponent(stamp, isDirectory: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let prefix = storeURL.lastPathComponent   // "twig.store"
        let related = try fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
        for file in related {
            try fm.copyItem(at: file, to: destDir.appendingPathComponent(file.lastPathComponent))
        }

        let all = try fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }   // 名字带时间戳，字典序即时间序
        for old in all.dropLast(keep) {
            try? fm.removeItem(at: old)
        }
    }
}
