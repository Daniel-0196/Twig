import Foundation

public enum CLICommand: Equatable {
    case add(title: String, project: String, goal: String?, due: Date?, estimate: Int?)
    case list(project: String?)
    case help
}

public struct CLIUsageError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public enum CLICommandParser {
    public static let usage = """
    twig — Twig 任务收件箱
      twig add "标题" --project 项目名 [--goal 目标名] [--due YYYY-MM-DD] [--estimate 分钟]
      twig list [--project 项目名]
    """

    public static func parse(_ args: [String]) throws -> CLICommand {
        guard let sub = args.first else { throw CLIUsageError(usage) }
        switch sub {
        case "help", "--help", "-h":
            return .help
        case "add":
            return try parseAdd(Array(args.dropFirst()))
        case "list":
            var rest = args.dropFirst()
            if rest.first == "--project" {
                rest = rest.dropFirst()
                guard let name = rest.first else { throw CLIUsageError("--project 缺项目名\n" + usage) }
                return .list(project: name)
            }
            return .list(project: nil)
        default:
            throw CLIUsageError("未知命令：\(sub)\n" + usage)
        }
    }

    private static func parseAdd(_ args: [String]) throws -> CLICommand {
        guard let title = args.first, !title.hasPrefix("--") else {
            throw CLIUsageError("add 缺任务标题\n" + usage)
        }
        var project: String?
        var goal: String?
        var due: Date?
        var estimate: Int?
        var i = 1
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current
        while i < args.count {
            let flag = args[i]
            let value: String
            if i + 1 < args.count { value = args[i + 1] } else {
                throw CLIUsageError("\(flag) 缺参数值\n" + usage)
            }
            switch flag {
            case "--project": project = value
            case "--goal": goal = value
            case "--due":
                guard let d = dayFormatter.date(from: value) else {
                    throw CLIUsageError("--due 日期格式应为 YYYY-MM-DD，收到「\(value)」")
                }
                due = d
            case "--estimate":
                guard let m = Int(value), m > 0 else {
                    throw CLIUsageError("--estimate 应为正整数分钟，收到「\(value)」")
                }
                estimate = m
            default:
                throw CLIUsageError("未知参数：\(flag)\n" + usage)
            }
            i += 2
        }
        guard let project else { throw CLIUsageError("add 必须带 --project\n" + usage) }
        return .add(title: title, project: project, goal: goal, due: due, estimate: estimate)
    }
}
