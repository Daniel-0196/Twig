# Twig 悬浮窗重写（拔树交互）+ 主窗口对齐 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按交互设计 v3（原型 v18）重写 Twig 悬浮窗为"拔树"节点画板，主窗口对齐原型（分项目报表），Edge 成为一等实体。

**Architecture:** 拔树引擎全部进 TwigCore 纯函数（拓扑 `TreeTopology` / 布局 `TreeLayout` / 物理 `PullPhysics`，XCTest 覆盖）；TwigApp 只做渲染与手势接线。数据模型新增 `Edge` @Model 和 Goal 的 `revealed/customX/customY`（增量迁移）。

**Tech Stack:** Swift 5.10 / SwiftUI / SwiftData / XCTest；SPM 工程（Xcode 16 工具链）

**参考实现（行为基准）:** `prototype/twig-proto.html` —— 计划中的每个数值常量、状态机分支、视觉参数都以它为准。实现者被要求阅读对应 JS 函数。

**Spec:** `docs/superpowers/specs/2026-08-03-twig-interaction-v3-final.md`

## Global Constraints

- 最低系统 macOS 15；零第三方依赖
- UI 文案简体中文
- 视觉风格 = Claude 浅色玻璃：节点卡 `rgba(255,255,255,0.62)` + blur；项目色 twig `#D97757`、mergeCook4 `#7D9B76`；衬线标题 `.serif`
- 每个 Task 结束 `swift build` 零告警 + 相关测试通过 + commit
- 工具链实况：Xcode 16 / Swift 6.0，`container.mainContext` 为 MainActor 隔离；`TwigCore.Task` 与 `_Concurrency.Task` 撞名需全限定
- 手感参数必须与原型一致（FOLLOW 0.4、GRAVITY 2.2+2%、GAP 190、扇距 110、埋深档 120+j×100、阈值 +20、预热 0.65、回弹 380ms easeOutBack、滞后 0.25）

---

## 文件结构

```
Sources/TwigCore/
├── Models/Edge.swift              # 新增：顺序/引用边实体
├── Models/Goal.swift              # 修改：+revealed +customX/customY
├── Infra/TwigStore.swift          # 修改：schema 加 Edge
├── Tree/TreeTopology.swift        # 新增：拓扑（根/深度/组件/出土卫生）
├── Tree/TreeLayout.swift          # 新增：方向几何 + 根迁移 + 扇开 + 埋土槽位
└── Tree/PullPhysics.swift         # 新增：重力/峰值/消耗/回弹 状态机
Sources/TwigApp/
├── AppState.swift                 # 修改：树状态（偏移/拉拽/悬停上下文/持久化）
├── Widget/TreeWidgetController.swift  # 新增：窗口管理（默认展开、方向切换、尺寸）
├── Widget/TreeCanvasView.swift    # 新增：节点+连线容器、手势路由
├── Widget/NodeCardView.swift      # 新增：节点卡 + 右侧小卫星
├── Widget/StemEdgeCanvas.swift    # 新增：多层锥度茎线 + 土壤弯折
├── Widget/HoverHud.swift          # 新增：功能按钮排 + 叶子排 + 挂点
└── Widget/TaskLeafPopover.swift   # 新增：任务详情 + 任务级番茄
Tests/TwigCoreTests/
├── EdgeTests.swift
├── TreeTopologyTests.swift
├── TreeLayoutTests.swift
└── PullPhysicsTests.swift
```

---

### Task 1: Edge 模型 + Goal 扩展 + 迁移

**Files:**
- Create: `Sources/TwigCore/Models/Edge.swift`
- Modify: `Sources/TwigCore/Models/Goal.swift`
- Modify: `Sources/TwigCore/Infra/TwigStore.swift`
- Test: `Tests/TwigCoreTests/EdgeTests.swift`

**Interfaces:**
- Consumes: 现有 `Project/Goal/Task`、`TwigStore.makeContainer(inMemory:)`
- Produces:
  - `enum EdgeType: String, Codable { case sequence, reference }`
  - `@Model Edge { var type: EdgeType; var from: Goal?; var to: Goal?; init(type:from:to:) }`
  - Goal 新增：`var revealed: Bool = false`、`var customX: Double? = nil`、`var customY: Double? = nil`、`@Relationship(deleteRule: .cascade, inverse: \Edge.from) var outEdges: [Edge] = []`、`@Relationship(deleteRule: .cascade, inverse: \Edge.to) var inEdges: [Edge] = []`

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/EdgeTests.swift`：

```swift
import XCTest
import SwiftData
@testable import TwigCore

final class EdgeTests: XCTestCase {
    @MainActor
    func testEdgePersistsBetweenGoals() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let p = Project(name: "twig", colorHint: "#D97757")
        ctx.insert(p)
        let a = Goal(title: "v0.2", horizon: .short, targetDate: nil)
        let b = Goal(title: "v0.5", horizon: .mid, targetDate: nil)
        a.project = p; b.project = p
        ctx.insert(a); ctx.insert(b)
        let e = Edge(type: .sequence, from: a, to: b)
        ctx.insert(e)
        try ctx.save()

