import Foundation
import SwiftData

public enum TwigStore {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Project.self, Goal.self, Task.self, TimeEntry.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(at: TwigPaths.supportDir, withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema, url: TwigPaths.storeURL)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}
