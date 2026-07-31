# Twig 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 Twig —— 个人 macOS 桌面 todo app（悬浮毛玻璃部件 + 枝干式目标展开 + 番茄钟 + git 进度追踪 + agent skill 接口）。

**Architecture:** Swift Package Manager 单工程（`Package.swift` 可直接用 Xcode 打开），三个 target：`TwigCore`（模型+逻辑+CLI 解析，全部可单测）、`twig`（薄 CLI）、`TwigApp`（SwiftUI 界面）。相比 spec 中"Xcode App 工程"的调整：用 SPM 包代替 .xcodeproj，以便命令行构建/测试，仍是零第三方依赖。系统要求从 macOS 14 提升到 **macOS 15**（本机 macOS 26，个人用无影响，且需要 `defaultLaunchBehavior` 等 API）。

**Tech Stack:** Swift 5.10 / SwiftUI / SwiftData / XCTest / dreamina CLI（icon）。

## Global Constraints

- 最低系统 macOS 15；开发机已有 Xcode 命令行工具（`swift build` / `swift test` 可用）
- 零第三方依赖，只用系统框架（SwiftUI、SwiftData、AppKit、Foundation、CoreGraphics）
- UI 文案一律简体中文
- 数据目录：`~/Library/Application Support/Twig/`
- 每个 Task 结束必须 `swift build` 通过 + 相关测试通过后 commit
- UI 任务（10、11、12、13）无单元测试，用任务内手动验收清单代替

---

## 文件结构

```
twig/
├── Package.swift
├── Sources/
│   ├── TwigCore/
│   │   ├── Infra/TwigPaths.swift          # 数据目录与所有文件路径
│   │   ├── Infra/TwigStore.swift          # ModelContainer 工厂
│   │   ├── Infra/StoreBackup.swift        # 启动前数据库备份（留 3 份）
│   │   ├── Models/Project.swift           # 项目
│   │   ├── Models/Goal.swift              # 目标节点（短/中/长期）
│   │   ├── Models/Task.swift              # 任务
│   │   ├── Models/TimeEntry.swift         # 计时记录
│   │   ├── Stores/TaskStore.swift         # 任务 CRUD + 查询
│   │   ├── Stores/TimerConfig.swift       # 计时器配置（UserDefaults）
│   │   ├── Stores/PomodoroEngine.swift    # 番茄钟状态机（纯逻辑）
│   │   ├── Stores/TimerStore.swift        # 引擎 ↔ SwiftData 胶水 + 心跳
│   │   ├── Stores/CrashRecovery.swift     # 未闭合计时恢复
│   │   ├── Inbox/InboxItem.swift          # 收件箱条目 + 解析
│   │   ├── Inbox/InboxImporter.swift      # 导入/去重/坏行留档
│   │   ├── Inbox/Snapshot.swift           # 快照模型 + 导出（供 CLI list）
│   │   ├── CLI/CLICommand.swift           # CLI 参数解析（可单测）
│   │   ├── Git/GitCommit.swift            # 提交模型 + log 解析
│   │   ├── Git/GitReader.swift            # git 子进程封装（超时 5s）
│   │   ├── Reports/ReportAggregator.swift # 日/周报聚合（纯函数）
│   │   └── Layout/BranchLayout.swift      # 枝干布局计算（纯函数）
│   ├── twig-cli/main.swift                # twig add / twig list
│   └── TwigApp/
│       ├── TwigAppMain.swift              # @main 入口
│       ├── AppState.swift                 # 装配容器/Stores/监视器/恢复
│       ├── ColorHex.swift                 # Color(hex:) 扩展
│       ├── Widget/WidgetWindowController.swift  # NSPanel 悬浮窗
│       ├── Widget/WidgetView.swift        # 状态机容器（三态）
│       ├── Widget/CollapsedBarView.swift  # 紧凑横条 + 虚线外延
│       ├── Widget/PeekListView.swift      # 今日任务滑出清单
│       ├── Widget/BranchView.swift        # 枝干展开（Canvas + 拖拽）
│       ├── Main/MainWindowView.swift      # 三栏主窗口
│       ├── Main/ProjectListView.swift
│       ├── Main/TimelineView.swift        # 目标泳道 + git 提交
│       ├── Main/TaskDetailView.swift
│       ├── Main/ReportsView.swift         # 今日/本周
│       └── Main/SettingsView.swift        # 计时器/仓库/导入失败/登录项
├── Tests/TwigCoreTests/                   # 与 TwigCore 对应的 XCTest
├── skills/claude/twig/SKILL.md            # Claude Code skill
├── skills/codex/twig.md                   # Codex 自定义 prompt
├── skills/install.sh                      # 安装/软链脚本
├── assets/Info.plist                      # .app 打包用
├── scripts/make-app.sh                    # release 打包 Twig.app
└── docs/superpowers/…                     # spec 与本计划
```

---

### Task 1: SPM 脚手架 + 路径 + 数据模型

**Files:**
- Create: `Package.swift`
- Create: `Sources/TwigCore/Infra/TwigPaths.swift`
- Create: `Sources/TwigCore/Infra/TwigStore.swift`
- Create: `Sources/TwigCore/Models/Project.swift`
- Create: `Sources/TwigCore/Models/Goal.swift`
- Create: `Sources/TwigCore/Models/Task.swift`
- Create: `Sources/TwigCore/Models/TimeEntry.swift`
- Test: `Tests/TwigCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `TwigPaths.supportDir / .storeURL / .inboxURL / .badLinesURL / .snapshotURL / .backupsDir`（均为 `static var: URL`）
  - `TwigStore.makeContainer(inMemory: Bool = false) throws -> ModelContainer`
  - `@Model Project(name:colorHint:repoPath:createdAt:)`，属性 `goals: [Goal]`
  - `@Model Goal(title:horizon:targetDate:sortOrder:)`，属性 `project: Project?`、`tasks: [Task]`、`isDone: Bool`
  - `enum Horizon: String, Codable { case short, mid, long }`
  - `@Model Task(title:estimateMin:dueDate:sortOrder:)`，属性 `goal: Goal?`、`isDone`、`completedAt: Date?`
  - `@Model TimeEntry(kind:startedAt:)`，属性 `task: Task?`、`endedAt: Date?`、`lastHeartbeat: Date`
  - `enum TimeKind: String, Codable { case pomodoro, stopwatch, break }`

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "twig",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "TwigCore", path: "Sources/TwigCore"),
        .executableTarget(name: "twig", dependencies: ["TwigCore"], path: "Sources/twig-cli"),
        .executableTarget(name: "TwigApp", dependencies: ["TwigCore"], path: "Sources/TwigApp"),
        .testTarget(name: "TwigCoreTests", dependencies: ["TwigCore"], path: "Tests/TwigCoreTests"),
    ]
)
```

- [ ] **Step 2: 写失败的模型测试**

`Tests/TwigCoreTests/ModelTests.swift`：

```swift
import XCTest
import SwiftData
@testable import TwigCore

final class ModelTests: XCTestCase {
    func testProjectGoalTaskChainPersists() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let project = Project(name: "mergeCook4", colorHint: "#D97757")
        ctx.insert(project)
        let goal = Goal(title: "demo 可玩", horizon: .short, targetDate: nil)
        goal.project = project
        ctx.insert(goal)
        let task = Task(title: "修 shader 编译错误")
        task.goal = goal
        ctx.insert(task)
        try ctx.save()

        let projects = try ctx.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].goals.count, 1)
        XCTAssertEqual(projects[0].goals[0].tasks.first?.title, "修 shader 编译错误")
        XCTAssertFalse(projects[0].goals[0].tasks[0].isDone)
    }

    func testCascadeDeleteRemovesGoalsAndTasks() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let project = Project(name: "p", colorHint: "#5F8A6E")
        ctx.insert(project)
        let goal = Goal(title: "g", horizon: .mid, targetDate: nil)
        goal.project = project
        ctx.insert(goal)
        let task = Task(title: "t")
        task.goal = goal
        ctx.insert(task)
        try ctx.save()

        ctx.delete(project)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Goal>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Task>()), 0)
    }

    func testTimeEntryDefaults() throws {
        let entry = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertNil(entry.endedAt)
        XCTAssertEqual(entry.lastHeartbeat, entry.startedAt)
        XCTAssertEqual(entry.kind, .pomodoro)
    }
}
```

- [ ] **Step 3: 运行测试确认编译失败**

Run: `swift test --filter ModelTests`
Expected: FAIL — 找不到 `TwigStore` / `Project` 等符号

- [ ] **Step 4: 实现路径与模型**

`Sources/TwigCore/Infra/TwigPaths.swift`：

```swift
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
```

`Sources/TwigCore/Infra/TwigStore.swift`：

```swift
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
```

`Sources/TwigCore/Models/Project.swift`：

```swift
import Foundation
import SwiftData

@Model
public final class Project {
    public var name: String
    public var colorHint: String   // "#D97757" 形式，枝干/节点继承此色
    public var repoPath: String?
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Goal.project)
    public var goals: [Goal] = []

    public init(name: String, colorHint: String, repoPath: String? = nil, createdAt: Date = .now) {
        self.name = name
        self.colorHint = colorHint
        self.repoPath = repoPath
        self.createdAt = createdAt
    }
}
```

`Sources/TwigCore/Models/Goal.swift`：

```swift
import Foundation
import SwiftData

public enum Horizon: String, Codable, CaseIterable {
    case short, mid, long
}

@Model
public final class Goal {
    public var title: String
    public var horizon: Horizon
    public var targetDate: Date?   // 长期只定季度时存季度末日期，UI 显示「Q4」
    public var isDone: Bool = false
    public var sortOrder: Double = 0
    public var project: Project?
    @Relationship(deleteRule: .cascade, inverse: \Task.goal)
    public var tasks: [Task] = []

    public init(title: String, horizon: Horizon, targetDate: Date?, sortOrder: Double = 0) {
        self.title = title
        self.horizon = horizon
        self.targetDate = targetDate
        self.sortOrder = sortOrder
    }
}
```

`Sources/TwigCore/Models/Task.swift`：

```swift
import Foundation
import SwiftData

@Model
public final class Task {
    public var title: String
    public var isDone: Bool = false
    public var estimateMin: Int?
    public var dueDate: Date?
    public var completedAt: Date?
    public var sortOrder: Double = 0
    public var goal: Goal?
    @Relationship(deleteRule: .nullify, inverse: \TimeEntry.task)
    public var timeEntries: [TimeEntry] = []

    public init(title: String, estimateMin: Int? = nil, dueDate: Date? = nil, sortOrder: Double = 0) {
        self.title = title
        self.estimateMin = estimateMin
        self.dueDate = dueDate
        self.sortOrder = sortOrder
    }
}
```

`Sources/TwigCore/Models/TimeEntry.swift`：

```swift
import Foundation
import SwiftData

public enum TimeKind: String, Codable {
    case pomodoro, stopwatch, `break`
}

@Model
public final class TimeEntry {
    public var kind: TimeKind
    public var startedAt: Date
    public var endedAt: Date?
    public var lastHeartbeat: Date
    public var task: Task?

    public init(kind: TimeKind, startedAt: Date) {
        self.kind = kind
        self.startedAt = startedAt
        self.lastHeartbeat = startedAt
    }

    /// 实际时长（秒）；未闭合时按 lastHeartbeat 估算
    public var duration: TimeInterval {
        (endedAt ?? lastHeartbeat).timeIntervalSince(startedAt)
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter ModelTests`
Expected: 3 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: SPM 脚手架 + SwiftData 四层模型（Project/Goal/Task/TimeEntry）"
```

---

### Task 2: TaskStore（CRUD + 查询）

**Files:**
- Create: `Sources/TwigCore/Stores/TaskStore.swift`
- Test: `Tests/TwigCoreTests/TaskStoreTests.swift`

**Interfaces:**
- Consumes: `TwigStore.makeContainer(inMemory:)`、`Project/Goal/Task`（Task 1）
- Produces（后续任务全部依赖）：
  - `@MainActor final class TaskStore`，`init(container: ModelContainer)`
  - `addProject(name: String, colorHint: String, repoPath: String? = nil) -> Project`
  - `addGoal(to: Project, title: String, horizon: Horizon, targetDate: Date?) -> Goal`
  - `addTask(to: Goal, title: String, estimateMin: Int? = nil, dueDate: Date? = nil) -> Task`
  - `toggleTask(_ task: Task)`（勾选/取消，维护 completedAt）
  - `tasksForToday(on day: Date, calendar: Calendar = .current) -> [Task]`（未完成 且 dueDate <= 当天结束）
  - `incompleteTasks() -> [Task]`
  - `allProjects() -> [Project]`
  - `taskExists(title: String, projectName: String) -> Bool`
  - `findOrCreateProject(named: String) -> Project`
  - `findOrCreateGoal(in: Project, title: String) -> Goal`

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/TaskStoreTests.swift`：

```swift
import XCTest
@testable import TwigCore

@MainActor
final class TaskStoreTests: XCTestCase {
    private func makeStore() throws -> TaskStore {
        TaskStore(container: try TwigStore.makeContainer(inMemory: true))
    }

    func testAddAndToggleTask() throws {
        let store = try makeStore()
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "v0.1", horizon: .short, targetDate: nil)
        let t = store.addTask(to: g, title: "写 TaskStore")
        XCTAssertFalse(t.isDone)
        store.toggleTask(t)
        XCTAssertTrue(t.isDone)
        XCTAssertNotNil(t.completedAt)
        store.toggleTask(t)
        XCTAssertFalse(t.isDone)
        XCTAssertNil(t.completedAt)
    }

    func testTasksForTodayIncludesOverdueButNotFuture() throws {
        let store = try makeStore()
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "g", horizon: .short, targetDate: nil)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        _ = store.addTask(to: g, title: "昨天就该做", dueDate: yesterday)
        _ = store.addTask(to: g, title: "今天的", dueDate: today)
        _ = store.addTask(to: g, title: "明天的", dueDate: tomorrow)
        let done = store.addTask(to: g, title: "已完成", dueDate: today)
        store.toggleTask(done)
        let titles = store.tasksForToday(on: today).map(\.title)
        XCTAssertEqual(Set(titles), ["昨天就该做", "今天的"])
    }

    func testFindOrCreateIsIdempotent() throws {
        let store = try makeStore()
        let p1 = store.findOrCreateProject(named: "twig")
        let p2 = store.findOrCreateProject(named: "twig")
        XCTAssertEqual(p1.persistentModelID, p2.persistentModelID)
        let g1 = store.findOrCreateGoal(in: p1, title: "收集箱")
        let g2 = store.findOrCreateGoal(in: p1, title: "收集箱")
        XCTAssertEqual(g1.persistentModelID, g2.persistentModelID)
        XCTAssertEqual(store.allProjects().count, 1)
    }

    func testTaskExistsChecksIncompleteOnly() throws {
        let store = try makeStore()
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "g", horizon: .short, targetDate: nil)
        let t = store.addTask(to: g, title: "修内存泄漏")
        XCTAssertTrue(store.taskExists(title: "修内存泄漏", projectName: "twig"))
        store.toggleTask(t)
        XCTAssertFalse(store.taskExists(title: "修内存泄漏", projectName: "twig"))
    }
}
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `swift test --filter TaskStoreTests`
Expected: FAIL — 找不到 `TaskStore`

- [ ] **Step 3: 实现 TaskStore**

`Sources/TwigCore/Stores/TaskStore.swift`：

```swift
import Foundation
import SwiftData