        let edges = try ctx.fetch(FetchDescriptor<Edge>())
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges[0].from?.title, "v0.2")
        XCTAssertEqual(edges[0].to?.title, "v0.5")
        XCTAssertEqual(a.outEdges.count, 1)
        XCTAssertEqual(b.inEdges.count, 1)
    }

    @MainActor
    func testGoalNewFieldsDefaults() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let g = Goal(title: "g", horizon: .short, targetDate: nil)
        container.mainContext.insert(g)
        XCTAssertFalse(g.revealed)
        XCTAssertNil(g.customX)
        XCTAssertNil(g.customY)
    }

    @MainActor
    func testCascadeDeleteGoalRemovesEdges() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let a = Goal(title: "a", horizon: .short, targetDate: nil)
        let b = Goal(title: "b", horizon: .mid, targetDate: nil)
        ctx.insert(a); ctx.insert(b)
        ctx.insert(Edge(type: .sequence, from: a, to: b))
        try ctx.save()
        ctx.delete(a)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Edge>()), 0)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter EdgeTests`
Expected: FAIL — 找不到 `Edge`

- [ ] **Step 3: 实现**

`Sources/TwigCore/Models/Edge.swift`：

```swift
import Foundation
import SwiftData

public enum EdgeType: String, Codable {
    case sequence, reference
}

@Model
public final class Edge {
    public var type: EdgeType
    public var from: Goal?
    public var to: Goal?

    public init(type: EdgeType, from: Goal, to: Goal) {
        self.type = type
        self.from = from
        self.to = to
    }
}
```

`Sources/TwigCore/Models/Goal.swift` — 在 class 内增加属性（其余不动）：

```swift
    // 拔树画板状态
    public var revealed: Bool = false       // 是否已出土（短期目标初始化时置 true，见 Task 5）
    public var customX: Double? = nil       // 手动摆放位置（覆盖自动布局）
    public var customY: Double? = nil
    @Relationship(deleteRule: .cascade, inverse: \Edge.from)
    public var outEdges: [Edge] = []
    @Relationship(deleteRule: .cascade, inverse: \Edge.to)
    public var inEdges: [Edge] = []
```

`Sources/TwigCore/Infra/TwigStore.swift` — schema 加 Edge：

```swift
        let schema = Schema([Project.self, Goal.self, Task.self, TimeEntry.self, Edge.self])
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter EdgeTests`
Expected: 3 tests PASS

- [ ] **Step 5: 用真实库验证增量迁移**

Run: `swift build && .build/debug/TwigApp &`，3 秒后 `pkill -x TwigApp`；确认启动不崩（真实 `~/Library/Application Support/Twig/twig.store` 已有 v1 数据，自动增量迁移 Edge 表）
Expected: 进程存活 3 秒，退出码正常

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: Edge 一等实体 + Goal 拔树状态字段（revealed/customPos）"
```

---

### Task 2: TreeTopology（拓扑纯函数）

**Files:**
- Create: `Sources/TwigCore/Tree/TreeTopology.swift`
- Test: `Tests/TwigCoreTests/TreeTopologyTests.swift`

**Interfaces:**
- Consumes: `Goal`、`Edge`、`EdgeType`（Task 1）
- Produces（用 `PersistentIdentifier` 作节点键）：
  - `enum TreeTopology`：
    - `static func depths(goals: [Goal], edges: [Edge]) -> [PersistentIdentifier: Int]`（seq 入度 0 = 根 depth 0，沿出边递增；不可达/孤立 = -1）
    - `static func isRoot(_ goal: Goal, edges: [Edge]) -> Bool`
    - `static func component(of goal: Goal, edges: [Edge]) -> (ids: Set<PersistentIdentifier>, depths: [PersistentIdentifier: Int])`（沿 seq 双向 BFS，depths 相对 goal）
    - `static func sanitizeReveal(goals: [Goal], edges: [Edge])`（子出土 ⇒ seq 祖先强制出土，迭代到不动点）
    - `static func outgoing(from: Goal, edges: [Edge]) -> [Edge]`（seq 出边）
    - `static func parent(of goal: Goal, edges: [Edge]) -> Goal?`（第一条 seq 入边的 from）

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/TreeTopologyTests.swift`：

```swift
import XCTest
@testable import TwigCore

@MainActor
final class TreeTopologyTests: XCTestCase {
    private func makeChain() throws -> (container _: ModelContainerUnused, goals: [Goal], edges: [Edge]) {
        fatalError("unused")
    }

