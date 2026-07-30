import Foundation

public enum TwigPaths {
    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Twig", isDirectory: true)
    }
    public static var storeURL: URL { supportDir.appendingPathComponent("twig.store") }
    public static var inboxURL: URL { supportDir.appendingPathComponent("inbox.jsonl") }
    public static var badLinesURL: URL { supportDir.appendingPathComponent("inbox.bad.jsonl") }
    public static var snapshotURL: URL { supportDir.appendingPathComponent("snapshot.json") }
    public static var backupsDir: URL { supportDir.appendingPathComponent("backups", isDirectory: true) }
}