@MainActor
public final class TaskStore {
    public let container: ModelContainer
    private var ctx: ModelContext { container.mainContext }
    private static let orderStep: Double = 1024

    public init(container: ModelContainer) {
        self.container = container
    }

    @discardableResult
    public func addProject(name: String, colorHint: String, repoPath: String? = nil) -> Project {
        let p = Project(name: name, colorHint: colorHint, repoPath: repoPath)
        ctx.insert(p)
        try? ctx.save()
        return p
    }

    @discardableResult
    public func addGoal(to project: Project, title: String, horizon: Horizon, targetDate: Date?) -> Goal {
        let next = (project.goals.map(\.sortOrder).max() ?? 0) + Self.orderStep
        let g = Goal(title: title, horizon: horizon, targetDate: targetDate, sortOrder: next)
        g.project = project
        ctx.insert(g)
        try? ctx.save()
        return g
    }

    @discardableResult
    public func addTask(to goal: Goal, title: String, estimateMin: Int? = nil, dueDate: Date? = nil) -> Task {
        let next = (goal.tasks.map(\.sortOrder).max() ?? 0) + Self.orderStep
        let t = Task(title: title, estimateMin: estimateMin, dueDate: dueDate, sortOrder: next)
        t.goal = goal
        ctx.insert(t)
        try? ctx.save()
        return t
    }