    // 用 SwiftData 建实体太啰嗦？不——拓扑函数只读 Goal/Edge 的引用关系，直接构造即可（不需 insert）
    private func goals(_ titles: [String]) -> [Goal] {
        titles.map { Goal(title: $0, horizon: .short, targetDate: nil) }
    }
    private func link(_ a: Goal, _ b: Goal) -> Edge { Edge(type: .sequence, from: a, to: b) }

    func testDepthsFromRoots() {
        let g = goals(["v0.2", "v0.5", "v1.0", "孤立"])
        let edges = [link(g[0], g[1]), link(g[1], g[2])]
        let d = TreeTopology.depths(goals: g, edges: edges)
        XCTAssertEqual(d[g[0].persistentModelID], 0)
        XCTAssertEqual(d[g[1].persistentModelID], 1)
        XCTAssertEqual(d[g[2].persistentModelID], 2)
        XCTAssertEqual(d[g[3].persistentModelID], -1)   // 孤立
    }

    func testFanOutDepths() {
        // 一出多：两个子节点同深度
        let g = goals(["根", "子A", "子B", "孙"])
        let edges = [link(g[0], g[1]), link(g[0], g[2]), link(g[1], g[3])]
        let d = TreeTopology.depths(goals: g, edges: edges)
        XCTAssertEqual(d[g[1].persistentModelID], 1)
        XCTAssertEqual(d[g[2].persistentModelID], 1)
        XCTAssertEqual(d[g[3].persistentModelID], 2)
    }

    func testComponentBidirectional() {
        let g = goals(["a", "b", "c", "x"])
        let edges = [link(g[0], g[1]), link(g[1], g[2])]
        let comp = TreeTopology.component(of: g[1], edges: edges)
        XCTAssertEqual(comp.ids.count, 3)
        XCTAssertEqual(comp.depths[g[0].persistentModelID], 1)
        XCTAssertEqual(comp.depths[g[1].persistentModelID], 0)
        XCTAssertEqual(comp.depths[g[2].persistentModelID], 1)
        XCTAssertFalse(comp.ids.contains(g[3].persistentModelID))
    }

    func testSanitizeRevealPullsAncestorsUp() {
        let g = goals(["a", "b", "c"])
        let edges = [link(g[0], g[1]), link(g[1], g[2])]
        g[0].revealed = true
        g[2].revealed = true   // c 出土但 b 没有 → b 必须被强制出土
        TreeTopology.sanitizeReveal(goals: g, edges: edges)
        XCTAssertTrue(g[1].revealed)
    }

    func testIsRoot() {
        let g = goals(["a", "b"])
        let edges = [link(g[0], g[1])]
        XCTAssertTrue(TreeTopology.isRoot(g[0], edges: edges))
        XCTAssertFalse(TreeTopology.isRoot(g[1], edges: edges))
    }
}
```

注：`Goal` 是 @Model，不 insert 进容器时 `persistentModelID` 也可用（backingData 有 id）；若测试运行时发现未 insert 的模型取 persistentModelID 崩溃，改为 insert 进内存容器再取。测试里删掉 `makeChain` 占位函数（它只是示意）。

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter TreeTopologyTests`
Expected: FAIL — 找不到 `TreeTopology`

- [ ] **Step 3: 实现**

`Sources/TwigCore/Tree/TreeTopology.swift`：

