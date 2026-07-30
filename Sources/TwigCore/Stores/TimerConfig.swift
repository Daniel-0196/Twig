import Foundation

public struct TimerConfig: Codable, Equatable {
    public var focusMinutes: Int = 25
    public var shortBreakMinutes: Int = 5
    public var longBreakMinutes: Int = 15
    public var pomodorosPerLongBreak: Int = 4
    public var soundEnabled: Bool = true
    public var notificationsEnabled: Bool = true
    public var autoStartBreak: Bool = true

    public init() {}

    private static let key = "twig.timerConfig"

    public static func load(from defaults: UserDefaults = .standard) -> TimerConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(TimerConfig.self, from: data)
        else { return TimerConfig() }
        return config
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