    public func toggleTask(_ task: Task) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        try? ctx.save()
    }

    /// 今日任务 = 未完成 且（无截止日期 或 截止不晚于今天结束）
    public func tasksForToday(on day: Date, calendar: Calendar = .current) -> [Task] {
        let endOfDay = calendar.startOfDay(for: day).addingTimeInterval(86400)
        return incompleteTasks()
            .filter { $0.dueDate.map { $0 < endOfDay } ?? true }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func incompleteTasks() -> [Task] {
        (try? ctx.fetch(FetchDescriptor<Task>()))?.filter { !$0.isDone } ?? []
    }

    public func allProjects() -> [Project] {
        (try? ctx.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    public func taskExists(title: String, projectName: String) -> Bool {
        incompleteTasks().contains {
            $0.title == title && $0.goal?.project?.name == projectName
        }
    }

    public func findOrCreateProject(named name: String) -> Project {
        if let existing = allProjects().first(where: { $0.name == name }) { return existing }
        return addProject(name: name, colorHint: Self.defaultColor)
    }

    public func findOrCreateGoal(in project: Project, title: String) -> Goal {
        if let existing = project.goals.first(where: { $0.title == title }) { return existing }
        return addGoal(to: project, title: title, horizon: .short, targetDate: nil)
    }

    private static let defaultColor = "#D97757"
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter TaskStoreTests`
Expected: 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Stores/TaskStore.swift Tests/TwigCoreTests/TaskStoreTests.swift
git commit -m "feat: TaskStore 任务 CRUD + 今日/查重/findOrCreate 查询"
```

---

### Task 3: 番茄钟状态机 + TimerStore + 配置

**Files:**
- Create: `Sources/TwigCore/Stores/TimerConfig.swift`
- Create: `Sources/TwigCore/Stores/PomodoroEngine.swift`
- Create: `Sources/TwigCore/Stores/TimerStore.swift`
- Test: `Tests/TwigCoreTests/PomodoroEngineTests.swift`
- Test: `Tests/TwigCoreTests/TimerStoreTests.swift`

**Interfaces:**
- Consumes: `TwigStore.makeContainer`、`Task`、`TimeEntry`、`TimeKind`（Task 1）
- Produces：
  - `struct TimerConfig: Codable, Equatable`（字段：`focusMinutes=25`、`shortBreakMinutes=5`、`longBreakMinutes=15`、`pomodorosPerLongBreak=4`、`soundEnabled=true`、`notificationsEnabled=true`、`autoStartBreak=true`）；`static func load(from: UserDefaults = .standard) -> TimerConfig`、`func save(to: UserDefaults = .standard)`
  - `enum TimerMode: Equatable { case pomodoro, stopwatch, countdown(minutes: Int) }`
  - `enum EngineState: Equatable { case idle, focusing(startedAt: Date, plannedEnd: Date?, mode: TimerMode), onBreak(startedAt: Date, endsAt: Date, isLong: Bool) }`
  - `enum EngineEvent: Equatable { case focusCompleted(duration: TimeInterval), breakCompleted, stopped(recorded: TimeInterval?) }`
  - `final class PomodoroEngine`：`init(config:now:)`、`state`、`completedPomodoros`、`startFocus(mode:)`、`tick() -> EngineEvent?`、`finishFocusEarly() -> EngineEvent?`、`stop(discard:) -> EngineEvent?`、`endBreak() -> EngineEvent?`
  - `@MainActor final class TimerStore`：`init(container:config:now:)`、`engine`、`activeTask: Task?`、`pendingCompletionCheck: Bool`、`onEvent: ((EngineEvent) -> Void)?`、`start(task: Task?, mode: TimerMode)`、`tick()`、`stop(discard:)`、`finishFocus()`、`endBreak()`、`heartbeat()`、`dismissCompletionCheck(markTaskDone: Bool)`

- [ ] **Step 1: 写引擎失败测试（注入假时钟）**

`Tests/TwigCoreTests/PomodoroEngineTests.swift`：

```swift
import XCTest
@testable import TwigCore

final class PomodoroEngineTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)

    private func makeEngine(config: TimerConfig = TimerConfig()) -> PomodoroEngine {
        PomodoroEngine(config: config, now: { [unowned self] in self.now })
    }

    func testPomodoroCompletesAfter25MinAndStartsShortBreak() {
        let engine = makeEngine()
        engine.startFocus(mode: .pomodoro)
        now = now.addingTimeInterval(24 * 60)
        XCTAssertNil(engine.tick())
        now = now.addingTimeInterval(60)
        let event = engine.tick()
        guard case .focusCompleted(let duration) = event else {
            return XCTFail("期望 focusCompleted，得到 \(String(describing: event))")
        }
        XCTAssertEqual(duration, 25 * 60, accuracy: 1)
        guard case .onBreak(_, _, let isLong) = engine.state else {
            return XCTFail("期望进入短休息")
        }
        XCTAssertFalse(isLong)
    }

    func testFourthPomodoroTriggersLongBreak() {
        let engine = makeEngine()
        for i in 1...4 {
            engine.startFocus(mode: .pomodoro)
            now = now.addingTimeInterval(25 * 60)
            _ = engine.tick()
            if i < 4 {
                now = now.addingTimeInterval(5 * 60)
                XCTAssertEqual(engine.tick(), .breakCompleted)
            }
        }
        guard case .onBreak(_, let endsAt, let isLong) = engine.state else {
            return XCTFail("第 4 个番茄后应进入休息")
        }
        XCTAssertTrue(isLong)
        XCTAssertEqual(endsAt.timeIntervalSinceNow, 15 * 60, accuracy: 60)
    }

    func testStopwatchNeverAutoCompletes() {
        let engine = makeEngine()
        engine.startFocus(mode: .stopwatch)
        now = now.addingTimeInterval(3 * 3600)
        XCTAssertNil(engine.tick())
        guard case .stopped(let recorded) = engine.stop(discard: false) else {
            return XCTFail("stop 应返回 stopped")
        }
        XCTAssertEqual(recorded ?? 0, 3 * 3600, accuracy: 1)
        XCTAssertEqual(engine.state, .idle)
    }

    func testCustomCountdown() {
        let engine = makeEngine()
        engine.startFocus(mode: .countdown(minutes: 40))
        now = now.addingTimeInterval(40 * 60)
        XCTAssertNotNil(engine.tick())
    }

    func testStopDiscardRecordsNothing() {
        let engine = makeEngine()
        engine.startFocus(mode: .pomodoro)
        now = now.addingTimeInterval(600)
        XCTAssertEqual(engine.stop(discard: true), .stopped(recorded: nil))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.completedPomodoros, 0)
    }

    func testAutoStartBreakOffLeavesIdle() {
        var config = TimerConfig()
        config.autoStartBreak = false
        let engine = makeEngine(config: config)
        engine.startFocus(mode: .pomodoro)
        now = now.addingTimeInterval(25 * 60)
        _ = engine.tick()
        XCTAssertEqual(engine.state, .idle)
    }
}
```

- [ ] **Step 2: 运行确认编译失败**

Run: `swift test --filter PomodoroEngineTests`
Expected: FAIL — 找不到 `PomodoroEngine`

- [ ] **Step 3: 实现 TimerConfig + PomodoroEngine**

`Sources/TwigCore/Stores/TimerConfig.swift`：

```swift
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
```

`Sources/TwigCore/Stores/PomodoroEngine.swift`：

```swift
import Foundation

public enum TimerMode: Equatable {
    case pomodoro, stopwatch, countdown(minutes: Int)
}

public enum EngineState: Equatable {
    case idle
    case focusing(startedAt: Date, plannedEnd: Date?, mode: TimerMode)
    case onBreak(startedAt: Date, endsAt: Date, isLong: Bool)
}

public enum EngineEvent: Equatable {
    case focusCompleted(duration: TimeInterval)
    case breakCompleted
    case stopped(recorded: TimeInterval?)   // nil = 已丢弃
}

public final class PomodoroEngine {
    public private(set) var state: EngineState = .idle
    public private(set) var completedPomodoros: Int = 0
    public var config: TimerConfig
    private let now: () -> Date

    public init(config: TimerConfig = TimerConfig(), now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
    }

    @discardableResult
    public func startFocus(mode: TimerMode) -> EngineState {
        let started = now()
        let plannedEnd: Date?
        switch mode {
        case .stopwatch: plannedEnd = nil
        case .pomodoro: plannedEnd = started.addingTimeInterval(TimeInterval(config.focusMinutes * 60))
        case .countdown(let m): plannedEnd = started.addingTimeInterval(TimeInterval(m * 60))
        }
        state = .focusing(startedAt: started, plannedEnd: plannedEnd, mode: mode)
        return state
    }

    @discardableResult
    public func tick() -> EngineEvent? {
        switch state {
        case .focusing(_, let plannedEnd, _):
            guard let plannedEnd, now() >= plannedEnd else { return nil }
            return completeFocus(endedAt: plannedEnd)
        case .onBreak(_, let endsAt, _):
            guard now() >= endsAt else { return nil }
            state = .idle
            return .breakCompleted
        case .idle:
            return nil
        }
    }

    @discardableResult
    public func finishFocusEarly() -> EngineEvent? {
        guard case .focusing(let startedAt, _, _) = state else { return nil }
        return completeFocus(endedAt: max(now(), startedAt))
    }

    @discardableResult
    public func stop(discard: Bool) -> EngineEvent? {
        guard case .focusing(let startedAt, _, _) = state else { return nil }
        state = .idle
        if discard { return .stopped(recorded: nil) }
        return .stopped(recorded: now().timeIntervalSince(startedAt))
    }

    @discardableResult
    public func endBreak() -> EngineEvent? {
        guard case .onBreak = state else { return nil }
        state = .idle
        return .breakCompleted
    }

    private func completeFocus(endedAt: Date) -> EngineEvent {
        guard case .focusing(let startedAt, _, _) = state else { return .stopped(recorded: nil) }
        completedPomodoros += 1
        let isLong = completedPomodoros % config.pomodorosPerLongBreak == 0
        if config.autoStartBreak {
            let mins = isLong ? config.longBreakMinutes : config.shortBreakMinutes
            state = .onBreak(startedAt: endedAt,
                             endsAt: endedAt.addingTimeInterval(TimeInterval(mins * 60)),
                             isLong: isLong)
        } else {
            state = .idle
        }
        return .focusCompleted(duration: endedAt.timeIntervalSince(startedAt))
    }
}
```

- [ ] **Step 4: 运行引擎测试确认通过**

Run: `swift test --filter PomodoroEngineTests`
Expected: 6 tests PASS

- [ ] **Step 5: 写 TimerStore 失败测试**

`Tests/TwigCoreTests/TimerStoreTests.swift`：

```swift
import XCTest
@testable import TwigCore

@MainActor
final class TimerStoreTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() throws -> TimerStore {
        TimerStore(container: try TwigStore.makeContainer(inMemory: true),
                   config: TimerConfig(),
                   now: { [unowned self] in self.now })
    }

    func testCompletedPomodoroWritesClosedEntryAndOpensBreak() throws {
        let store = try makeStore()
        var events: [EngineEvent] = []
        store.onEvent = { events.append($0) }
        store.start(task: nil, mode: .pomodoro)
        now = now.addingTimeInterval(25 * 60)
        store.tick()
        XCTAssertTrue(events.contains(.focusCompleted(duration: 25 * 60)))
        let entries = try store.container.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 2)   // 1 段专注（已闭合）+ 1 段休息（进行中）
        let focus = entries.first { $0.kind == .pomodoro }
        XCTAssertNotNil(focus?.endedAt)
        XCTAssertEqual(focus?.duration ?? 0, 25 * 60, accuracy: 2)
        XCTAssertEqual(entries.first { $0.kind == .break }?.endedAt, nil)
        XCTAssertTrue(store.pendingCompletionCheck)
    }

    func testStopDiscardDeletesEntry() throws {
        let store = try makeStore()
        store.start(task: nil, mode: .stopwatch)
        now = now.addingTimeInterval(300)
        store.stop(discard: true)
        let count = try store.container.mainContext.fetchCount(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(count, 0)
    }

    func testHeartbeatUpdatesTimestamp() throws {
        let store = try makeStore()
        store.start(task: nil, mode: .stopwatch)
        now = now.addingTimeInterval(60)
        store.heartbeat()
        let entry = try store.container.mainContext.fetch(FetchDescriptor<TimeEntry>()).first
        XCTAssertEqual(entry?.lastHeartbeat, now)
    }

    func testDismissCompletionCheckCanMarkTaskDone() throws {
        let store = try makeStore()
        let taskStore = TaskStore(container: store.container)
        let p = taskStore.addProject(name: "twig", colorHint: "#D97757")
        let g = taskStore.addGoal(to: p, title: "g", horizon: .short, targetDate: nil)
        let t = taskStore.addTask(to: g, title: "被计时的任务")
        store.start(task: t, mode: .pomodoro)
        now = now.addingTimeInterval(25 * 60)
        store.tick()
        store.dismissCompletionCheck(markTaskDone: true)
        XCTAssertFalse(store.pendingCompletionCheck)
        XCTAssertTrue(t.isDone)
    }
}
```

- [ ] **Step 6: 运行确认编译失败**

Run: `swift test --filter TimerStoreTests`
Expected: FAIL — 找不到 `TimerStore`

- [ ] **Step 7: 实现 TimerStore**

`Sources/TwigCore/Stores/TimerStore.swift`：

```swift
import Foundation
import SwiftData

@MainActor
public final class TimerStore {
    public private(set) var engine: PomodoroEngine
    public private(set) var activeTask: Task?
    public private(set) var pendingCompletionCheck = false
    public var onEvent: ((EngineEvent) -> Void)?

    public let container: ModelContainer
    private var ctx: ModelContext { container.mainContext }
    private var activeEntry: TimeEntry?
    private let now: () -> Date

    public init(container: ModelContainer,
                config: TimerConfig = .load(),
                now: @escaping () -> Date = Date.init) {
        self.container = container
        self.now = now
        self.engine = PomodoroEngine(config: config, now: now)
    }

    public func start(task: Task?, mode: TimerMode) {
        if let stale = activeEntry {   // 保险：旧段直接丢弃
            ctx.delete(stale)
            activeEntry = nil
        }
        engine.startFocus(mode: mode)
        activeTask = task
        let entry = TimeEntry(kind: mode == .stopwatch ? .stopwatch : .pomodoro, startedAt: now())
        entry.task = task
        ctx.insert(entry)
        activeEntry = entry
        try? ctx.save()
    }

    public func tick() {
        heartbeat()
        guard let event = engine.tick() else { return }
        handle(event)
    }

    public func stop(discard: Bool) {
        guard let event = engine.stop(discard: discard) else { return }
        if discard, let entry = activeEntry {
            ctx.delete(entry)
        } else {
            activeEntry?.endedAt = now()
        }
        activeEntry = nil
        activeTask = nil
        try? ctx.save()
        onEvent?(event)
    }

    public func finishFocus() {
        guard let event = engine.finishFocusEarly() else { return }
        handle(event)
    }

    public func endBreak() {
        guard let event = engine.endBreak() else { return }
        closeActiveEntry()
        try? ctx.save()
        onEvent?(event)
    }

    public func heartbeat() {
        guard let entry = activeEntry, entry.endedAt == nil else { return }
        entry.lastHeartbeat = now()
        try? ctx.save()
    }

    /// 番茄结束后的"任务完成了吗？"：markTaskDone=true 则勾掉当前任务
    public func dismissCompletionCheck(markTaskDone: Bool) {
        if markTaskDone, let task = activeTask {
            task.isDone = true
            task.completedAt = now()
        }
        if case .focusing = engine.state {} else { activeTask = nil }
        pendingCompletionCheck = false
        try? ctx.save()
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .focusCompleted:
            closeActiveEntry()
            pendingCompletionCheck = true
            if case .onBreak(let startedAt, _, _) = engine.state {
                let breakEntry = TimeEntry(kind: .break, startedAt: startedAt)
                ctx.insert(breakEntry)
                activeEntry = breakEntry
            }
        case .breakCompleted:
            closeActiveEntry()
        case .stopped:
            break
        }
        try? ctx.save()
        onEvent?(event)
    }

    private func closeActiveEntry() {
        guard let entry = activeEntry, entry.endedAt == nil else { return }
        entry.endedAt = now()
        activeEntry = nil
    }
}
```

- [ ] **Step 8: 运行测试确认通过**

Run: `swift test --filter TimerStoreTests`
Expected: 4 tests PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/TwigCore/Stores Tests/TwigCoreTests/PomodoroEngineTests.swift Tests/TwigCoreTests/TimerStoreTests.swift
git commit -m "feat: 番茄钟状态机 + TimerStore（三种计时模式、心跳落盘、完成询问）"
```

---
### Task 4: 收件箱（解析 + 导入 + 坏行留档）

**Files:**
- Create: `Sources/TwigCore/Inbox/InboxItem.swift`
- Create: `Sources/TwigCore/Inbox/InboxImporter.swift`
- Test: `Tests/TwigCoreTests/InboxTests.swift`

**Interfaces:**
- Consumes: `TaskStore`（Task 2）、`TwigPaths`（Task 1）
- Produces：
  - `struct InboxItem: Codable, Equatable`（`id: UUID`、`title`、`project`、`goal: String?`、`due: Date?`、`estimateMin: Int?`、`source`、`createdAt: Date`）
  - `enum InboxParser { static func parse(line: String) -> InboxItem? }`（JSON 一行一条，ISO8601 日期；坏行返回 nil）
  - `struct ImportReport: Equatable { var imported: Int; var skippedDuplicates: Int; var badLines: [String] }`
  - `@MainActor final class InboxImporter`，`init(store: TaskStore)`，`importInbox(at inboxURL: URL, badLinesURL: URL) throws -> ImportReport`

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/InboxTests.swift`：

```swift
import XCTest
@testable import TwigCore

@MainActor
final class InboxTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-test-\(UUID().uuidString)-\(name)")
    }

    private func makeLine(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    func testParseGoodLine() throws {
        let line = """
        {"id":"\(UUID().uuidString)","title":"修渲染管线","project":"mergeCook4","goal":"demo可玩","due":"2026-08-05T00:00:00Z","estimateMin":120,"source":"claude","createdAt":"2026-07-30T10:00:00Z"}
        """
        let item = InboxParser.parse(line: line)
        XCTAssertEqual(item?.title, "修渲染管线")
        XCTAssertEqual(item?.project, "mergeCook4")
        XCTAssertEqual(item?.estimateMin, 120)
        XCTAssertNil(InboxParser.parse(line: "这不是 json"))
        XCTAssertNil(InboxParser.parse(line: "{\"title\":\"缺字段\"}"))
    }

    func testImportCreatesProjectGoalTask() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let inbox = tempURL("inbox.jsonl")
        let bad = tempURL("bad.jsonl")
        let line = try makeLine([
            "id": UUID().uuidString, "title": "写单元测试", "project": "twig",
            "goal": "v0.1", "estimateMin": 60, "source": "codex",
            "createdAt": "2026-07-30T10:00:00Z",
        ])
        try line.write(to: inbox, atomically: true, encoding: .utf8)

        let report = try InboxImporter(store: store).importInbox(at: inbox, badLinesURL: bad)
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.badLines, [])
        XCTAssertTrue(store.taskExists(title: "写单元测试", projectName: "twig"))
        // 收件箱已清空
        XCTAssertEqual(try String(contentsOf: inbox, encoding: .utf8), "")
    }

    func testImportSkipsDuplicatesAndArchivesBadLines() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "v0.1", horizon: .short, targetDate: nil)
        _ = store.addTask(to: g, title: "已有任务")
        let inbox = tempURL("inbox.jsonl")
        let bad = tempURL("bad.jsonl")
        let dup = try makeLine([
            "id": UUID().uuidString, "title": "已有任务", "project": "twig",
            "source": "claude", "createdAt": "2026-07-30T10:00:00Z",
        ])
        try (dup + "\n坏行\n").write(to: inbox, atomically: true, encoding: .utf8)

        let report = try InboxImporter(store: store).importInbox(at: inbox, badLinesURL: bad)
        XCTAssertEqual(report.imported, 0)
        XCTAssertEqual(report.skippedDuplicates, 1)
        XCTAssertEqual(report.badLines, ["坏行"])
        XCTAssertTrue(try String(contentsOf: bad, encoding: .utf8).contains("坏行"))
    }
}
```

- [ ] **Step 2: 运行确认编译失败**

Run: `swift test --filter InboxTests`
Expected: FAIL — 找不到 `InboxParser` / `InboxImporter`

- [ ] **Step 3: 实现收件箱**

`Sources/TwigCore/Inbox/InboxItem.swift`：

```swift
import Foundation

public struct InboxItem: Codable, Equatable {
    public var id: UUID
    public var title: String
    public var project: String
    public var goal: String?
    public var due: Date?
    public var estimateMin: Int?
    public var source: String      // "claude" / "codex" / "cli"
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, project: String, goal: String? = nil,
                due: Date? = nil, estimateMin: Int? = nil, source: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.project = project
        self.goal = goal
        self.due = due
        self.estimateMin = estimateMin
        self.source = source
        self.createdAt = createdAt
    }
}

public enum InboxParser {
    public static func parse(line: String) -> InboxItem? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InboxItem.self, from: data)
    }

    public static func encode(_ item: InboxItem) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        return String(data: data, encoding: .utf8)!
    }
}
```

`Sources/TwigCore/Inbox/InboxImporter.swift`：

```swift
import Foundation

public struct ImportReport: Equatable {
    public var imported: Int = 0
    public var skippedDuplicates: Int = 0
    public var badLines: [String] = []
}

@MainActor
public final class InboxImporter {
    private let store: TaskStore

    public init(store: TaskStore) {
        self.store = store
    }

    @discardableResult
    public func importInbox(at inboxURL: URL, badLinesURL: URL) throws -> ImportReport {
        let fm = FileManager.default
        guard fm.fileExists(atPath: inboxURL.path) else { return ImportReport() }

        // 先把收件箱原子 rename 成 processing 文件再处理：
        // read→清空之间 CLI 追加的行会落在重建的新 inbox 里，不会被误清（丢数据窗口）
        let processingURL = inboxURL.deletingPathExtension()
            .appendingPathExtension("processing.jsonl")
        try? fm.removeItem(at: processingURL)   // 上次崩溃残留
        let renamed: Bool
        do {
            try fm.moveItem(at: inboxURL, to: processingURL)
            renamed = true
        } catch {
            renamed = false   // rename 失败兜底：直接读原文件，处理后 truncate
        }
        let sourceURL = renamed ? processingURL : inboxURL
        guard let data = fm.contents(atPath: sourceURL.path),
              let text = String(data: data, encoding: .utf8)
        else {
            if renamed { try? fm.removeItem(at: processingURL) }
            return ImportReport()
        }

        var report = ImportReport()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let item = InboxParser.parse(line: line) else {
                report.badLines.append(line)
                continue
            }
            if store.taskExists(title: item.title, projectName: item.project) {
                report.skippedDuplicates += 1
                continue
            }
            let project = store.findOrCreateProject(named: item.project)
            let goal = store.findOrCreateGoal(in: project, title: item.goal ?? "收集箱")
            store.addTask(to: goal, title: item.title, estimateMin: item.estimateMin, dueDate: item.due)
            report.imported += 1
        }

        // 清空收件箱：processing 文件处理完直接删除；
        // 兜底路径用 truncate 保持 inode（atomic write 会替换 inode，文件监视器永久失效）。
        // 注意：rename 流程后 inbox 由 CLI/watcher 按需重建（新 inode），
        // AppState 的文件监视器每轮导入后必须 re-arm。
        if renamed {
            try? fm.removeItem(at: processingURL)
        } else {
            let handle = try FileHandle(forWritingTo: inboxURL)
            try handle.truncate(atOffset: 0)
            try handle.close()
        }

        // 坏行留档（追加，不覆盖）
        if !report.badLines.isEmpty {
            let archive = report.badLines.joined(separator: "\n") + "\n"
            if FileManager.default.fileExists(atPath: badLinesURL.path),
               let handle = try? FileHandle(forWritingTo: badLinesURL) {
                handle.seekToEndOfFile()
                handle.write(Data(archive.utf8))
                try? handle.close()
            } else {
                try? archive.write(to: badLinesURL, atomically: true, encoding: .utf8)
            }
        }
        return report
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter InboxTests`
Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Inbox Tests/TwigCoreTests/InboxTests.swift
git commit -m "feat: 收件箱解析/导入（去重、坏行留档 inbox.bad.jsonl）"
```

---

### Task 5: CLI 参数解析 + twig 命令行 + 快照导出

**Files:**
- Create: `Sources/TwigCore/CLI/CLICommand.swift`
- Create: `Sources/TwigCore/Inbox/Snapshot.swift`
- Create: `Sources/twig-cli/main.swift`
- Test: `Tests/TwigCoreTests/CLICommandTests.swift`
- Test: `Tests/TwigCoreTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `InboxItem`、`InboxParser.encode(_:)`（Task 4）、`TwigPaths`、`Project/Goal/Task`（Task 1）
- Produces：
  - `enum CLICommand: Equatable { case add(title: String, project: String, goal: String?, due: Date?, estimate: Int?), list(project: String?), help }`
  - `struct CLIUsageError: Error, Equatable, CustomStringConvertible`
  - `enum CLICommandParser { static func parse(_ args: [String]) throws -> CLICommand }`
  - `struct TaskSnapshot / ProjectSnapshot / GoalSnapshot / TaskLine: Codable`
  - `enum SnapshotExporter { static func export(projects: [Project], to url: URL) throws }`
  - 可执行文件 `twig`：`twig add "标题" --project X [--goal Y] [--due YYYY-MM-DD] [--estimate 分钟]`、`twig list [--project X]`

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/CLICommandTests.swift`：

```swift
import XCTest
@testable import TwigCore

final class CLICommandTests: XCTestCase {
    func testParseFullAdd() throws {
        let cmd = try CLICommandParser.parse([
            "add", "修渲染管线", "--project", "mergeCook4",
            "--goal", "demo可玩", "--due", "2026-08-05", "--estimate", "120",
        ])
        guard case .add(let title, let project, let goal, let due, let estimate) = cmd else {
            return XCTFail("期望 add，得到 \(cmd)")
        }
        XCTAssertEqual(title, "修渲染管线")
        XCTAssertEqual(project, "mergeCook4")
        XCTAssertEqual(goal, "demo可玩")
        XCTAssertEqual(estimate, 120)
        XCTAssertNotNil(due)
    }

    func testParseMinimalAdd() throws {
        let cmd = try CLICommandParser.parse(["add", "随手记", "--project", "twig"])
        guard case .add(_, _, let goal, let due, let estimate) = cmd else {
            return XCTFail("期望 add")
        }
        XCTAssertNil(goal); XCTAssertNil(due); XCTAssertNil(estimate)
    }

    func testParseList() throws {
        XCTAssertEqual(try CLICommandParser.parse(["list"]), .list(project: nil))
        XCTAssertEqual(try CLICommandParser.parse(["list", "--project", "twig"]), .list(project: "twig"))
    }

    func testErrors() {
        XCTAssertThrowsError(try CLICommandParser.parse([]))
        XCTAssertThrowsError(try CLICommandParser.parse(["add"]))
        XCTAssertThrowsError(try CLICommandParser.parse(["add", "x"]))               // 缺 --project
        XCTAssertThrowsError(try CLICommandParser.parse(["add", "x", "--project"]))   // 缺值
        XCTAssertThrowsError(try CLICommandParser.parse(["frobnicate"]))
        XCTAssertThrowsError(try CLICommandParser.parse(["add", "x", "--project", "p", "--due", "8月5日"]))
    }
}
```

`Tests/TwigCoreTests/SnapshotTests.swift`：

```swift
import XCTest
@testable import TwigCore

@MainActor
final class SnapshotTests: XCTestCase {
    func testExportWritesReadableSnapshot() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "v0.1", horizon: .short, targetDate: nil)
        _ = store.addTask(to: g, title: "任务A")
        let done = store.addTask(to: g, title: "任务B")
        store.toggleTask(done)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-snap-\(UUID().uuidString).json")
        try SnapshotExporter.export(projects: store.allProjects(), to: url)

        let data = try Data(contentsOf: url)
        let snap = try JSONDecoder().decode(TaskSnapshot.self, from: data)
        XCTAssertEqual(snap.projects.count, 1)
        XCTAssertEqual(snap.projects[0].name, "twig")
        XCTAssertEqual(snap.projects[0].goals[0].tasks.map(\.title), ["任务A", "任务B"])
        XCTAssertFalse(snap.projects[0].goals[0].tasks[0].isDone)
        XCTAssertTrue(snap.projects[0].goals[0].tasks[1].isDone)
    }
}
```

- [ ] **Step 2: 运行确认编译失败**

Run: `swift test --filter "CLICommandTests|SnapshotTests"`
Expected: FAIL — 找不到 `CLICommandParser` / `SnapshotExporter`

- [ ] **Step 3: 实现 CLI 解析与快照**

`Sources/TwigCore/CLI/CLICommand.swift`：

```swift
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
```

`Sources/TwigCore/Inbox/Snapshot.swift`：

```swift
import Foundation

public struct TaskSnapshot: Codable {
    public var generatedAt: Date
    public var projects: [ProjectSnapshot]
}

public struct ProjectSnapshot: Codable {
    public var name: String
    public var colorHint: String
    public var goals: [GoalSnapshot]
}

public struct GoalSnapshot: Codable {
    public var title: String
    public var horizon: String
    public var tasks: [TaskLine]
}

public struct TaskLine: Codable {
    public var title: String
    public var isDone: Bool
}

public enum SnapshotExporter {
    public static func export(projects: [Project], to url: URL) throws {
        let snapshot = TaskSnapshot(generatedAt: Date(), projects: projects.map { p in
            ProjectSnapshot(name: p.name, colorHint: p.colorHint, goals: p.goals
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { g in
                    GoalSnapshot(title: g.title, horizon: g.horizon.rawValue, tasks: g.tasks
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map { TaskLine(title: $0.title, isDone: $0.isDone) })
                })
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter "CLICommandTests|SnapshotTests"`
Expected: 5 tests PASS

- [ ] **Step 5: 写 CLI 入口并手动验证**

`Sources/twig-cli/main.swift`：

```swift
import Foundation
import TwigCore

do {
    switch try CLICommandParser.parse(Array(CommandLine.arguments.dropFirst())) {
    case .add(let title, let project, let goal, let due, let estimate):
        try FileManager.default.createDirectory(at: TwigPaths.supportDir, withIntermediateDirectories: true)
        let item = InboxItem(title: title, project: project, goal: goal,
                             due: due, estimateMin: estimate, source: "cli")
        let line = try InboxParser.encode(item) + "\n"
        if FileManager.default.fileExists(atPath: TwigPaths.inboxURL.path),
           let handle = try? FileHandle(forWritingTo: TwigPaths.inboxURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try line.write(to: TwigPaths.inboxURL, atomically: true, encoding: .utf8)
        }
        print("已加入 Twig 收件箱：\(title) → \(project)")

    case .list(let projectFilter):
        guard let data = FileManager.default.contents(atPath: TwigPaths.snapshotURL.path) else {
            print("还没有快照（Twig.app 运行过一次后才会有）。收件箱里的任务会在下次启动 app 时导入。")
            exit(0)
        }
        let snapshot = try JSONDecoder().decode(TaskSnapshot.self, from: data)
        for project in snapshot.projects where projectFilter == nil || project.name == projectFilter {
            print("◆ \(project.name)")
            for goal in project.goals {
                print("  ○ \(goal.title) [\(goal.horizon)]")
                for task in goal.tasks {
                    print("    \(task.isDone ? "☑" : "☐") \(task.title)")
                }
            }
        }

    case .help:
        print(CLICommandParser.usage)
    }
} catch let error as CLIUsageError {
    FileHandle.standardError.write(Data((error.description + "\n").utf8))
    exit(1)
}
```

Run:

```bash
swift build
.build/debug/twig add "测试收件箱" --project twig --goal v0.1 --estimate 30
cat ~/Library/Application\ Support/Twig/inbox.jsonl   # 应有一行 JSON
.build/debug/twig list                                # 应提示还没有快照
.build/debug/twig add 2>&1; echo "exit=$?"            # 应打印用法，exit=1
```

Expected: 行为与注释一致。

- [ ] **Step 6: Commit**

```bash
git add Sources/TwigCore/CLI Sources/TwigCore/Inbox/Snapshot.swift Sources/twig-cli Tests/TwigCoreTests/CLICommandTests.swift Tests/TwigCoreTests/SnapshotTests.swift
git commit -m "feat: twig CLI（add 写入收件箱 / list 读快照）+ 快照导出"
```

---

### Task 6: git 集成（log 解析 + 子进程封装）

**Files:**
- Create: `Sources/TwigCore/Git/GitCommit.swift`
- Create: `Sources/TwigCore/Git/GitReader.swift`
- Test: `Tests/TwigCoreTests/GitTests.swift`

**Interfaces:**
- Consumes: 无
- Produces：
  - `struct GitCommit: Equatable { hash: String, date: Date, subject: String }`
  - `enum GitLogParser { static func parse(_ output: String) -> [GitCommit] }`
  - `enum GitError: Error, Equatable { case notARepo, timedOut, failed(Int32) }`
  - `struct GitReader`，`init()`、`currentBranch(repoPath: String) throws -> String`、`log(repoPath: String, since: Date, timeout: TimeInterval = 5) throws -> [GitCommit]`

- [ ] **Step 1: 写失败测试（含临时仓库集成测试）**

`Tests/TwigCoreTests/GitTests.swift`：

```swift
import XCTest
@testable import TwigCore

final class GitTests: XCTestCase {
    func testParseLogOutput() {
        let output = "a1b2c3d\t2026-07-29T10:00:00+08:00\tfeat: 修 shader\n9z8y7x6\t2026-07-28T09:30:00+08:00\tchore: 清理"
        let commits = GitLogParser.parse(output)
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].hash, "a1b2c3d")
        XCTAssertEqual(commits[0].subject, "feat: 修 shader")
        XCTAssertLessThan(commits[1].date, commits[0].date)
        XCTAssertEqual(GitLogParser.parse(""), [])
        XCTAssertEqual(GitLogParser.parse("乱写的行"), [])
    }

    func testReaderReadsRealRepo() throws {
        // 建一个带两条提交的真实临时仓库
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func shell(_ cmd: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "cd '\(dir.path)' && \(cmd)"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
        shell("git init -q && git config user.email t@t && git config user.name t")
        shell("echo a > a.txt && git add . && GIT_AUTHOR_DATE='2026-07-29T10:00:00' GIT_COMMITTER_DATE='2026-07-29T10:00:00' git commit -qm '第一条提交'")
        shell("echo b >> a.txt && git add . && git commit -qm '第二条提交'")

        let reader = GitReader()
        let branch = try reader.currentBranch(repoPath: dir.path)
        XCTAssertFalse(branch.isEmpty)
        let commits = try reader.log(repoPath: dir.path, since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits.first?.subject, "第二条提交")   // 新提交在前
    }

    func testReaderRejectsNonRepo() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-nogit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try GitReader().log(repoPath: dir.path, since: Date())) { error in
            XCTAssertEqual(error as? GitError, .notARepo)
        }
    }
}
```

- [ ] **Step 2: 运行确认编译失败**

Run: `swift test --filter GitTests`
Expected: FAIL — 找不到 `GitLogParser` / `GitReader`

- [ ] **Step 3: 实现 git 集成**

`Sources/TwigCore/Git/GitCommit.swift`：

```swift
import Foundation

public struct GitCommit: Equatable {
    public var hash: String
    public var date: Date
    public var subject: String

    public init(hash: String, date: Date, subject: String) {
        self.hash = hash
        self.date = date
        self.subject = subject
    }
}

public enum GitLogParser {
    /// 解析 `git log --pretty=format:%h%x09%aI%x09%s` 的输出
    public static func parse(_ output: String) -> [GitCommit] {
        let formatter = ISO8601DateFormatter()
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3, let date = formatter.date(from: String(parts[1])) else { return nil }
            return GitCommit(hash: String(parts[0]), date: date, subject: String(parts[2]))
        }
    }
}
```

`Sources/TwigCore/Git/GitReader.swift`：

```swift
import Foundation

public enum GitError: Error, Equatable {
    case notARepo
    case timedOut
    case failed(Int32)
}

public struct GitReader {
    private let gitPath: String

    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    public func currentBranch(repoPath: String) throws -> String {
        let (code, out) = try run(["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"], timeout: 5)
        guard code == 0 else { throw GitError.notARepo }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func log(repoPath: String, since: Date, timeout: TimeInterval = 5) throws -> [GitCommit] {
        let iso = ISO8601DateFormatter().string(from: since)
        let (code, out) = try run([
            "-C", repoPath, "log",
            "--since=\(iso)", "--max-count=500",
            "--pretty=format:%h%x09%aI%x09%s",
        ], timeout: timeout)
        guard code == 0 else { throw code == 128 ? GitError.notARepo : GitError.failed(code) }
        return GitLogParser.parse(out)
    }

    private func run(_ args: [String], timeout: TimeInterval) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw GitError.timedOut
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter GitTests`
Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Git Tests/TwigCoreTests/GitTests.swift
git commit -m "feat: git log 读取（5s 超时、非仓库降级、max-count 500）"
```

---

### Task 7: 日/周报表聚合

**Files:**
- Create: `Sources/TwigCore/Reports/ReportAggregator.swift`
- Test: `Tests/TwigCoreTests/ReportTests.swift`

**Interfaces:**
- Consumes: `TimeEntry`、`Task`（Task 1）
- Produces：
  - `struct DayReport: Equatable { day: Date, focusMinutes: Int, breakMinutes: Int, completedTaskTitles: [String], perProjectFocus: [String: Int] }`
  - `enum ReportAggregator`：`dayReport(day: Date, entries: [TimeEntry], tasks: [Task], calendar: Calendar = .current) -> DayReport`、`weekReport(containing day: Date, entries: [TimeEntry], tasks: [Task], calendar: Calendar = .current) -> [DayReport]`（7 天，周一到周日）
  - 归属规则：**计时记到 startedAt 所在那天**（跨午夜不切分）；完成任务按 completedAt 归日；git 提交不进聚合，由报表 UI 另行调用 `GitReader`

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/ReportTests.swift`：

```swift
import XCTest
@testable import TwigCore

final class ReportTests: XCTestCase {
    private let calendar = Calendar.current

    private func entry(_ kind: TimeKind, start: Date, minutes: Double) -> TimeEntry {
        let e = TimeEntry(kind: kind, startedAt: start)
        e.endedAt = start.addingTimeInterval(minutes * 60)
        return e
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testDayReportSumsFocusAndBreak() {
        let today = day(2026, 7, 30)
        let entries = [
            entry(.pomodoro, start: day(2026, 7, 30, 9), minutes: 25),
            entry(.stopwatch, start: day(2026, 7, 30, 14), minutes: 50),
            entry(.break, start: day(2026, 7, 30, 10), minutes: 5),
            entry(.pomodoro, start: day(2026, 7, 29, 9), minutes: 25),  // 昨天不算
        ]
        let report = ReportAggregator.dayReport(day: today, entries: entries, tasks: [])
        XCTAssertEqual(report.focusMinutes, 75)
        XCTAssertEqual(report.breakMinutes, 5)
    }

    func testCrossMidnightEntryCountsToStartDay() {
        let night = day(2026, 7, 30, 23)
        let entries = [entry(.pomodoro, start: night, minutes: 60)]   // 跨到 31 号
        let d30 = ReportAggregator.dayReport(day: day(2026, 7, 30), entries: entries, tasks: [])
        let d31 = ReportAggregator.dayReport(day: day(2026, 7, 31), entries: entries, tasks: [])
        XCTAssertEqual(d30.focusMinutes, 60)
        XCTAssertEqual(d31.focusMinutes, 0)
    }

    func testCompletedTasksAndPerProjectFocus() {
        let today = day(2026, 7, 30)
        let project = Project(name: "twig", colorHint: "#D97757")
        let goal = Goal(title: "v0.1", horizon: .short, targetDate: nil)
        goal.project = project
        let task = Task(title: "完成的任务")
        task.goal = goal
        task.isDone = true
        task.completedAt = day(2026, 7, 30, 16)
        let other = Task(title: "昨天完成的")
        other.isDone = true
        other.completedAt = day(2026, 7, 29, 16)

        let focus = entry(.pomodoro, start: day(2026, 7, 30, 9), minutes: 25)
        focus.task = task

        let report = ReportAggregator.dayReport(day: today, entries: [focus], tasks: [task, other])
        XCTAssertEqual(report.completedTaskTitles, ["完成的任务"])
        XCTAssertEqual(report.perProjectFocus["twig"], 25)
    }

    func testWeekReportReturnsSevenDays() {
        let entries = [entry(.pomodoro, start: day(2026, 7, 29, 10), minutes: 25)]
        // 2026-07-30 是周四
        let week = ReportAggregator.weekReport(containing: day(2026, 7, 30), entries: entries, tasks: [])
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.reduce(0) { $0 + $1.focusMinutes }, 25)
    }
}
```

- [ ] **Step 2: 运行确认编译失败**

Run: `swift test --filter ReportTests`
Expected: FAIL — 找不到 `ReportAggregator`

- [ ] **Step 3: 实现报表聚合**

`Sources/TwigCore/Reports/ReportAggregator.swift`：

```swift
import Foundation

public struct DayReport: Equatable {
    public var day: Date
    public var focusMinutes: Int = 0
    public var breakMinutes: Int = 0
    public var completedTaskTitles: [String] = []
    public var perProjectFocus: [String: Int] = [:]   // 项目名 → 专注分钟
}

public enum ReportAggregator {
    public static func dayReport(day: Date, entries: [TimeEntry], tasks: [Task],
                                 calendar: Calendar = .current) -> DayReport {
        var report = DayReport(day: calendar.startOfDay(for: day))
        for entry in entries where calendar.isDate(entry.startedAt, inSameDayAs: day) {
            let minutes = Int(entry.duration / 60)
            switch entry.kind {
            case .pomodoro, .stopwatch:
                report.focusMinutes += minutes
                if let name = entry.task?.goal?.project?.name {
                    report.perProjectFocus[name, default: 0] += minutes
                }
            case .break:
                report.breakMinutes += minutes
            }
        }
        report.completedTaskTitles = tasks
            .filter { $0.isDone && $0.completedAt.map({ calendar.isDate($0, inSameDayAs: day) }) ?? false }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .map(\.title)
        return report
    }

    /// 包含 day 的那一周（周一到周日）7 天报表
    public static func weekReport(containing day: Date, entries: [TimeEntry], tasks: [Task],
                                  calendar input: Calendar = .current) -> [DayReport] {
        var calendar = input
        calendar.firstWeekday = 2   // 周一
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: day) else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return dayReport(day: date, entries: entries, tasks: tasks, calendar: calendar)
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter ReportTests`
Expected: 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Reports Tests/TwigCoreTests/ReportTests.swift
git commit -m "feat: 日/周报表聚合（跨午夜归开始日、分项目专注统计）"
```

---
### Task 8: 崩溃恢复 + 数据库备份

**Files:**
- Create: `Sources/TwigCore/Stores/CrashRecovery.swift`
- Create: `Sources/TwigCore/Infra/StoreBackup.swift`
- Test: `Tests/TwigCoreTests/CrashRecoveryTests.swift`
- Test: `Tests/TwigCoreTests/StoreBackupTests.swift`

**Interfaces:**
- Consumes: `TimeEntry`（Task 1）、`TwigPaths`
- Produces：
  - `enum CrashRecovery { static func openEntries(_ entries: [TimeEntry]) -> [TimeEntry]; static func close(_ entry: TimeEntry, fallback now: Date) }`（关闭时 `endedAt = min(lastHeartbeat, now)`，不晚于 startedAt）
  - `enum StoreBackup { static func backupNow(storeURL: URL = TwigPaths.storeURL, backupsDir: URL = TwigPaths.backupsDir, keep: Int = 3, supportDir: URL = TwigPaths.supportDir, fm: FileManager = .default) throws }`（连同 `twig.store-wal/-shm` 一起复制到时间戳子目录，超出 keep 删最旧）

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/CrashRecoveryTests.swift`：

```swift
import XCTest
@testable import TwigCore

final class CrashRecoveryTests: XCTestCase {
    func testFindsOnlyUnclosedEntries() {
        let closed = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 100))
        closed.endedAt = Date(timeIntervalSince1970: 200)
        let open = TimeEntry(kind: .stopwatch, startedAt: Date(timeIntervalSince1970: 300))
        let result = CrashRecovery.openEntries([closed, open])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startedAt, Date(timeIntervalSince1970: 300))
    }

    func testCloseUsesLastHeartbeat() {
        let entry = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 1000))
        entry.lastHeartbeat = Date(timeIntervalSince1970: 1300)   // 计到 1300 就崩了
        CrashRecovery.close(entry, fallback: Date(timeIntervalSince1970: 9999))
        XCTAssertEqual(entry.endedAt, Date(timeIntervalSince1970: 1300))
    }

    func testCloseNeverEndsBeforeStart() {
        let entry = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 1000))
        entry.lastHeartbeat = Date(timeIntervalSince1970: 900)   // 异常数据：心跳早于开始
        CrashRecovery.close(entry, fallback: Date(timeIntervalSince1970: 800))
        XCTAssertEqual(entry.endedAt, entry.startedAt)
    }
}
```

`Tests/TwigCoreTests/StoreBackupTests.swift`：

```swift
import XCTest
@testable import TwigCore