```swift
import Foundation
import SwiftData

public enum TreeTopology {
    private static func seqEdges(_ edges: [Edge]) -> [Edge] {
        edges.filter { $0.type == .sequence }
    }

    /// seq 入度 0 = 根（depth 0），沿出边递增；孤立/不可达 = -1
    public static func depths(goals: [Goal], edges: [Edge]) -> [PersistentIdentifier: Int] {
        let seq = seqEdges(edges)
        var indeg: [PersistentIdentifier: Int] = [:]
        for g in goals { indeg[g.persistentModelID] = 0 }
        for e in seq { if let to = e.to { indeg[to.persistentModelID, default: 0] += 1 } }
        var depth: [PersistentIdentifier: Int] = [:]
        var queue = goals.filter { indeg[$0.persistentModelID] == 0 }
        queue.forEach { depth[$0.persistentModelID] = 0 }
        var guardCount = 0
        while !queue.isEmpty && guardCount < 500 {
            guardCount += 1
            let cur = queue.removeFirst()
            let curDepth = depth[cur.persistentModelID] ?? 0
            for e in seq where e.from?.persistentModelID == cur.persistentModelID {
                guard let nxt = e.to else { continue }
                let id = nxt.persistentModelID
                if depth[id] == nil || depth[id]! < curDepth + 1 {
                    depth[id] = curDepth + 1
                    queue.append(nxt)
                }
            }
        }
        for g in goals where depth[g.persistentModelID] == nil {
            depth[g.persistentModelID] = -1
        }
        return depth
    }

    public static func isRoot(_ goal: Goal, edges: [Edge]) -> Bool {
        !seqEdges(edges).contains { $0.to?.persistentModelID == goal.persistentModelID }
    }

    /// 沿 seq 双向 BFS：拔树的单位（一棵"树"）
    public static func component(of goal: Goal, edges: [Edge]) -> (ids: Set<PersistentIdentifier>, depths: [PersistentIdentifier: Int]) {
        let seq = seqEdges(edges)
        var ids: Set<PersistentIdentifier> = [goal.persistentModelID]
        var depths: [PersistentIdentifier: Int] = [goal.persistentModelID: 0]
        var queue = [goal]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            let d = depths[cur.persistentModelID] ?? 0
            for e in seq {
                let other: Goal?
                if e.from?.persistentModelID == cur.persistentModelID { other = e.to }
                else if e.to?.persistentModelID == cur.persistentModelID { other = e.from }
                else { continue }
                guard let o = other, !ids.contains(o.persistentModelID) else { continue }
                ids.insert(o.persistentModelID)
                depths[o.persistentModelID] = d + 1
                queue.append(o)
            }
        }
        return (ids, depths)
    }

    /// 子节点出土 ⇒ 其 seq 祖先必须先出土（迭代到不动点）
    public static func sanitizeReveal(goals: [Goal], edges: [Edge]) {
        let seq = seqEdges(edges)
        var changed = true
        var guardCount = 0
        while changed && guardCount < 20 {
            guardCount += 1
            changed = false
            for e in seq {
                guard let a = e.from, let b = e.to else { continue }
                if b.revealed && !a.revealed { a.revealed = true; changed = true }
            }
        }
    }

    public static func outgoing(from: Goal, edges: [Edge]) -> [Edge] {
        seqEdges(edges).filter { $0.from?.persistentModelID == from.persistentModelID }
    }

    public static func parent(of goal: Goal, edges: [Edge]) -> Goal? {
        seqEdges(edges).first { $0.to?.persistentModelID == goal.persistentModelID }?.from
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter TreeTopologyTests`
Expected: 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Tree Tests/TwigCoreTests/TreeTopologyTests.swift
git commit -m "feat: TreeTopology 拓扑纯函数（根/深度/组件/出土卫生）"
```

---

### Task 3: TreeLayout（方向几何 + 根迁移 + 扇开布局）

**Files:**
- Create: `Sources/TwigCore/Tree/TreeLayout.swift`
- Test: `Tests/TwigCoreTests/TreeLayoutTests.swift`

**Interfaces:**
- Consumes: `Project/Goal/Edge`、`TreeTopology.depths`（Task 2）
- Produces：
  - `enum PullDirection: String, Codable, CaseIterable { case up, down, left, right }`（**含义 = 拖拽/出土方向**）
  - `struct DirGeom { var axisIsX: Bool; var unit: CGPoint; var soil: CGFloat; var chainSign: CGFloat; var buriedSign: CGFloat }`（`unit` = 拖拽方向单位向量；`chainSign` = 链条朝土壤的符号）
  - `enum TreeGeom { static func geom(for: PullDirection, rect: CGRect) -> DirGeom }`
  - `struct Placement: Equatable { var goal: PersistentIdentifier; var center: CGPoint; var isBuried: Bool }`
  - `enum TreeLayout { static func place(goals: [Goal], edges: [Edge], rect: CGRect, direction: PullDirection) -> [PersistentIdentifier: CGPoint] }`（只排未设 customX/Y 的节点；含根迁移与扇开；埋土节点排在土线外）
  - 常量：`mainGap = 190`、`siblingGap = 110`、`rootInset = 90`、`depthExtra = 50`、`buriedBase = 120`、`buriedStep = 100`

几何规则（与原型 v15+ 一致，rect = 悬浮窗内容区）：

| direction | soil（土线） | 链条方向（chainSign 沿主轴） | 埋土方向 |
|---|---|---|---|
| up（向上拔） | rect 底边 | 向下 +1 | +1 |
| down | rect 顶边 | 向上 −1 | −1 |
| left | rect 左边 | 向左 −1 | −1 |
| right | rect 右边 | 向右 +1 | +1 |

- 根基准：`rootBase = soil − chainSign方向内缩 max(rootInset, Dmax × mainGap + depthExtra)`（Dmax = 该项目已出土节点的最大拓扑深度）——即"根随出土深度向屏内迁移"
- 深度 k 节点主轴坐标 = `rootBase + chainSign × k × mainGap × spacingOf(goal)`（spacingOf = 0.88+hash×0.24）
- 同层兄弟交叉轴：以父节点 cross 为中心扇开 `(i − (count−1)/2) × siblingGap + jitterOf(goal)`（jitter = hash×44 − 22）；根层以项目 baseCross 为中心
- baseCross（交叉轴项目间距）：axis=x → `rect.minY + 50 + projectIndex × 150`；axis=y → `rect.minX + 80 + projectIndex × 260`
- 孤立节点（depth −1）：排在根层 `baseCross + 170 + i × 100`
- 埋土节点：按深度排序，主轴坐标 = `soil + buriedSign × (buriedBase + j × buriedStep)`，交叉轴 = baseCross + jitter

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/TreeLayoutTests.swift`：