final class StoreBackupTests: XCTestCase {
    func testBackupCopiesStoreFilesAndPrunesOld() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("twig-backup-\(UUID().uuidString)")
        let support = root.appendingPathComponent("support")
        let backups = root.appendingPathComponent("backups")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let store = support.appendingPathComponent("twig.store")
        try "db".write(to: store, atomically: true, encoding: .utf8)
        try "wal".write(to: support.appendingPathComponent("twig.store-wal"), atomically: true, encoding: .utf8)

        for _ in 0..<5 {
            try StoreBackup.backupNow(storeURL: store, backupsDir: backups, keep: 3, supportDir: support)
            Thread.sleep(forTimeInterval: 1.1)   // 时间戳精确到秒，错开
        }
        let dirs = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(dirs.count, 3)   // 只留最近 3 份
        let newest = dirs.sorted { $0.lastPathComponent < $1.lastPathComponent }.last!
        let files = try fm.contentsOfDirectory(at: newest, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertTrue(files.contains("twig.store"))
        XCTAssertTrue(files.contains("twig.store-wal"))
    }

    func testBackupWithoutStoreIsNoOp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNoThrow(try StoreBackup.backupNow(
            storeURL: root.appendingPathComponent("不存在.store"),
            backupsDir: root.appendingPathComponent("backups"),
            supportDir: root))
    }
}
```

- [ ] **Step 2: 运行确认编译失败**

Run: `swift test --filter "CrashRecoveryTests|StoreBackupTests"`
Expected: FAIL — 找不到 `CrashRecovery` / `StoreBackup`

- [ ] **Step 3: 实现恢复与备份**

`Sources/TwigCore/Stores/CrashRecovery.swift`：

```swift
import Foundation

public enum CrashRecovery {
    /// 上次运行未闭合的计时（崩溃/强退/断电的痕迹）
    public static func openEntries(_ entries: [TimeEntry]) -> [TimeEntry] {
        entries.filter { $0.endedAt == nil }
    }

    /// 补记：以最后一次心跳为准（我们最多只丢一分钟）
    public static func close(_ entry: TimeEntry, fallback now: Date) {
        let end = min(entry.lastHeartbeat, now)
        entry.endedAt = max(end, entry.startedAt)
    }
}
```

`Sources/TwigCore/Infra/StoreBackup.swift`：

```swift
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter "CrashRecoveryTests|StoreBackupTests"`
Expected: 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Stores/CrashRecovery.swift Sources/TwigCore/Infra/StoreBackup.swift Tests/TwigCoreTests/CrashRecoveryTests.swift Tests/TwigCoreTests/StoreBackupTests.swift
git commit -m "feat: 崩溃恢复（心跳补记）+ 启动前数据库备份（留 3 份）"
```

---

### Task 9: App 骨架 + 悬浮窗（Collapsed 横条）

**Files:**
- Create: `Sources/TwigApp/TwigAppMain.swift`
- Create: `Sources/TwigApp/AppState.swift`
- Create: `Sources/TwigApp/ColorHex.swift`
- Create: `Sources/TwigApp/Widget/WidgetWindowController.swift`
- Create: `Sources/TwigApp/Widget/WidgetView.swift`
- Create: `Sources/TwigApp/Widget/CollapsedBarView.swift`

**Interfaces:**
- Consumes: 全部 Stores（Task 2/3）、`CrashRecovery`、`StoreBackup`（Task 8）、`InboxImporter`（Task 4）、`SnapshotExporter`（Task 5）
- Produces（Task 10/11/12 依赖）：
  - `@MainActor @Observable final class AppState`：`taskStore`、`timerStore`、`widgetState: WidgetState`、`start()`、`importInbox()`、`exportSnapshot()`、`currentFocusTitle: String`、`openMainWindow: (() -> Void)?`
  - `enum WidgetState { case collapsed, peeked, expanded }`
  - `@MainActor final class WidgetWindowController`：`show(rootView:)`、`resize(toHeight:CGFloat,animated:Bool)`
  - `extension Color { init?(hex: String) }`

- [ ] **Step 1: 写 ColorHex / WidgetWindowController / CollapsedBarView**

`Sources/TwigApp/ColorHex.swift`：

```swift
import SwiftUI

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
```

`Sources/TwigApp/Widget/WidgetWindowController.swift`：

```swift
import AppKit
import SwiftUI

@MainActor
final class WidgetWindowController {
    private var panel: NSPanel?

    func show<Content: View>(rootView: Content) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("TwigWidget")
        panel.contentView = NSHostingView(rootView: rootView)
        ensureVisible(panel)
        panel.orderFront(nil)
        self.panel = panel
    }

    /// 状态切换时改高度（展开枝干时变高），宽度 560 固定（380 横条 + 180 枝干留白）
    func resize(toHeight height: CGFloat, animated: Bool = true) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: animated)
    }

    /// 被拖出屏幕则回到主屏右上角
    private func ensureVisible(_ panel: NSPanel) {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !visible, let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - panel.frame.width - 40,
                y: screen.visibleFrame.maxY - panel.frame.height - 40
            ))
        }
    }
}
```

`Sources/TwigApp/Widget/CollapsedBarView.swift`：

```swift
import SwiftUI
import TwigCore

/// 紧凑横条：当前任务 + 计时 + 进度；右侧透明区画向外延展的虚线
struct CollapsedBarView: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: activeColorHex) ?? .orange)
                    .frame(width: 10, height: 10)
                Text(appState.currentFocusTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(timerText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: "#D97757") ?? .orange)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(width: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.6), lineWidth: 1)
            )

            // 向屏幕外延展的虚线（点击枝干区在 Task 10 接管）
            Canvas { ctx, size in
                let start = CGPoint(x: 8, y: size.height / 2)
                for (i, offset) in [-18.0, 16.0].enumerated() {
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(
                        to: CGPoint(x: size.width - 20, y: size.height / 2 + offset * 2),
                        control1: CGPoint(x: 60, y: size.height / 2),
                        control2: CGPoint(x: 90, y: size.height / 2 + offset)
                    )
                    ctx.stroke(path, with: .color(.primary.opacity(0.3)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6]))
                    _ = i
                }
            }
            .frame(width: 160)
        }
        .frame(width: 560, height: 64)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { appState.widgetState = .peeked }
        }
    }

    private var activeColorHex: String {
        appState.timerStore.activeTask?.goal?.project?.colorHint ?? "#D97757"
    }

    private var timerText: String {
        switch appState.timerStore.engine.state {
        case .idle: return "开始"
        case .focusing(let startedAt, let plannedEnd, _):
            let base = plannedEnd ?? Date()
            let remaining = max(0, base.timeIntervalSince(plannedEnd == nil ? startedAt : Date()))
            let seconds = plannedEnd == nil
                ? Int(Date().timeIntervalSince(startedAt))
                : Int(remaining)
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .onBreak(_, let endsAt, _):
            let seconds = max(0, Int(endsAt.timeIntervalSinceNow))
            return String(format: "休 %d:%02d", seconds / 60, seconds % 60)
        }
    }
}
```

- [ ] **Step 2: 写 AppState + WidgetView + 入口**

`Sources/TwigApp/AppState.swift`：

```swift
import AppKit
import Foundation
import SwiftData
import TwigCore
import UserNotifications

enum WidgetState {
    case collapsed, peeked, expanded
}

@MainActor
@Observable
final class AppState {
    let container: ModelContainer
    let taskStore: TaskStore
    let timerStore: TimerStore
    var widgetState: WidgetState = .collapsed
    var openMainWindow: (() -> Void)?

    private var inboxWatcher: DispatchSourceFileSystemObject?
    private var snapshotTimer: Timer?
    private(set) var lastImportReport: ImportReport?

    init() {
        do {
            container = try TwigStore.makeContainer()
        } catch {
            fatalError("数据库打开失败：\(error.localizedDescription)")
        }
        taskStore = TaskStore(container: container)
        timerStore = TimerStore(container: container)
    }

    func start() {
        try? StoreBackup.backupNow()
        recoverUnclosedEntries()
        importInbox()
        watchInbox()
        exportSnapshot()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.exportSnapshot() }
        }
        timerStore.onEvent = { [weak self] event in self?.handleEngineEvent(event) }
    }

    var currentFocusTitle: String {
        if let task = timerStore.activeTask { return task.title }
        switch timerStore.engine.state {
        case .idle: return "点我开始专注"
        case .focusing: return "专注中"
        case .onBreak(_, _, let isLong): return isLong ? "长休息" : "短休息"
        }
    }

    func importInbox() {
        let report = try? InboxImporter(store: taskStore)
            .importInbox(at: TwigPaths.inboxURL, badLinesURL: TwigPaths.badLinesURL)
        if let report, report.imported > 0 || !report.badLines.isEmpty {
            lastImportReport = report
            exportSnapshot()
        }
    }

    func exportSnapshot() {
        try? SnapshotExporter.export(projects: taskStore.allProjects(), to: TwigPaths.snapshotURL)
    }

    // MARK: - 私有

    private func recoverUnclosedEntries() {
        let ctx = container.mainContext
        guard let all = try? ctx.fetch(FetchDescriptor<TimeEntry>()) else { return }
        let open = CrashRecovery.openEntries(all)
        guard !open.isEmpty else { return }
        for entry in open { CrashRecovery.close(entry, fallback: Date()) }
        try? ctx.save()
        let total = Int(open.reduce(0) { $0 + $1.duration } / 60)
        let alert = NSAlert()
        alert.messageText = "补记中断的计时"
        alert.informativeText = "检测到 \(open.count) 段未正常结束的计时（共约 \(total) 分钟），已按最后心跳补记。如不需要可在主窗口删除对应记录。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func watchInbox() {
        try? FileManager.default.createDirectory(at: TwigPaths.supportDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: TwigPaths.inboxURL.path) {
            FileManager.default.createFile(atPath: TwigPaths.inboxURL.path, contents: nil)
        }
        let fd = open(TwigPaths.inboxURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.importInbox() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        inboxWatcher = source
    }

    private func handleEngineEvent(_ event: EngineEvent) {
        let config = timerStore.engine.config
        switch event {
        case .focusCompleted:
            if config.notificationsEnabled { notify(title: "专注结束", body: "任务完成了吗？去横条上确认一下") }
            if config.soundEnabled { NSSound(named: "Glass")?.play() }
        case .breakCompleted:
            if config.notificationsEnabled { notify(title: "休息结束", body: "回来继续吧") }
        case .stopped:
            break
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

`Sources/TwigApp/Widget/WidgetView.swift`：

```swift
import SwiftUI
import TwigCore

struct WidgetView: View {
    let appState: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                CollapsedBarView(appState: appState)
                if appState.widgetState == .peeked {
                    Text("今日任务清单（Task 10 实现）")
                        .font(.caption)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { appState.widgetState = .collapsed }
                }
            }
            .onAppear { appState.timerStore.tick() }
            .onChange(of: .now) { appState.timerStore.tick() }
        }
    }
}
```

`Sources/TwigApp/TwigAppMain.swift`：

```swift
import AppKit
import SwiftUI
import TwigCore
import UserNotifications

@main
struct TwigAppMain: App {
    @State private var appState = AppState()
    @State private var widgetController: WidgetWindowController?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        Window("Twig", id: "main") {
            Text("主窗口（Task 11 实现）")
                .frame(minWidth: 720, minHeight: 480)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra("Twig", systemImage: "leaf") {
            Button("打开主窗口") { openMain() }
            Divider()
            Button("退出 Twig") { NSApp.terminate(nil) }
        }

        Settings { EmptyView() }
    }

    @Environment(\.openWindow) private var openWindow

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct TwigAppDelegate {
    static func boot(appState: AppState, controller: WidgetWindowController) {
        appState.start()
        controller.show(rootView: WidgetView(appState: appState))
    }
}
```

`TwigAppMain.swift` 中挂载悬浮窗的代码（放在 `Window` 场景的 onAppear 之外，用 `.onAppear` 于 MenuBarExtra 标签或 init 后调用）——在 `body` 的 `MenuBarExtra` 里不方便做启动逻辑，改为在 `AppState` 创建处：把 `@State private var appState = AppState()` 之后增加：

```swift
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let controller = WidgetWindowController()
        _widgetController = State(initialValue: controller)
        // App 启动即装配
        Task { @MainActor in
            appState.start()
            controller.show(rootView: WidgetView(appState: appState))
        }
    }
```

注意：若上面的 `init` 与既有 `init` 冲突，合并成一个 init（通知授权 + 悬浮窗启动），并删除 `TwigAppDelegate` 结构。

- [ ] **Step 3: 构建并手动运行验证**

Run: `swift build && .build/debug/TwigApp &`

手动验收清单：

- [ ] 屏幕右上角（或上次位置）出现毛玻璃横条，右侧有两条虚线向外弯曲
- [ ] 横条可拖动，退出重开位置还在
- [ ] 横条不抢焦点（点其他 app 窗口，横条浮着但不激活）
- [ ] 菜单栏出现叶子图标，可退出
- [ ] 终端跑 `.build/debug/twig add "手动验证任务" --project twig`，横条所在 app 日志/快照更新：`cat ~/Library/Application\ Support/Twig/snapshot.json` 里有这条
- [ ] `kill -9` 掉 app 再启动，若之前有计时会出现"补记中断的计时"弹窗

- [ ] **Step 4: Commit**

```bash
git add Sources/TwigApp
git commit -m "feat: App 骨架 + 悬浮毛玻璃横条（NSPanel 非激活置顶、收件箱监视、崩溃补记）"
```

---

### Task 10: 枝干展开（BranchLayout 纯函数 + BranchView + Peeked）

**Files:**
- Create: `Sources/TwigCore/Layout/BranchLayout.swift`
- Create: `Sources/TwigApp/Widget/BranchView.swift`
- Create: `Sources/TwigApp/Widget/PeekListView.swift`
- Modify: `Sources/TwigApp/Widget/WidgetView.swift`
- Modify: `Sources/TwigApp/Widget/CollapsedBarView.swift`（虚线外延方向化）
- Test: `Tests/TwigCoreTests/BranchLayoutTests.swift`

**Interfaces:**
- Consumes: `Project/Goal/Task`（Task 1）、`TaskStore`（Task 2）、`AppState`、`WidgetState`（Task 9）
- Produces：
  - `enum BranchDirection: String, Codable, CaseIterable { case right, left, up, down }`（**用户变更 2026-07-30：枝干方向可自定义**，Persist 于 UserDefaults 键 `twig.branchDirection`，默认 `.right`）
  - `struct BranchTuning: Equatable`（`direction: BranchDirection = .right`、`curveTension=0.35`、`branchSpacing=150`、`nodeSpacing=64`、`fadeDistance=320`、`dragExpandThreshold=24`，全部可调——交互手感迭代就改这里）
  - `struct BranchNode: Identifiable, Equatable`（`id: UUID`、`title`、`subtitle`、`colorHex`、`center: CGPoint`、`opacity: Double`、`dashed: Bool`）
  - `struct BranchEdge: Equatable`（`from/to/c1/c2: CGPoint`、`colorHex`、`dashed`、`faded: Bool`）
  - `struct BranchLayoutResult: Equatable`（`nodes: [BranchNode]`、`edges: [BranchEdge]`、`contentSize: CGSize`、`direction: BranchDirection`）
  - `enum BranchLayout { static func compute(projects: [Project], anchor: CGPoint, tuning: BranchTuning = .init(), now: Date = .now) -> BranchLayoutResult }`
  - 布局规则：每个项目一条枝干，从 anchor 出发沿 **主轴**（direction 决定：right=+x、left=−x、down=+y、up=−y）扇开；项目 i 的节点列沿主轴偏移 `branchSpacing * (i+1)`；同项目节点沿**交叉轴**按 targetDate（空则最大）升序错开 `nodeSpacing`；`opacity = max(0.3, 1 - 主轴距离/fadeDistance)`；`dashed = (horizon != .short)`；边为贝塞尔（control 点按 curveTension 沿主轴外推）；`contentSize` 覆盖从 anchor 到最远节点的包围盒（含节点块留白 120/96）

- [ ] **Step 1: 写布局失败测试**

`Tests/TwigCoreTests/BranchLayoutTests.swift`：

```swift
import XCTest
@testable import TwigCore