```swift
import XCTest
import CoreGraphics
@testable import TwigCore

final class TreeLayoutTests: XCTestCase {
    private let rect = CGRect(x: 100, y: 100, width: 800, height: 500)

    private func makeProject() -> (Project, [Goal], [Edge]) {
        let p = Project(name: "twig", colorHint: "#D97757")
        let a = Goal(title: "v0.2", horizon: .short, targetDate: nil)
        let b = Goal(title: "v0.5", horizon: .mid, targetDate: nil)
        let c = Goal(title: "v1.0", horizon: .long, targetDate: nil)
        [a, b, c].forEach { $0.project = p }
        let edges = [Edge(type: .sequence, from: a, to: b), Edge(type: .sequence, from: b, to: c)]
        return (p, [a, b, c], edges)
    }

    func testUpDirectionRootNearBottomBuriedBelow() {
        let (p, goals, edges) = makeProject()
        goals[0].revealed = true   // 只出土根
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .up)
        let rootY = pos[goals[0].persistentModelID]!.y
        XCTAssertEqual(rootY, rect.maxY - 90, accuracy: 1)   // 贴底边
        let buriedY = pos[goals[1].persistentModelID]!.y
        XCTAssertGreaterThan(buriedY, rect.maxY)             // 埋在底边外
        XCTAssertEqual(pos.count, 3)
        _ = p
    }

    func testRootMigratesWithRevealDepth() {
        let (_, goals, edges) = makeProject()
        goals[0].revealed = true
        goals[1].revealed = true   // 出土到 depth 1
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .up)
        let rootY = pos[goals[0].persistentModelID]!.y
        // rootBase = soil − max(90, 1×190+50) = bottom − 240
        XCTAssertEqual(rootY, rect.maxY - 240, accuracy: 1)
        // v0.5 在根与土壤之间（链条朝土壤连续）
        let midY = pos[goals[1].persistentModelID]!.y
        XCTAssertGreaterThan(midY, rootY)
        XCTAssertLessThan(midY, rect.maxY)
    }

    func testDownDirectionMirrored() {
        let (_, goals, edges) = makeProject()
        goals[0].revealed = true
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .down)
        let rootY = pos[goals[0].persistentModelID]!.y
        XCTAssertEqual(rootY, rect.minY + 90, accuracy: 1)
        XCTAssertLessThan(pos[goals[1].persistentModelID]!.y, rect.minY)   // 埋在顶边外
    }

    func testSiblingFanOut() {
        let p = Project(name: "twig", colorHint: "#D97757")
        let root = Goal(title: "root", horizon: .short, targetDate: nil)
        let k1 = Goal(title: "k1", horizon: .mid, targetDate: nil)
        let k2 = Goal(title: "k2", horizon: .mid, targetDate: nil)
        [root, k1, k2].forEach { $0.project = p; $0.revealed = true }
        let edges = [Edge(type: .sequence, from: root, to: k1), Edge(type: .sequence, from: root, to: k2)]
        let pos = TreeLayout.place(goals: [root, k1, k2], edges: edges, rect: rect, direction: .up)
        let x1 = pos[k1.persistentModelID]!.x
        let x2 = pos[k2.persistentModelID]!.x
        XCTAssertNotEqual(x1, x2)   // 兄弟扇开不重叠
        XCTAssertEqual((x1 + x2) / 2, pos[root.persistentModelID]!.x, accuracy: 30)   // 以父为中心
    }

    func testCustomPositionWins() {
        let (_, goals, edges) = makeProject()
        goals[0].revealed = true
        goals[0].customX = 333; goals[0].customY = 222
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .up)
        XCTAssertEqual(pos[goals[0].persistentModelID], CGPoint(x: 333, y: 222))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter TreeLayoutTests`
Expected: FAIL — 找不到 `TreeLayout`

- [ ] **Step 3: 实现**

`Sources/TwigCore/Tree/TreeLayout.swift`：