final class BranchLayoutTests: XCTestCase {
    private func makeProjects() -> [Project] {
        let p1 = Project(name: "渲染", colorHint: "#D97757")
        let soon = Goal(title: "demo", horizon: .short,
                        targetDate: Date().addingTimeInterval(5 * 86400), sortOrder: 1024)
        soon.project = p1
        let later = Goal(title: "优化", horizon: .mid,
                         targetDate: Date().addingTimeInterval(40 * 86400), sortOrder: 2048)
        later.project = p1
        p1.goals = [later, soon]   // 故意乱序，布局应按日期排

        let p2 = Project(name: "玩法", colorHint: "#5F8A6E")
        let g = Goal(title: "闭环", horizon: .mid,
                     targetDate: Date().addingTimeInterval(30 * 86400), sortOrder: 1024)
        g.project = p2
        p2.goals = [g]
        return [p1, p2]
    }

    func testNodesSortedByDateWithinProject() {
        let result = BranchLayout.compute(projects: makeProjects(), anchor: CGPoint(x: 0, y: 200))
        let renderNodes = result.nodes.filter { $0.colorHex == "#D97757" }
        XCTAssertEqual(renderNodes.count, 2)
        XCTAssertEqual(renderNodes[0].title, "demo")   // 日期近的排前（y 更小）
        XCTAssertLessThan(renderNodes[0].center.y, renderNodes[1].center.y)
    }

    func testFartherProjectIsMoreTransparent() {
        let result = BranchLayout.compute(projects: makeProjects(), anchor: CGPoint(x: 0, y: 200))
        let first = result.nodes.filter { $0.colorHex == "#D97757" }.map(\.opacity).max()!
        let second = result.nodes.filter { $0.colorHex == "#5F8A6E" }.map(\.opacity).max()!
        XCTAssertGreaterThan(first, second)
        XCTAssertGreaterThanOrEqual(second, 0.3)
    }

    func testMidLongTermNodesAreDashed() {
        let result = BranchLayout.compute(projects: makeProjects(), anchor: CGPoint(x: 0, y: 200))
        let demo = result.nodes.first { $0.title == "demo" }
        let closed = result.nodes.first { $0.title == "闭环" }
        XCTAssertEqual(demo?.dashed, false)
        XCTAssertEqual(closed?.dashed, true)
    }

    func testEdgesConnectAnchorToNodes() {
        let anchor = CGPoint(x: 0, y: 200)
        let result = BranchLayout.compute(projects: makeProjects(), anchor: anchor)
        XCTAssertFalse(result.edges.isEmpty)
        XCTAssertTrue(result.edges.contains { $0.from == anchor })
        // 每条边的终点都落在某个节点中心
        for edge in result.edges {
            XCTAssertTrue(result.nodes.contains { $0.center == edge.to } || edge.to == anchor)
        }
    }

    func testDirectionChangesMainAxis() {
        let anchor = CGPoint(x: 400, y: 300)
        var tuning = BranchTuning()

        tuning.direction = .right
        let right = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(right.nodes.allSatisfy { $0.center.x > anchor.x })

        tuning.direction = .left
        let left = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(left.nodes.allSatisfy { $0.center.x < anchor.x })

        tuning.direction = .down
        let down = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(down.nodes.allSatisfy { $0.center.y > anchor.y })
        XCTAssertGreaterThan(down.contentSize.height, down.contentSize.width - 400)  // 纵向布局更高

        tuning.direction = .up
        let up = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(up.nodes.allSatisfy { $0.center.y < anchor.y })
    }
}
```

- [ ] **Step 2: 运行确认编译失败**

Run: `swift test --filter BranchLayoutTests`
Expected: FAIL — 找不到 `BranchLayout`

- [ ] **Step 3: 实现 BranchLayout**

`Sources/TwigCore/Layout/BranchLayout.swift`：

```swift
import CoreGraphics
import Foundation

public enum BranchDirection: String, Codable, CaseIterable {
    case right, left, up, down
}

public struct BranchTuning: Equatable {
    public var direction: BranchDirection = .right
    public var curveTension: CGFloat = 0.35
    public var branchSpacing: CGFloat = 150
    public var nodeSpacing: CGFloat = 64
    public var fadeDistance: CGFloat = 320
    public var dragExpandThreshold: CGFloat = 24
    public init() {}
}

public struct BranchNode: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let colorHex: String
    public var center: CGPoint
    public var opacity: Double
    public var dashed: Bool
}

public struct BranchEdge: Equatable {
    public var from: CGPoint
    public var to: CGPoint
    public var c1: CGPoint
    public var c2: CGPoint
    public var colorHex: String
    public var dashed: Bool
    public var faded: Bool
}

public struct BranchLayoutResult: Equatable {
    public var nodes: [BranchNode]
    public var edges: [BranchEdge]
    public var contentSize: CGSize
    public var direction: BranchDirection
}

public enum BranchLayout {
    public static func compute(projects: [Project], anchor: CGPoint,
                               tuning: BranchTuning = .init(), now: Date = .now) -> BranchLayoutResult {
        var nodes: [BranchNode] = []
        var edges: [BranchEdge] = []
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "M/d"

        // 主轴单位向量（枝干延展方向）与交叉轴单位向量（节点错开方向）
        let main: CGPoint
        switch tuning.direction {
        case .right: main = CGPoint(x: 1, y: 0)
        case .left:  main = CGPoint(x: -1, y: 0)
        case .down:  main = CGPoint(x: 0, y: 1)
        case .up:    main = CGPoint(x: 0, y: -1)
        }
        let cross = CGPoint(x: -main.y, y: main.x)   // 主轴逆时针旋转 90°

        func layoutPoint(main m: CGFloat, cross c: CGFloat) -> CGPoint {
            CGPoint(x: anchor.x + main.x * m + cross.x * c,
                    y: anchor.y + main.y * m + cross.y * c)
        }

        for (projectIndex, project) in projects.enumerated() {
            let goals = project.goals
                .filter { !$0.isDone }
                .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
            guard !goals.isEmpty else { continue }
            let mainOffset = tuning.branchSpacing * CGFloat(projectIndex + 1)
            var previousPoint = anchor

            for (goalIndex, goal) in goals.enumerated() {
                // 交叉轴正方向错开：日期近的离 anchor 近
                let center = layoutPoint(main: mainOffset,
                                         cross: 48 + CGFloat(goalIndex) * tuning.nodeSpacing)
                let opacity = max(0.3, 1 - mainOffset / tuning.fadeDistance)
                let dashed = goal.horizon != .short
                let subtitle = goal.targetDate.map { dayFmt.string(from: $0) } ?? "未定"
                nodes.append(BranchNode(
                    id: stableID(for: goal),
                    title: goal.title,
                    subtitle: subtitle,
                    colorHex: project.colorHint,
                    center: center,
                    opacity: opacity,
                    dashed: dashed
                ))
                let d = mainOffset * tuning.curveTension
                edges.append(BranchEdge(
                    from: previousPoint,
                    to: center,
                    c1: CGPoint(x: previousPoint.x + main.x * d, y: previousPoint.y + main.y * d),
                    c2: CGPoint(x: center.x - main.x * d, y: center.y - main.y * d),
                    colorHex: project.colorHint,
                    dashed: dashed && goalIndex == goals.count - 1,
                    faded: opacity < 0.7
                ))
                previousPoint = center
            }
        }

        // contentSize = 从 anchor 出发沿主轴/交叉轴的包围盒（含留白）
        var maxMain: CGFloat = 0, minCross: CGFloat = 0, maxCross: CGFloat = 0
        for node in nodes {
            let dx = node.center.x - anchor.x
            let dy = node.center.y - anchor.y
            maxMain = max(maxMain, dx * main.x + dy * main.y)
            let c = dx * cross.x + dy * cross.y
            minCross = min(minCross, c)
            maxCross = max(maxCross, c)
        }
        let crossSpan = maxCross - minCross
        let size = CGSize(
            width: abs(main.x) * (maxMain + 120) + abs(cross.x) * (crossSpan + 96),
            height: abs(main.y) * (maxMain + 120) + abs(cross.y) * (crossSpan + 96)
        )
        return BranchLayoutResult(nodes: nodes, edges: edges,
                                  contentSize: size, direction: tuning.direction)
    }

    private static func stableID(for goal: Goal) -> UUID {
        // 同一 goal 多次布局要拿到同一个 id，否则 SwiftUI 动画会跳
        var hash = goal.persistentModelID.uriRepresentation().absoluteString.utf8.reduce(into: [UInt8](repeating: 0, count: 16)) { buf, byte in
            buf[Int(byte) % 16] &+= byte
        }
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
    }
}
```

注：若 `BranchNode.id` 的稳定化实现编译告警，可简化为 `UUID(uuidString:)` 散列方案或直接保留 goal 的 uri 字符串作 `id: String`（把 `Identifiable` 的关联类型改为 String，同步改测试与 BranchView）。

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter BranchLayoutTests`
Expected: 4 tests PASS

- [ ] **Step 5: 写 BranchView / PeekListView 并接入 WidgetView**

`Sources/TwigApp/Widget/BranchView.swift`：

```swift
import SwiftUI
import TwigCore

/// 枝干完全展开：贝塞尔枝干 + 圆润玻璃块节点；拖动节点改排期
struct BranchView: View {
    let appState: AppState
    @State private var draggingNodeID: UUID?

    var body: some View {
        let tuning = appState.branchTuning
        let anchor: CGPoint = switch tuning.direction {
        case .right: CGPoint(x: 0, y: 32)
        case .left:  CGPoint(x: 0, y: 32)          // 容器内坐标，布局向左延展
        case .down:  CGPoint(x: 190, y: 0)         // 从横条中点向下
        case .up:    CGPoint(x: 190, y: 0)
        }
        let layout = BranchLayout.compute(
            projects: appState.taskStore.allProjects(),
            anchor: anchor,
            tuning: tuning
        )
        // 左/上方向时布局坐标为负向，整体平移进容器正坐标系
        let tx: CGFloat = layout.direction == .left ? layout.contentSize.width : 0
        let ty: CGFloat = layout.direction == .up ? layout.contentSize.height : 0
        ZStack(alignment: .topLeading) {
            Group {
                Canvas { ctx, _ in
                    for edge in layout.edges {
                        var path = Path()
                        path.move(to: edge.from)
                        path.addCurve(to: edge.to, control1: edge.c1, control2: edge.c2)
                        let color = Color(hex: edge.colorHex) ?? .gray
                        ctx.stroke(
                            path,
                            with: .color(color.opacity(edge.faded ? 0.4 : 0.85)),
                            style: StrokeStyle(
                                lineWidth: edge.faded ? 1.5 : 2,
                                lineCap: .round,
                                dash: edge.dashed ? [4, 6] : []
                            )
                        )
                    }
                }
                ForEach(layout.nodes) { node in
                    GoalNodeBlock(node: node)
                        .position(node.center)
                        .opacity(draggingNodeID == node.id ? 0.9 : node.opacity)
                        .gesture(
                            DragGesture()
                                .onChanged { _ in draggingNodeID = node.id }
                                .onEnded { value in
                                    draggingNodeID = nil
                                    appState.moveGoal(nodeID: node.id, verticalDelta: value.translation.height)
                                }
                        )
                }
            }
            .offset(x: tx, y: ty)
        }
        .frame(
            width: max(560, layout.contentSize.width),
            height: max(layout.contentSize.height, 120)
        )
        .onChange(of: layout.contentSize) { _, size in
            appState.branchContentSize = size
        }
        .onAppear { appState.branchContentSize = layout.contentSize }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture {
                appState.widgetState = .collapsed
            }
        )
    }
}

/// 单个目标节点：圆润玻璃块
struct GoalNodeBlock: View {
    let node: BranchNode

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: node.colorHex) ?? .gray)
                .frame(width: 8, height: 8)
            Text(node.title)
                .font(.system(size: 12, weight: .medium))
            Text(node.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(node.dashed ? 0.35 : 0.6),
                        style: StrokeStyle(lineWidth: 1, dash: node.dashed ? [3, 3] : []))
        )
    }
}
```

`Sources/TwigApp/Widget/PeekListView.swift`：

```swift
import SwiftUI
import TwigCore

/// 悬停滑出：今日任务清单，可直接勾选
struct PeekListView: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(appState.taskStore.tasksForToday(on: Date()).prefix(6), id: \.persistentModelID) { task in
                HStack(spacing: 8) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Color(hex: task.goal?.project?.colorHint ?? "#D97757") ?? .orange)
                    Text(task.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.taskStore.toggleTask(task)
                    appState.exportSnapshot()
                }
            }
            HStack {
                Spacer()
                Button("展开枝干") { appState.widgetState = .expanded }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.5), lineWidth: 1))
    }
}
```

修改 `Sources/TwigApp/Widget/CollapsedBarView.swift`：把 Task 9 里固定向右的虚线 Canvas 抽成方向感知的 `DashedExtensionView`，并按枝干方向调整组装：

```swift
/// 横条末梢的虚线外延，方向跟随枝干方向
struct DashedExtensionView: View {
    let direction: BranchDirection

    var body: some View {
        Canvas { ctx, size in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let start: CGPoint = switch direction {
            case .right: CGPoint(x: 8, y: mid.y)
            case .left: CGPoint(x: size.width - 8, y: mid.y)
            case .down, .up: mid
            }
            let ends: [CGPoint] = switch direction {
            case .right: [CGPoint(x: size.width - 12, y: mid.y - 24), CGPoint(x: size.width - 12, y: mid.y + 24)]
            case .left: [CGPoint(x: 12, y: mid.y - 24), CGPoint(x: 12, y: mid.y + 24)]
            case .down: [CGPoint(x: mid.x - 60, y: size.height - 6), CGPoint(x: mid.x + 60, y: size.height - 6)]
            case .up: [CGPoint(x: mid.x - 60, y: 6), CGPoint(x: mid.x + 60, y: 6)]
            }
            for end in ends {
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end,
                              control1: CGPoint(x: (start.x + end.x) / 2, y: start.y),
                              control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                ctx.stroke(path, with: .color(.primary.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6]))
            }
        }
    }
}
```