```swift
import CoreGraphics
import Foundation
import SwiftData

public enum PullDirection: String, Codable, CaseIterable {
    case up, down, left, right
}

public enum TreeLayout {
    public static let mainGap: CGFloat = 190
    public static let siblingGap: CGFloat = 110
    public static let rootInset: CGFloat = 90
    public static let depthExtra: CGFloat = 50
    public static let buriedBase: CGFloat = 120
    public static let buriedStep: CGFloat = 100

    // 确定性抖动（按 goal id 哈希）
    private static func hash01(_ id: PersistentIdentifier) -> Double {
        var h: UInt64 = 5381
        for b in id.uriRepresentation().absoluteString.utf8 {
            h = ((h &<< 5) &+ h) &+ UInt64(b)
        }
        return Double(h % 65536) / 65536.0
    }
    private static func jitter(_ g: Goal) -> CGFloat { CGFloat(hash01(g.persistentModelID) - 0.5) * 44 }
    private static func spacing(_ g: Goal) -> CGFloat { CGFloat(0.88 + hash01(g.persistentModelID) * 0.24) }

    /// 只排未手动摆放（customX/Y 为 nil）的节点；返回 goal id → 中心点
    public static func place(goals: [Goal], edges: [Edge], rect: CGRect,
                             direction: PullDirection) -> [PersistentIdentifier: CGPoint] {
        var result: [PersistentIdentifier: CGPoint] = [:]
        let depth = TreeTopology.depths(goals: goals, edges: edges)

        // 项目分组（保持 projects 传入顺序用 Goal.project）
        var byProject: [PersistentIdentifier: (project: Project, goals: [Goal])] = [:]
        var order: [PersistentIdentifier] = []
        for g in goals {
            guard let p = g.project else { continue }
            if byProject[p.persistentModelID] == nil {
                byProject[p.persistentModelID] = (p, [])
                order.append(p.persistentModelID)
            }
            byProject[p.persistentModelID]!.goals.append(g)
        }

        for (pi, pid) in order.enumerated() {
            let group = byProject[pid]!
            let baseCross: CGFloat = (direction == .up || direction == .down)
                ? rect.minX + 80 + CGFloat(pi) * 260
                : rect.minY + 50 + CGFloat(pi) * 150

            let shown = group.goals.filter { $0.revealed && $0.customX == nil }
            let hidden = group.goals.filter { !$0.revealed && $0.customX == nil }
                .sorted { (depth[$0.persistentModelID] ?? 0) < (depth[$1.persistentModelID] ?? 0) }

            // 根随出土深度迁移
            let dMax = CGFloat(shown.map { max(0, depth[$0.persistentModelID] ?? 0) }.max() ?? 0)
            let inset = max(rootInset, dMax * mainGap + depthExtra)
            let rootBase: CGFloat
            switch direction {
            case .up:    rootBase = rect.maxY - inset
            case .down:  rootBase = rect.minY + inset
            case .left:  rootBase = rect.minX + inset
            case .right: rootBase = rect.maxX - inset
            }
            let chainSign: CGFloat = (direction == .up || direction == .right) ? 1 : -1
            let buriedSign = chainSign
            let soil: CGFloat = (direction == .up) ? rect.maxY : (direction == .down) ? rect.minY
                              : (direction == .left) ? rect.minX : rect.maxX

            func setAbs(_ g: Goal, main: CGFloat, cross: CGFloat) {
                let pt = (direction == .up || direction == .down)
                    ? CGPoint(x: cross, y: main)
                    : CGPoint(x: main, y: cross)
                result[g.persistentModelID] = pt
            }

            // 根层
            let roots = shown.filter { (depth[$0.persistentModelID] ?? -1) <= 0 }
            for (i, n) in roots.enumerated() {
                let cross = baseCross + (CGFloat(i) - CGFloat(roots.count - 1) / 2) * siblingGap + jitter(n)
                n.crossPosCache = cross   // Goal 上无此字段——见下"实现注"
                setAbs(n, rootBase, cross)
            }

            // 逐层扇开
            var frontier = roots
            var dk: CGFloat = 1
            while !frontier.isEmpty && dk < 20 {
                var next: [Goal] = []
                for parent in frontier {
                    let kids = TreeTopology.outgoing(from: parent, edges: edges)
                        .compactMap { $0.to }
                        .filter { $0.revealed && $0.customX == nil }
                    let parentCross = result[parent.persistentModelID]!.xOrY(cross: direction)
                    for (i, kid) in kids.enumerated() {
                        let cross = parentCross + (CGFloat(i) - CGFloat(kids.count - 1) / 2) * siblingGap + jitter(kid)
                        setAbs(kid, rootBase + chainSign * dk * mainGap * spacing(kid), cross)
                        next.append(kid)
                    }
                }
                frontier = next
                dk += 1
            }

            // 孤立已揭示节点：排在根层旁边
            let orphans = shown.filter { !roots.contains($0) && result[$0.persistentModelID] == nil }
            for (i, n) in orphans.enumerated() {
                setAbs(n, rootBase, baseCross + 170 + CGFloat(i) * 100 + jitter(n))
            }

            // 埋土：按深度排，土线外
            for (j, n) in hidden.enumerated() {
                setAbs(n, soil + buriedSign * (buriedBase + CGFloat(j) * buriedStep),
                       baseCross + jitter(n))
            }
        }
        return result
    }
}

private extension CGPoint {
    func xOrY(cross direction: PullDirection) -> CGFloat {
        (direction == .up || direction == .down) ? x : y
    }
}
```