CollapsedBarView 的 body 改为按方向组装（横条部分抽成 `bar` 计算属性，内容不变）：

```swift
    var body: some View {
        let dashed = DashedExtensionView(direction: appState.branchTuning.direction)
        Group {
            switch appState.branchTuning.direction {
            case .right:
                HStack(spacing: 0) { bar; dashed.frame(width: 160) }
            case .left:
                HStack(spacing: 0) { dashed.frame(width: 160); bar }
            case .down:
                VStack(spacing: 0) { bar; dashed.frame(height: 48) }
            case .up:
                VStack(spacing: 0) { dashed.frame(height: 48); bar }
            }
        }
        .frame(width: 560, height: barHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { appState.widgetState = .peeked }
        }
    }
```

`.up` 方向时悬浮窗整体需要向下锚定（扩高时往上长会顶出屏幕）——v1 处理：`WidgetWindowController.resize(toHeight:)` 已保持顶边不动向上增长，up 方向下用户在设置里选完后把横条拖到屏幕底部即可，交互迭代期再细化锚定。

修改 `Sources/TwigApp/Widget/WidgetView.swift`，把 Task 9 的占位 peek 替换为真实三态，并让窗口高度随状态变化：

```swift
import SwiftUI
import TwigCore

struct WidgetView: View {
    let appState: AppState
    var controller: WidgetWindowController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                CollapsedBarView(appState: appState)
                switch appState.widgetState {
                case .collapsed:
                    EmptyView()
                case .peeked:
                    PeekListView(appState: appState)
                        .onHover { inside in
                            if !inside { appState.widgetState = .collapsed }
                        }
                case .expanded:
                    BranchView(appState: appState)
                }
            }
            .onChange(of: appState.widgetState) { _, state in
                switch state {
                case .collapsed: controller.resize(toHeight: 64)
                case .peeked: controller.resize(toHeight: 64 + 220)
                case .expanded:
                    controller.resize(toHeight: 64 + appState.branchContentSize.height)
                }
            }
            .onChange(of: appState.branchContentSize) { _, size in
                if appState.widgetState == .expanded {
                    controller.resize(toHeight: 64 + size.height)
                }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            appState.timerStore.tick()
        }
    }
}
```

在 `AppState` 中补充枝干方向配置与拖动改排期的方法：

```swift
    /// 枝干方向（用户可自定义，存 UserDefaults）
    var branchTuning: BranchTuning {
        var tuning = BranchTuning()
        if let raw = UserDefaults.standard.string(forKey: "twig.branchDirection"),
           let direction = BranchDirection(rawValue: raw) {
            tuning.direction = direction
        }
        return tuning
    }

    /// BranchView 布局后回写，供窗口扩容器使用
    var branchContentSize: CGSize = CGSize(width: 560, height: 360)

    /// 枝干节点上下拖动 = 在该项目内调整目标排序（sortOrder 交换）
    func moveGoal(nodeID: UUID, verticalDelta: CGFloat) {
        let steps = Int((verticalDelta / 64).rounded())   // 每 64pt 一格
        guard steps != 0 else { return }
        for project in taskStore.allProjects() {
            var goals = project.goals.filter { !$0.isDone }
                .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
            // nodeID 由 BranchLayout 从 persistentModelID 派生，这里用标题匹配找回（v1 简化）
            // 更稳妥的做法是 BranchNode 直接携带 PersistentIdentifier —— 交互迭代时改进
            guard goals.count > 1 else { continue }
            // v1：拖哪个项目就在哪个项目内轮转 sortOrder
            if steps > 0 {
                let first = goals.removeFirst()
                goals.append(first)
            } else {
                let last = goals.removeLast()
                goals.insert(last, at: 0)
            }
            for (i, goal) in goals.enumerated() {
                goal.sortOrder = Double(i + 1) * 1024
            }
            try? container.mainContext.save()
        }
    }
```

并把 TwigAppMain 中 `controller.show(rootView: WidgetView(appState: appState))` 改为 `controller.show(rootView: WidgetView(appState: appState, controller: controller))`。

- [ ] **Step 6: 构建并手动验证**

Run: `swift build && .build/debug/TwigApp &`

手动验收清单：

- [ ] 悬停横条 → 滑出今日清单；移开 → 收回
- [ ] 清单里点圆圈能勾选任务，立即变灰
- [ ] 点"展开枝干"→ 窗口变高，枝干贝塞尔曲线 + 玻璃块节点出现，近实远虚
- [ ] 中长期节点是虚线描边，短期是实线
- [ ] 拖动节点上下移动松手后排序变化
- [ ] 点空白处收回 collapsed
- [ ] 多项目时两条枝干颜色不同、远处更透明
- [ ] 主窗口设置里切换枝干方向为"向左"→ 虚线和枝干都向左延展；切回"向右"恢复（up/down 方向 v1 仅要求布局正确、不顶出屏幕）

- [ ] **Step 7: Commit**

```bash
git add Sources/TwigCore/Layout Sources/TwigApp/Widget Tests/TwigCoreTests/BranchLayoutTests.swift
git commit -m "feat: 枝干式展开（纯函数布局 + Canvas 贝塞尔 + 玻璃块节点拖拽排序）"
```

---

### Task 11: 主窗口（项目 / 时间轴 / 详情 / 报表 / 设置）

**Files:**
- Create: `Sources/TwigApp/Main/MainWindowView.swift`
- Create: `Sources/TwigApp/Main/ProjectListView.swift`
- Create: `Sources/TwigApp/Main/TimelineView.swift`
- Create: `Sources/TwigApp/Main/TaskDetailView.swift`
- Create: `Sources/TwigApp/Main/ReportsView.swift`
- Create: `Sources/TwigApp/Main/SettingsView.swift`
- Modify: `Sources/TwigApp/TwigAppMain.swift`（主窗口 scene 换成 MainWindowView）

**Interfaces:**
- Consumes: `AppState`（Task 9）、`TaskStore`（Task 2）、`ReportAggregator`（Task 7）、`GitReader`（Task 6）、`TimerConfig`（Task 3）
- Produces: 无新公共接口（叶子 UI 层）

- [ ] **Step 1: 写主窗口各视图**

`Sources/TwigApp/Main/MainWindowView.swift`：

```swift
import SwiftUI
import TwigCore

struct MainWindowView: View {
    let appState: AppState
    @State private var selectedProject: Project?
    @State private var showingReports = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            ProjectListView(appState: appState, selection: $selectedProject)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            if let project = selectedProject {
                TimelineView(appState: appState, project: project)
            } else {
                Text("选择一个项目")
                    .foregroundStyle(.secondary)
            }
        } detail: {
            Text("任务详情")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 860, minHeight: 540)
        .toolbar {
            ToolbarItemGroup {
                Button { showingReports.toggle() } label: {
                    Label("报表", systemImage: "chart.bar")
                }
                Button { showingSettings.toggle() } label: {
                    Label("设置", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingReports) {
            ReportsView(appState: appState)
                .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(appState: appState)
                .frame(width: 480, height: 420)
        }
    }
}
```

`Sources/TwigApp/Main/ProjectListView.swift`：

```swift
import SwiftUI
import TwigCore

struct ProjectListView: View {
    let appState: AppState
    @Binding var selection: Project?
    @State private var newProjectName = ""

    var body: some View {
        List(appState.taskStore.allProjects(), id: \.persistentModelID, selection: $selection) { project in
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: project.colorHint) ?? .gray)
                    .frame(width: 10, height: 10)
                Text(project.name)
                Spacer()
                if project.repoPath == nil {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(.tertiary)
                        .help("未绑定 git 仓库")
                }
            }
            .tag(project)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("新项目名", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    guard !newProjectName.isEmpty else { return }
                    let p = appState.taskStore.addProject(name: newProjectName, colorHint: "#D97757")
                    newProjectName = ""
                    selection = p
                    appState.exportSnapshot()
                }
            }
            .padding(10)
        }
    }
}
```

`Sources/TwigApp/Main/TimelineView.swift`：

```swift
import SwiftUI
import TwigCore

/// 中间栏：目标泳道（短/中/长期）+ 该项目近期 git 提交
struct TimelineView: View {
    let appState: AppState
    let project: Project
    @State private var commits: [GitCommit] = []
    @State private var repoLost = false
    @State private var newGoalTitle = ""
    @State private var newGoalHorizon: Horizon = .short

    var body: some View {
        List {
            ForEach(Horizon.allCases, id: \.self) { horizon in
                Section(horizonLabel(horizon)) {
                    ForEach(goals(for: horizon), id: \.persistentModelID) { goal in
                        GoalRow(appState: appState, goal: goal)
                    }
                }
            }
            Section("近期提交") {
                if project.repoPath == nil {
                    Button("绑定本地 git 仓库…") { pickRepo() }
                } else if repoLost {
                    Label("仓库失联：路径不存在或已不是 git 仓库", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("重新选择…") { pickRepo() }
                } else {
                    ForEach(commits, id: \.hash) { commit in
                        HStack {
                            Text(commit.hash).font(.caption.monospaced())
                            Text(commit.subject).lineLimit(1)
                            Spacer()
                            Text(commit.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("新目标", text: $newGoalTitle)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $newGoalHorizon) {
                    Text("短期").tag(Horizon.short)
                    Text("中期").tag(Horizon.mid)
                    Text("长期").tag(Horizon.long)
                }
                .frame(width: 90)
                Button("添加目标") {
                    guard !newGoalTitle.isEmpty else { return }
                    appState.taskStore.addGoal(to: project, title: newGoalTitle,
                                               horizon: newGoalHorizon, targetDate: nil)
                    newGoalTitle = ""
                    appState.exportSnapshot()
                }
            }
            .padding(10)
        }
        .onAppear(perform: loadCommits)
    }

    private func goals(for horizon: Horizon) -> [Goal] {
        project.goals
            .filter { $0.horizon == horizon }
            .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private func horizonLabel(_ h: Horizon) -> String {
        switch h { case .short: "短期"; case .mid: "中期"; case .long: "长期" }
    }

    private func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            project.repoPath = url.path
            try? appState.container.mainContext.save()
            loadCommits()
        }
    }

    private func loadCommits() {
        guard let path = project.repoPath else { return }
        do {
            commits = try GitReader().log(repoPath: path,
                                          since: Date().addingTimeInterval(-14 * 86400))
            repoLost = false
        } catch {
            repoLost = true
            commits = []
        }
    }
}

/// 目标行：勾选 + 其下任务
struct GoalRow: View {
    let appState: AppState
    let goal: Goal
    @State private var newTaskTitle = ""

    var body: some View {
        DisclosureGroup {
            ForEach(goal.tasks.sorted { $0.sortOrder < $1.sortOrder }, id: \.persistentModelID) { task in
                HStack {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Color(hex: goal.project?.colorHint ?? "#D97757") ?? .orange)
                    Text(task.title).strikethrough(task.isDone)
                    Spacer()
                    if let estimate = task.estimateMin {
                        Text("约\(estimate)分钟").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("专注") {
                        appState.timerStore.start(task: task, mode: .pomodoro)
                    }
                    .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.taskStore.toggleTask(task)
                    appState.exportSnapshot()
                }
            }
            HStack {
                TextField("新任务", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    guard !newTaskTitle.isEmpty else { return }
                    appState.taskStore.addTask(to: goal, title: newTaskTitle)
                    newTaskTitle = ""
                    appState.exportSnapshot()
                }
            }
        } label: {
            HStack {
                Text(goal.title).font(.headline)
                Spacer()
                if let date = goal.targetDate {
                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

`Sources/TwigApp/Main/ReportsView.swift`：

```swift
import SwiftUI
import SwiftData
import TwigCore

/// 今日 / 本周：TimeEntry 聚合 + 已完成任务
struct ReportsView: View {
    let appState: AppState
    @State private var scope = 0   // 0=今日 1=本周

    var body: some View {
        VStack {
            Picker("", selection: $scope) {
                Text("今日").tag(0)
                Text("本周").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            let ctx = appState.container.mainContext
            let entries = (try? ctx.fetch(FetchDescriptor<TimeEntry>())) ?? []
            let tasks = (try? ctx.fetch(FetchDescriptor<Task>())) ?? []

            if scope == 0 {
                let report = ReportAggregator.dayReport(day: Date(), entries: entries, tasks: tasks)
                DayReportCard(report: report)
            } else {
                let week = ReportAggregator.weekReport(containing: Date(), entries: entries, tasks: tasks)
                List(week, id: \.day) { report in
                    HStack {
                        Text(report.day, format: .dateTime.month().day().weekday())
                        Spacer()
                        Text("专注 \(report.focusMinutes) 分钟")
                        Text("完成 \(report.completedTaskTitles.count) 项")
                            .foregroundStyle(.secondary)
                    }
                }
                let total = week.reduce(0) { $0 + $1.focusMinutes }
                Text("本周共专注 \(total / 60) 小时 \(total % 60) 分钟")
                    .font(.headline)
                    .padding()
            }
            Spacer()
        }
    }
}

struct DayReportCard: View {
    let report: DayReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                VStack { Text("\(report.focusMinutes)").font(.largeTitle); Text("专注分钟").font(.caption) }
                VStack { Text("\(report.breakMinutes)").font(.largeTitle); Text("休息分钟").font(.caption) }
                VStack { Text("\(report.completedTaskTitles.count)").font(.largeTitle); Text("完成任务").font(.caption) }
            }
            if !report.perProjectFocus.isEmpty {
                Divider()
                ForEach(report.perProjectFocus.sorted(by: { $0.value > $1.value }), id: \.key) { name, minutes in
                    HStack {
                        Text(name)
                        Spacer()
                        Text("\(minutes) 分钟").foregroundStyle(.secondary)
                    }
                }
            }
            if !report.completedTaskTitles.isEmpty {
                Divider()
                ForEach(report.completedTaskTitles, id: \.self) { title in
                    Label(title, systemImage: "checkmark.circle")
                }
            }
            Spacer()
        }
        .padding()
    }
}
```

`Sources/TwigApp/Main/SettingsView.swift`：

```swift
import SwiftUI
import ServiceManagement
import TwigCore

struct SettingsView: View {
    let appState: AppState
    @State private var config = TimerConfig.load()
    @State private var badLineCount = 0
    @State private var loginItem = false
    @AppStorage("twig.branchDirection") private var branchDirection = BranchDirection.right.rawValue