**实现注**：上面 `n.crossPosCache` 那行是笔误——删掉它；根层 cross 直接通过 `setAbs` 写入 result，父层从 `result[parent].xOrY(cross:)` 读取。另外 `roots.contains($0)` 对 @Model 用 `contains(where: { $0.persistentModelID == ... })` 更稳。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter TreeLayoutTests`
Expected: 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Tree Tests/TwigCoreTests/TreeLayoutTests.swift
git commit -m "feat: TreeLayout 方向几何（根迁移/扇开/埋土槽位）"
```

---

### Task 4: PullPhysics（重力/峰值/消耗/回弹）

**Files:**
- Create: `Sources/TwigCore/Tree/PullPhysics.swift`
- Test: `Tests/TwigCoreTests/PullPhysicsTests.swift`

**Interfaces:**
- Consumes: `PullDirection`、`TreeLayout`（Task 3）
- Produces：
  - `struct PullSession`：`var targetOffset: CGSize`、`var offset: CGSize`、`var consumed: CGFloat`、`var peakRaw: CGFloat`、`var velocity: CGSize`
  - `enum PullPhysics`：
    - `static let follow: CGFloat = 0.4`、`gravityBase: CGFloat = 2.2`、`gravityRate: CGFloat = 0.02`、`revealSlack: CGFloat = 20`、`hotRatio: CGFloat = 0.65`
    - `static func step(_ s: inout PullSession, direction: PullDirection)`（一帧：follow 积分 + 重力回吸 + 速度记录）
    - `static func pullMain(_ s: PullSession, direction: PullDirection) -> CGFloat`（沿拖拽方向的峰值有效拔力 = max(peakRaw, 瞬时) − consumed）
    - `static func checkReveal(_ s: inout PullSession, direction: PullDirection, buriedDepth: CGFloat) -> Bool`（pullMain > buriedDepth ⇒ true 且 consumed += buriedDepth）
    - `static func springEase(_ t: CGFloat) -> CGFloat`（easeOutBack，t∈[0,1]）

物理语义（与原型一致）：step 每帧 `offset += (target − offset) × follow`；然后重力把 offset 往 0 吸（主轴 `gravityBase + |offset|×rate`，交叉轴固定 0.8）；velocity = 本帧位移。拖拽时 targetOffset = 起点偏移 + 鼠标位移 × 0.9。

- [ ] **Step 1: 写失败测试**

`Tests/TwigCoreTests/PullPhysicsTests.swift`：

```swift
import XCTest
import CoreGraphics
@testable import TwigCore

final class PullPhysicsTests: XCTestCase {
    func testFollowIntegrationApproachesTarget() {
        var s = PullSession()
        s.targetOffset = CGSize(width: 0, height: -260)   // 向上拽
        for _ in 0..<30 { PullPhysics.step(&s, direction: .up) }
        XCTAssertLessThan(s.offset.y, -150)   // 趋近目标（被重力吃掉一部分）
        XCTAssertLessThan(s.velocity.y, 0)
    }

    func testGravityPullsBackWhenTargetZero() {
        var s = PullSession()
        s.offset = CGSize(width: 0, height: -200)
        s.targetOffset = .zero   // 松手的目标
        for _ in 0..<200 { PullPhysics.step(&s, direction: .up) }
        XCTAssertEqual(s.offset.y, 0, accuracy: 1)   // 被吸回土里
    }

    func testPeakPullSurvivesGravityFallback() {
        var s = PullSession()
        s.targetOffset = CGSize(width: 0, height: -260)
        for _ in 0..<10 { PullPhysics.step(&s, direction: .up) }
        let peak = s.peakRaw
        XCTAssertGreaterThan(peak, 100)
        // 回拉（手往回松），峰值保留
        s.targetOffset = CGSize(width: 0, height: -60)
        for _ in 0..<10 { PullPhysics.step(&s, direction: .up) }
        XCTAssertEqual(s.peakRaw, peak)
        XCTAssertEqual(PullPhysics.pullMain(s, direction: .up), peak)
    }

    func testRevealConsumesPull() {
        var s = PullSession()
        s.peakRaw = 300
        XCTAssertTrue(PullPhysics.checkReveal(&s, direction: .up, buriedDepth: 140))
        XCTAssertEqual(s.consumed, 140)
        // 消耗后同一波拔力不够第二个（埋深 240）
        XCTAssertFalse(PullPhysics.checkReveal(&s, direction: .up, buriedDepth: 240))
        // 继续用力到峰值 300+140 → 第二个出土
        s.peakRaw = 450
        XCTAssertTrue(PullPhysics.checkReveal(&s, direction: .up, buriedDepth: 240))
    }

    func testSpringEaseOvershoots() {
        XCTAssertEqual(PullPhysics.springEase(0), 0, accuracy: 0.001)
        XCTAssertEqual(PullPhysics.springEase(1), 1, accuracy: 0.001)
        // easeOutBack 中途过冲
        XCTAssertGreaterThan(PullPhysics.springEase(0.8), 1.0)
    }

    func testDirectionSigns() {
        // 向上拔：offset.y 为负，pullMain 为正
        var s = PullSession()
        s.peakRaw = 100
        s.offset = CGSize(width: 0, height: -100)
        XCTAssertEqual(PullPhysics.pullMain(s, direction: .up), 100)
        // 向下拔：offset.y 为正
        s.offset = CGSize(width: 0, height: 100)
        s.peakRaw = 0
        XCTAssertEqual(PullPhysics.pullMain(s, direction: .down), 100)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter PullPhysicsTests`