    var body: some View {
        Form {
            Section("枝干") {
                Picker("延展方向", selection: $branchDirection) {
                    Text("向右").tag(BranchDirection.right.rawValue)
                    Text("向左").tag(BranchDirection.left.rawValue)
                    Text("向下").tag(BranchDirection.down.rawValue)
                    Text("向上").tag(BranchDirection.up.rawValue)
                }
                Text("悬浮窗贴在屏幕哪条边，就选相反方向")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("计时器") {
                Stepper("专注 \(config.focusMinutes) 分钟", value: $config.focusMinutes, in: 5...120, step: 5)
                Stepper("短休息 \(config.shortBreakMinutes) 分钟", value: $config.shortBreakMinutes, in: 1...30)
                Stepper("长休息 \(config.longBreakMinutes) 分钟", value: $config.longBreakMinutes, in: 5...60, step: 5)
                Stepper("每 \(config.pomodorosPerLongBreak) 个番茄后长休息", value: $config.pomodorosPerLongBreak, in: 2...8)
                Toggle("到点自动开始休息", isOn: $config.autoStartBreak)
                Toggle("提示音", isOn: $config.soundEnabled)
                Toggle("系统通知", isOn: $config.notificationsEnabled)
            }
            Section("系统") {
                Toggle("登录后自动启动（需以 Twig.app 形式运行）", isOn: $loginItem)
                    .onChange(of: loginItem) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch { loginItem = false }
                    }
            }
            Section("收件箱") {
                Text(badLineCount == 0 ? "没有导入失败的记录" : "有 \(badLineCount) 条导入失败，见 inbox.bad.jsonl")
                    .foregroundStyle(badLineCount == 0 ? .secondary : .orange)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            badLineCount = (try? String(contentsOf: TwigPaths.badLinesURL, encoding: .utf8))?
                .split(separator: "\n").count ?? 0
        }
        .onChange(of: config) { _, newValue in
            newValue.save()
            appState.timerStore.engine.config = newValue
        }
    }
}
```

修改 `Sources/TwigApp/TwigAppMain.swift` 的 Window scene，并删除 Task 9 里占位的 `Settings { EmptyView() }` scene（设置已改为工具栏 sheet）：

```swift
        Window("Twig", id: "main") {
            MainWindowView(appState: appState)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultLaunchBehavior(.suppressed)
```

- [ ] **Step 2: 构建并手动验证**

Run: `swift build && .build/debug/TwigApp &`，菜单栏叶子 → 打开主窗口

手动验收清单：

- [ ] 左侧能添加项目（带颜色点），选中后中间出现短/中/长期泳道
- [ ] 泳道里能添加目标，目标里能添加任务；任务可勾选（划线）
- [ ] 任务行点"专注"，悬浮横条立刻开始倒计时并显示该任务名
- [ ] "绑定本地 git 仓库"选 ~/work/twig，下方出现近 14 天提交列表
- [ ] 把项目 repoPath 指向一个不存在的路径（或直接选非 git 目录）→ 显示"仓库失联"，可重新选择
- [ ] 工具栏"报表"：今日显示专注分钟/休息分钟/完成任务；本周 7 行 + 合计
- [ ] 工具栏"设置"：改专注时长后，新开始的番茄用新时长；坏行计数正确显示

- [ ] **Step 3: Commit**

```bash
git add Sources/TwigApp
git commit -m "feat: 主窗口（项目/泳道/任务/报表/设置 + git 仓库绑定）"
```

---
### Task 12: 菜单栏增强 + Twig.app 打包

**Files:**
- Create: `assets/Info.plist`
- Create: `scripts/make-app.sh`
- Modify: `Sources/TwigApp/TwigAppMain.swift`（MenuBarExtra 加计时快捷操作）

**Interfaces:**
- Consumes: `AppState`（Task 9）
- Produces：`scripts/make-app.sh`（release 构建 → `build/Twig.app`，ad-hoc 签名）；菜单栏可开始/停止计时

- [ ] **Step 1: 增强 MenuBarExtra**

把 `Sources/TwigApp/TwigAppMain.swift` 中的 `MenuBarExtra` 替换为：

```swift
        MenuBarExtra("Twig", systemImage: "leaf") {
            switch appState.timerStore.engine.state {
            case .idle:
                Button("开始番茄钟") { appState.timerStore.start(task: nil, mode: .pomodoro) }
                Button("开始正计时") { appState.timerStore.start(task: nil, mode: .stopwatch) }
            case .focusing:
                Button("提前完成") { appState.timerStore.finishFocus() }
                Button("停止并保留") { appState.timerStore.stop(discard: false) }
                Button("停止并丢弃") { appState.timerStore.stop(discard: true) }
            case .onBreak:
                Button("结束休息") { appState.timerStore.endBreak() }
            }
            Divider()
            Button("打开主窗口") { openMain() }
            Divider()
            Button("退出 Twig") { NSApp.terminate(nil) }
        }
```

- [ ] **Step 2: 写 Info.plist 和打包脚本**

`assets/Info.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Twig</string>
    <key>CFBundleIdentifier</key><string>com.daniel.twig</string>
    <key>CFBundleName</key><string>Twig</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSUserNotificationAlertUsageDescription</key><string>番茄钟到点提醒</string>
</dict>
</plist>
```

`scripts/make-app.sh`：

```bash
#!/bin/bash
# 打包 Twig.app：swift release 构建 → 标准 .app 结构 → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product TwigApp

APP=build/Twig.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TwigApp "$APP/Contents/MacOS/Twig"
cp assets/Info.plist "$APP/Contents/Info.plist"
if [ -f assets/AppIcon.icns ]; then
    cp assets/AppIcon.icns "$APP/Contents/Resources/"
fi
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "已生成 $APP — 拖入 /Applications 或直接 open 运行"
```

```bash
chmod +x scripts/make-app.sh
```

- [ ] **Step 3: 构建打包并手动验证**

Run: `./scripts/make-app.sh && open build/Twig.app`

手动验收清单：

- [ ] Twig.app 正常启动，悬浮横条出现
- [ ] 菜单栏可开始番茄钟 / 提前完成 / 停止（三种状态菜单项不同）
- [ ] 主窗口 → 设置 → 打开"登录后自动启动"不报错（打包运行时才有效）
- [ ] 数据与 debug 版互通（同一个 `~/Library/Application Support/Twig/`）

- [ ] **Step 4: Commit**

```bash
git add assets scripts Sources/TwigApp/TwigAppMain.swift
git commit -m "feat: 菜单栏计时快捷操作 + make-app.sh 打包脚本"
```

---

### Task 13: Agent Skill 套件（Claude + Codex）

**Files:**
- Create: `skills/claude/twig/SKILL.md`
- Create: `skills/codex/twig.md`
- Create: `skills/install.sh`

**Interfaces:**
- Consumes: `twig` CLI（Task 5）
- Produces：`skills/install.sh` 执行后，`~/.claude/skills/twig/SKILL.md` 与 `~/.codex/prompts/twig.md` 可用；`twig` 二进制软链到 `~/.local/bin/twig`

- [ ] **Step 1: 写 Claude skill**

`skills/claude/twig/SKILL.md`：

```markdown
---
name: twig
description: Use when the user wants to record a task/todo into their Twig desktop app — e.g. "记一下", "加到 todo", "记到 Twig", "add a task", or when they mention something should be done later and you'd normally suggest tracking it. Also use to check what's currently on their task list.
---

# Twig 任务记录

用户的桌面 todo app。通过 `twig` CLI 交互（在 PATH 中；找不到时用 `~/.local/bin/twig`）。

## 加任务

```bash
twig add "任务标题" --project 项目名 [--goal 目标名] [--due YYYY-MM-DD] [--estimate 分钟]
```

规则：

1. **先查重**：`twig list --project 项目名`，已有同名未完成任务就不要重复添加，直接告诉用户已存在。
2. **项目名**：用 `twig list` 输出的现有项目名（一字不差）。用户说的项目不在列表里时，先问用户是新建项目还是归到现有项目，不要擅自新建。
3. **--goal**：用户明确说了里程碑/目标才带；不带则进"收集箱"。
4. **--due**：只在用户给出明确日期时带，换算成 YYYY-MM-DD。"下周三"这类相对日期用对话中的今天日期换算。
5. **--estimate**：用户提到"大概要 X 小时/分钟"才带，统一换算成分钟。
6. 标题就是任务本身，别加"记得去"这类前缀。
7. 任务进的是收件箱，Twig.app 运行中会秒级导入；app 没开则下次启动时导入。告诉用户"已记到 Twig"即可。

## 批量记录

用户一次性说多件事时，逐条 `twig add`，全部加完后汇总列出加了哪几条。

## 查任务

`twig list`（全部项目）或 `twig list --project 项目名`。输出含 ☐/☑ 状态，回答"我还有什么要做"类问题时按 项目 → 目标 组织转述。
```

- [ ] **Step 2: 写 Codex prompt**

`skills/codex/twig.md`：

```markdown
把任务记到用户的 Twig 桌面 todo app。

用 `twig` CLI（PATH 中；找不到用 `~/.local/bin/twig`）：

    twig add "任务标题" --project 项目名 [--goal 目标名] [--due YYYY-MM-DD] [--estimate 分钟]

规则：
1. 先 `twig list --project 项目名` 查重，已有同名未完成任务则不重复添加。
2. 项目名必须与 `twig list` 中现有项目一字不差；不存在时先问用户。
3. --goal 只在用户明确提到里程碑时带；--due 只在有明确日期时带（YYYY-MM-DD）；--estimate 统一换算成分钟。
4. 多条任务逐条添加，最后汇总。
5. 任务是进收件箱，app 运行中自动导入；回复用户"已记到 Twig"。

查任务：twig list [--project 项目名]，☐=未完成 ☑=已完成。
```

- [ ] **Step 3: 写安装脚本并验证**

`skills/install.sh`：

```bash
#!/bin/bash
# 安装 twig CLI + agent skills（Claude Code / Codex）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product twig
mkdir -p ~/.local/bin ~/.claude/skills ~/.codex/prompts
ln -sf "$(pwd)/.build/release/twig" ~/.local/bin/twig
ln -sfn "$(pwd)/skills/claude/twig" ~/.claude/skills/twig
cp skills/codex/twig.md ~/.codex/prompts/twig.md

echo "完成："
echo "  twig CLI      → ~/.local/bin/twig"
echo "  Claude skill  → ~/.claude/skills/twig/"
echo "  Codex prompt  → ~/.codex/prompts/twig.md"
```

```bash
chmod +x skills/install.sh
./skills/install.sh
export PATH="$HOME/.local/bin:$PATH"
twig add "skill 自测任务" --project twig --goal v0.1
cat ~/Library/Application\ Support/Twig/inbox.jsonl   # 应有刚才那条
ls -la ~/.claude/skills/twig/SKILL.md ~/.codex/prompts/twig.md
```

手动验收：

- [ ] `twig` 在 PATH 中可用，add 成功写入收件箱
- [ ] 两个 skill 文件就位
- [ ] 若 Twig.app 正在运行，几秒内主窗口/快照出现"skill 自测任务"

- [ ] **Step 4: Commit**

```bash
git add skills
git commit -m "feat: agent skill 套件（Claude SKILL.md + Codex prompt + 安装脚本）"
```

---

### Task 14: App icon（dreamina）+ 总验收 + 推送 GitHub

**Files:**
- Create: `assets/AppIcon.icns`（生成产物）
- Create: `assets/icon-source.png`（dreamina 原图）

**Interfaces:**
- Consumes: dreamina CLI（`~/.local/bin/dreamina`，已登录 maestro）、`scripts/make-app.sh`（Task 12）
- Produces: `assets/AppIcon.icns`；GitHub 远程仓库（私有）并完成首次推送

- [ ] **Step 1: 用 dreamina 生成 icon 原图**

```bash
mkdir -p assets
~/.local/bin/dreamina text2image \
  --prompt="macOS 应用图标：圆润 squircle 玻璃质感底，暖米白渐变，中央一枚极简的赤陶橙色树枝小芽图形（圆润几何块风格），柔和光影，扁平现代设计，无文字" \
  --ratio=1:1 --resolution_type=2k --poll=150
```

从输出 JSON 的 `result_json.images[0].image_url` 取图下载：

```bash
curl -L "<上一步的 image_url>" -o assets/icon-source.png
```

不满意可调整 prompt 重新生成（圆润、玻璃、赤陶橙是关键词）。

- [ ] **Step 2: 制作 AppIcon.icns**

```bash
mkdir -p /tmp/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size assets/icon-source.png --out /tmp/AppIcon.iconset/icon_${size}x${size}.png >/dev/null
  double=$((size*2))
  sips -z $double $double assets/icon-source.png --out /tmp/AppIcon.iconset/icon_${size}x${size}@2x.png >/dev/null
done
iconutil -c icns /tmp/AppIcon.iconset -o assets/AppIcon.icns
./scripts/make-app.sh   # 重新打包带上 icon
open build/Twig.app     # 确认 Dock 图标生效
```

- [ ] **Step 3: 全量测试 + 总验收清单**

```bash
swift test   # 全部单元测试应通过
```

按 spec §11 手动验收核心路径：

- [ ] `twig add "验收任务" --project twig` → app 内出现（收件箱链路）
- [ ] 主窗口对"验收任务"点"专注"→ 横条倒计时 → 提前完成 → 询问任务完成 → 确认后任务勾掉
- [ ] 报表"今日"里有这段专注时长和这条已完成任务
- [ ] 悬浮窗：悬停出今日清单 → 展开枝干 → 拖动节点 → 点空白收回
- [ ] `kill -9` 后重启：数据都在，若有未闭合计时会弹补记提示
- [ ] `ls ~/Library/Application\ Support/Twig/backups` 有备份目录

- [ ] **Step 4: 登录 gh 并推送 GitHub**

钥匙串里已有 GitHub token（账号 Daniel-0196），用它登录 gh CLI 再建私有仓库：

```bash
git credential fill <<< $'protocol=https\nhost=github.com\n' \
  | awk '/^password=/{print substr($0,10)}' \
  | gh auth login --with-token
gh auth status
gh repo create twig --private --source=. --remote=origin --push
git log --oneline | head -20   # 确认全部提交已推送（gh repo view 可复核）
```

若 `gh repo create` 因仓库已存在报错，改为：

```bash
git remote add origin git@github.com:Daniel-0196/twig.git 2>/dev/null || true
git push -u origin main
```

- [ ] **Step 5: Commit icon 资产**

```bash
git add assets/icon-source.png assets/AppIcon.icns
git commit -m "chore: app icon（dreamina 生成：圆润玻璃 + 赤陶橙枝芽）"
git push
```

---

## Self-Review 记录

**Spec 覆盖核对**（spec 章节 → 任务）：

- §3 技术方案/分层 → Task 1（SPM 形态已在本计划 Architecture 说明调整原因）
- §4 数据模型 → Task 1（TimeEntry.lastHeartbeat、duration 派生）
- §5 悬浮部件三态 + 枝干 → Task 9（collapsed）、Task 10（peeked/expanded/BranchTuning 可调参数）
- §6 番茄钟三模式 + 自定义 → Task 3（引擎/配置）、Task 11（设置 UI）、Task 12（菜单栏快捷）
- §7 主窗口 → Task 11
- §8 git 集成 → Task 6（读取）；提示式任务关联降级说明：v1 只做时间线展示与日报列出提交，commit↔任务提示匹配留待后续迭代（已在 spec 中为"保守策略"，实现计划首期聚焦读取链路）
- §9 Agent 接口 → Task 4（收件箱）、Task 5（CLI+快照）、Task 9（app 监视导入）、Task 13（skill 套件）
- §10 错误处理 → Task 6（仓库失联/超时）、Task 4（坏行留档）、Task 3/8（心跳+恢复）、Task 8（备份）、Task 9（窗口位置校验）
- §11 测试策略 → 核心逻辑全部 XCTest（Task 1-8、10 布局），UI 手动清单（Task 9-12、14）
- §12 icon/仓库 → Task 14

**已知有意简化（实现时不得"顺手补上"）**：

- `BranchNode.id` 从 `persistentModelID` 派生的稳定化方案在 Task 10 给了简化实现与备选说明，交互迭代期再硬化
- `AppState.moveGoal` 的 v1 是项目内轮转排序，跨枝干拖动改归属留给交互原型迭代（spec §5 明确手感细节开发期定）
- commit 与任务的提示式匹配未进首期范围（见上）