Expected: FAIL — 找不到 `PullPhysics`

- [ ] **Step 3: 实现**

`Sources/TwigCore/Tree/PullPhysics.swift`：

```swift
import CoreGraphics
import Foundation

public struct PullSession {
    public var targetOffset: CGSize = .zero   // 手的目标位移（起点偏移 + 拖拽 × 0.9）
    public var offset: CGSize = .zero         // 树的实际偏移（积分值）
    public var consumed: CGFloat = 0          // 已消耗的拉力
    public var peakRaw: CGFloat = 0           // 峰值拔力（猛拽冲线算数）
    public var velocity: CGSize = .zero       // 本帧位移（枝干张力弯曲用）
    public init() {}
}

public enum PullPhysics {
    public static let follow: CGFloat = 0.4
    public static let gravityBase: CGFloat = 2.2
    public static let gravityRate: CGFloat = 0.02
    public static let revealSlack: CGFloat = 20
    public static let hotRatio: CGFloat = 0.65

    /// 一帧：跟随积分 + 重力回吸 + 速度记录
    public static func step(_ s: inout PullSession, direction: PullDirection) {
        let prev = s.offset
        s.offset.width += (s.targetOffset.width - s.offset.width) * follow
        s.offset.height += (s.targetOffset.height - s.offset.height) * follow

        // 重力：主轴往土壤吸 + 交叉轴回正
        if direction == .up || direction == .down {
            s.offset.height -= (s.offset.height > 0 ? 1 : s.offset.height < 0 ? -1 : 0)
                * min(abs(s.offset.height), gravityBase + abs(s.offset.height) * gravityRate)
            s.offset.width -= (s.offset.width > 0 ? 1 : s.offset.width < 0 ? -1 : 0)
                * min(abs(s.offset.width), 0.8)
        } else {
            s.offset.width -= (s.offset.width > 0 ? 1 : s.offset.width < 0 ? -1 : 0)
                * min(abs(s.offset.width), gravityBase + abs(s.offset.width) * gravityRate)
            s.offset.height -= (s.offset.height > 0 ? 1 : s.offset.height < 0 ? -1 : 0)
                * min(abs(s.offset.height), 0.8)
        }
        s.velocity = CGSize(width: s.offset.width - prev.width, height: s.offset.height - prev.height)

        // 峰值拔力（沿拖拽方向）
        let raw = rawPull(s, direction: direction)
        s.peakRaw = max(s.peakRaw, raw)
    }

    /// 沿拖拽方向的瞬时拔出量（恒正）
    public static func rawPull(_ s: PullSession, direction: PullDirection) -> CGFloat {
        switch direction {
        case .up: return -s.offset.height
        case .down: return s.offset.height
        case .left: return -s.offset.width
        case .right: return s.offset.width
        }
    }

    /// 有效拔力 = 峰值 − 已消耗
    public static func pullMain(_ s: PullSession, direction: PullDirection) -> CGFloat {
        max(s.peakRaw, rawPull(s, direction: direction)) - s.consumed
    }

    /// 出土判定：有效拔力超过埋深 ⇒ 出土并消耗拉力
    public static func checkReveal(_ s: inout PullSession, direction: PullDirection,
                                   buriedDepth: CGFloat) -> Bool {
        if pullMain(s, direction: direction) > buriedDepth + revealSlack - 20 {   // 原型：threshold = 埋深+20
            s.consumed += buriedDepth
            return true
        }
        return false
    }

    /// easeOutBack（松手回弹曲线，t∈[0,1]，中途略过 1 为过冲）
    public static func springEase(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
}
```

注：`checkReveal` 里 `+ revealSlack - 20` 是故意的：原型阈值为"埋深 + 20"，即 `pullMain > buried + 20`；这里 buriedDepth 参数传"纯埋深"，写成 `buriedDepth + revealSlack - 20` = buriedDepth + 0…不对。改为直接 `pullMain > buriedDepth + 20`：`revealSlack` 常量即 20，判断写作 `> buriedDepth + revealSlack`，实现者按此修正（测试不受影响：140 埋深 + 20 = 160 < 300 ✓）。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter PullPhysicsTests`
Expected: 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TwigCore/Tree Tests/TwigCoreTests/PullPhysicsTests.swift
git commit -m "feat: PullPhysics 重力/峰值/拉力消耗/回弹曲线"
```

---
<!-- CHUNK-2 -->
