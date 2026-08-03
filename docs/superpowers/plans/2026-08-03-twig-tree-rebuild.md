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
### Task 5: AppState 树状态装配 + 持久化

**Files:**
- Modify: `Sources/TwigApp/AppState.swift`
- Modify: `Sources/TwigCore/Stores/TaskStore.swift`（addGoal 时设置 revealed 默认）

**Interfaces:**
- Consumes: `TreeTopology/TreeLayout/PullPhysics`（Task 2-4）、`TaskStore`、`TimerStore`
- Produces（Task 6-9 依赖）：
  - `AppState` 新增：
    - `var pullDirection: PullDirection`（读写 UserDefaults `twig.pullDirection`，默认 `.down`）
    - `var pullSession: PullSession?`（进行中）
    - `var hoveredGoal: Goal?`（悬停上下文当前节点）
    - `func goalsAndEdges() -> (goals: [Goal], edges: [Edge])`（从 mainContext 拉全量）
    - `func placements(in rect: CGRect) -> [PersistentIdentifier: CGPoint]`（调 TreeLayout.place）
    - `func setCustomPosition(_ goal: Goal, x: CGFloat, y: CGFloat)`
    - `func reveal(_ goal: Goal)`（置 revealed + sanitizeReveal + save + exportSnapshot）
    - `func resetTree(_ project: Project)`（中长期 revealed=false、清 customX/Y、清偏移、save）
    - `func addEdge(from: Goal, to: Goal)`（防重复、seq）
    - `func toggleEdgeType(_ edge: Edge)`
    - `func deleteGoalTree(_ goal: Goal)`（删节点及关联边）
    - `func addGoalNode(near: Goal, title: String)`（新增独立节点，继承项目，不挂线）
    - `var treeOffset: CGSize`（当前被拔树的偏移，无拖拽为 .zero）

- [ ] **Step 1: addGoal 默认 revealed**

`TaskStore.addGoal` 增加参数默认值：`horizon == .short` 时 `revealed = true`，其余 false：

```swift
    @discardableResult
    public func addGoal(to project: Project, title: String, horizon: Horizon, targetDate: Date?) -> Goal {
        let next = (project.goals.map(\.sortOrder).max() ?? 0) + Self.orderStep
        let g = Goal(title: title, horizon: horizon, targetDate: targetDate, sortOrder: next)
        g.revealed = (horizon == .short)   // 短期目标默认在屏内
        g.project = project
        ctx.insert(g)
        try? ctx.save()
        return g
    }
```

并为既有数据做一次迁移性赋值（在 AppState.start() 里，幂等）：

```swift
    /// 迁移：首次升级后，为短期目标补 revealed=true
    private func migrateRevealFlags() {
        let ctx = container.mainContext
        guard let all = try? ctx.fetch(FetchDescriptor<Goal>()) else { return }
        var touched = false
        for g in all where g.horizon == .short && !g.revealed {
            g.revealed = true
            touched = true
        }
        if touched { try? ctx.save() }
    }
```

在 `start()` 开头调用 `migrateRevealFlags()`。

- [ ] **Step 2: AppState 树状态**

在 `AppState` 增加（参考原型 `offsetOf/pullState/renderedPos`）：

```swift
    // MARK: - 拔树画板状态
    var pullDirection: PullDirection = {
        if let raw = UserDefaults.standard.string(forKey: "twig.pullDirection"),
           let d = PullDirection(rawValue: raw) { return d }
        return .down
    }() {
        didSet { UserDefaults.standard.set(pullDirection.rawValue, forKey: "twig.pullDirection") }
    }
    var pullSession: PullSession?
    var pullComponent: Set<PersistentIdentifier> = []
    var pullDepths: [PersistentIdentifier: Int] = [:]
    var pullProject: Project?
    var hoveredGoal: Goal?
    var treeOffset: CGSize = .zero

    func goalsAndEdges() -> (goals: [Goal], edges: [Edge]) {
        let ctx = container.mainContext
        let goals = (try? ctx.fetch(FetchDescriptor<Goal>())) ?? []
        let edges = (try? ctx.fetch(FetchDescriptor<Edge>())) ?? []
        return (goals, edges)
    }

    func placements(in rect: CGRect) -> [PersistentIdentifier: CGPoint] {
        let (goals, edges) = goalsAndEdges()
        return TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: pullDirection)
    }

    func reveal(_ goal: Goal) {
        goal.revealed = true
        let (goals, edges) = goalsAndEdges()
        TreeTopology.sanitizeReveal(goals: goals, edges: edges)
        try? container.mainContext.save()
        exportSnapshot()
    }

    func setCustomPosition(_ goal: Goal, x: CGFloat, y: CGFloat) {
        goal.customX = x
        goal.customY = y
        try? container.mainContext.save()
    }

    func resetTree(_ project: Project) {
        for g in project.goals {
            g.revealed = (g.horizon == .short)
            g.customX = nil
            g.customY = nil
        }
        treeOffset = .zero
        try? container.mainContext.save()
        exportSnapshot()
    }

    func addEdge(from: Goal, to: Goal) {
        guard from.persistentModelID != to.persistentModelID else { return }
        let (_, edges) = goalsAndEdges()
        let dup = edges.contains {
            $0.type == .sequence
            && $0.from?.persistentModelID == from.persistentModelID
            && $0.to?.persistentModelID == to.persistentModelID
        }
        if !dup {
            container.mainContext.insert(Edge(type: .sequence, from: from, to: to))
            try? container.mainContext.save()
        }
    }

    func toggleEdgeType(_ edge: Edge) {
        edge.type = edge.type == .sequence ? .reference : .sequence
        try? container.mainContext.save()
    }

    func deleteGoalTree(_ goal: Goal) {
        container.mainContext.delete(goal)   // 边级联删除
        try? container.mainContext.save()
        exportSnapshot()
    }

    func addGoalNode(near: Goal, title: String) {
        guard let project = near.project else { return }
        taskStore.addGoal(to: project, title: title, horizon: near.horizon, targetDate: nil)
        exportSnapshot()
    }
```

- [ ] **Step 3: 构建 + 全量测试**

Run: `swift build && swift test`
Expected: build 零告警；既有测试全绿（无新增测试，状态装配在 Task 9 手动验收）

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat: AppState 拔树状态装配（方向/偏移/出土/重置/边管理）"
```

---

### Task 6: 节点卡片 + 小卫星（NodeCardView）

**Files:**
- Create: `Sources/TwigApp/Widget/NodeCardView.swift`
- Modify: `Sources/TwigApp/ColorHex.swift`（加 `Color.twigAccent` 常量）

**Interfaces:**
- Consumes: `Goal`、`AppState`（读任务数）
- Produces：
  - `struct NodeCardView: View`，`init(goal: Goal, color: Color, isBuried: Bool, isFocusing: Bool)` —— 毛玻璃卡 + 衬线标题 + 右侧小卫星（期限 tag / 迷你进度条 / done/total / 红点任务数）
  - 视觉参数（与原型一致）：卡 `background(.white.opacity(0.62))` + `.background(.ultraThinMaterial)`、圆角 11、项目色左边条 3px、标题 `.font(.custom("Georgia", size: 12)).weight(.semibold)`（用 `.serif` design）、期限 tag：short `#D97757` / mid `#6B8FC4` / long `#A6A49E`、卫星在卡片右侧外 7px、竖向居中

- [ ] **Step 1: 实现 NodeCardView**

```swift
import SwiftUI
import TwigCore

/// 节点卡：主体只有阶段名；期限/进度/任务数做成右侧小卫星
struct NodeCardView: View {
    let goal: Goal
    let color: Color
    var isBuried: Bool = false
    var isFocusing: Bool = false

    private var total: Int { goal.tasks.count }
    private var done: Int { goal.tasks.filter(\.isDone).count }
    private var openCount: Int { total - done }
    private var frac: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        Text(goal.title)
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(.white.opacity(0.62))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.85), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .overlay(alignment: .trailing) { satellite }
            .opacity(isBuried ? 0.22 : 1)
            .saturation(isBuried ? 0.6 : 1)
    }

    /// 右侧小卫星：期限 tag → 迷你进度条 → done/total → 红点任务数
    private var satellite: some View {
        HStack(spacing: 4) {
            Text(tagText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tagColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(.white.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.8), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.07)).frame(width: 26, height: 3)
                Capsule().fill(done == total && total > 0 ? Color(red: 0.49, green: 0.61, blue: 0.46) : color)
                    .frame(width: 26 * frac, height: 3)
            }
            Text("\(done)/\(total)")
                .font(.system(size: 9))
                .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.42))
                .monospacedDigit()
            Text("\(openCount)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .frame(minWidth: 15, minHeight: 15)
                .background(color, in: Circle())
        }
        .padding(.leading, 7)
        .offset(x: satelliteWidth)   // 整体移出卡片右缘
        .allowsHitTesting(false)
    }

    private var satelliteWidth: CGFloat { 0 }   // 占位：由 GeometryReader 或固定值实现，见下

    private var tagText: String {
        let base = goal.horizon == .short ? "短期" : goal.horizon == .mid ? "中期" : "长期"
        if let d = goal.targetDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "M/d"
            return base + " " + fmt.string(from: d)
        }
        return base
    }

    private var tagColor: Color {
        switch goal.horizon {
        case .short: return Color(red: 0.85, green: 0.47, blue: 0.34)   // #D97757
        case .mid: return Color(red: 0.42, green: 0.56, blue: 0.77)     // #6B8FC4
        case .long: return Color(red: 0.65, green: 0.64, blue: 0.62)    // #A6A49E
        }
    }
}
```

`satelliteWidth` 的实现：用 `.offset(x:)` 加固定值不行（卡片宽度不定）。改用：把 satellite 放在 `overlay(alignment: .trailing)` 里并设 `.offset(x: …)` 为卫星自身宽度 + 7——更简单可靠的做法：外层用 `ZStack(alignment: .leading)`，卡片 `fixedSize()`，卫星 `.alignmentGuide` 太重。**采用实现**：卡片外面包一层 `HStack(spacing: 7) { card; satellite }`，其中 satellite 用 `.frame(width: 0)` + `overflow: visible` 的思路不可靠——直接用 HStack 真实占位（卫星占布局宽度，节点位置计算时把卫星宽度算进节点宽度）。Task 8 的布局输入节点尺寸 = 卡片宽 + 卫星宽。

最终结构：

```swift
    var body: some View {
        HStack(spacing: 7) {
            cardBody
            satellite
        }
    }
```

`cardBody` = 上面的卡片部分（无 overlay satellite）。这样卫星参与布局，连线挂点用整个 HStack 的宽度（portOf 用 offsetWidth 对应全宽），与原型一致。

- [ ] **Step 2: 构建通过 + 预览截图**

Run: `swift build`
Expected: 零告警。无单测（视觉件）；截图验收在 Task 9 统一做

- [ ] **Step 3: Commit**

```bash
git add Sources/TwigApp/Widget/NodeCardView.swift
git commit -m "feat: 节点卡片（阶段名 + 右侧小卫星，Claude 玻璃风）"
```

---

### Task 7: 茎线画布（StemEdgeCanvas）

**Files:**
- Create: `Sources/TwigApp/Widget/StemEdgeCanvas.swift`

**Interfaces:**
- Consumes: `Edge`、`Goal`、`PullDirection`
- Produces：
  - `struct StemEdgeCanvas: View`，`init(edges: [Edge], positions: [PersistentIdentifier: CGRect], direction: PullDirection, soilLine: CGFloat, focusGoal: PersistentIdentifier?)`
  - `positions` 由 Task 8 传（goal id → 当前帧节点矩形）；`soilLine` = 土线主轴坐标
  - 视觉（与原型 drawStem v2 一致）：4 层光滑曲线叠加锥度（粗 3px 只覆盖根部 28% → 细 0.8px 贯通），`strokeLineCap = .round`，入点消融圆点（r 2.5/3.5），项目色；悬停聚焦时非相关边 opacity 0.3
  - 跨界边：土线处弯折（地上锥度茎、地下虚线 `dash: [4,6]` opacity 0.45）
  - 张力弯曲：bow = 静态微弯（≤8px，按边 id 哈希定向）+ `min(55, |crossVel| × 6 + |crossPull| × 0.25)`（由 Task 8 通过 positions 隐式传入当前帧位置，速度分量由 AppState.pullSession.velocity 提供——本 View 增加参数 `crossPull: CGFloat = 0, crossVel: CGFloat = 0`）
  - 挂点：出挂点在链条方向侧（`chainSign` 侧），入挂点反侧

- [ ] **Step 1: 实现 StemEdgeCanvas**

```swift
import SwiftUI
import TwigCore

/// 茎线画布：多层锥度 + 土壤弯折 + 悬停聚焦
struct StemEdgeCanvas: View {
    let edges: [Edge]
    let positions: [PersistentIdentifier: CGRect]
    let direction: PullDirection
    let soilLine: CGFloat
    var focusGoal: PersistentIdentifier? = nil
    var crossPull: CGFloat = 0
    var crossVel: CGFloat = 0

    var body: some View {
        Canvas { ctx, _ in
            for edge in edges {
                guard let from = edge.from, let to = edge.to,
                      let a = positions[from.persistentModelID],
                      let b = positions[to.persistentModelID] else { continue }
                let isSeq = edge.type == .sequence
                let color = isSeq ? Color(hex: from.project?.colorHint ?? "#D97757") ?? .orange
                                  : Color.white.opacity(0.35)
                let hot = focusGoal == nil
                    || from.persistentModelID == focusGoal
                    || to.persistentModelID == focusGoal
                let out = outPort(a)
                let end = inPort(b)

                if to.revealed || !isSeq {
                    drawStem(ctx: ctx, from: out, to: end, color: color, hot: hot,
                             dashed: !isSeq)
                } else {
                    drawCrossing(ctx: ctx, from: out, to: end, color: color, hot: hot)
                }
            }
        }
    }

    // MARK: - 挂点
    private var sign: CGPoint {   // 链条朝向单位向量
        switch direction {
        case .up: return CGPoint(x: 0, y: 1)
        case .down: return CGPoint(x: 0, y: -1)
        case .left: return CGPoint(x: -1, y: 0)
        case .right: return CGPoint(x: 1, y: 0)
        }
    }
    private func outPort(_ r: CGRect) -> CGPoint {
        direction == .up ? CGPoint(x: r.midX, y: r.maxY)
        : direction == .down ? CGPoint(x: r.midX, y: r.minY)
        : direction == .left ? CGPoint(x: r.minX, y: r.midY)
        : CGPoint(x: r.maxX, y: r.midY)
    }
    private func inPort(_ r: CGRect) -> CGPoint {
        direction == .up ? CGPoint(x: r.midX, y: r.minY)
        : direction == .down ? CGPoint(x: r.midX, y: r.maxY)
        : direction == .left ? CGPoint(x: r.maxX, y: r.midY)
        : CGPoint(x: r.minX, y: r.midY)
    }

    // MARK: - 弯曲（藤蔓张力）
    private func bow(for edge: Edge, length: CGFloat) -> CGFloat {
        let hash = abs(edge.persistentModelID.hashValue % 1000) / 1000.0
        let bowStatic = min(8, length * 0.05) * (hash > 0.5 ? 1 : -1)
        let bowDyn = max(-55, min(55, crossVel * 6 + crossPull * 0.25))
        return bowStatic + bowDyn
    }

    private func curve(from out: CGPoint, to end: CGPoint, bow: CGFloat) -> Path {
        let g = sign
        let perp = CGPoint(x: -g.y * bow, y: g.x * bow)
        let norm: CGFloat = 40
        let m1 = CGPoint(x: out.x + g.x * norm + perp.x * 0.8, y: out.y + g.y * norm + perp.y * 0.8)
        let m2 = CGPoint(x: end.x - g.x * norm + perp.x, y: end.y - g.y * norm + perp.y)
        var p = Path()
        p.move(to: out)
        p.addCurve(to: end, control1: m1, control2: m2)
        return p
    }

    // MARK: - 多层锥度茎
    private func drawStem(ctx: GraphicsContext, from: CGPoint, to: CGPoint,
                          color: Color, hot: Bool, dashed: Bool) {
        let length = hypot(to.x - from.x, to.y - from.y)
        let bow = bowForCurrent(length: length)
        let path = curve(from: from, to: to, bow: bow)
        if dashed {
            ctx.stroke(path, with: .color(color.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            return
        }
        let dim: Double = hot ? 1 : 0.3
        // 4 层叠加锥度：细笔贯通、粗笔只覆盖根部（trim 比例）
        let covers: [CGFloat] = [1, 0.76, 0.52, 0.28]
        for (i, cover) in covers.enumerated() {
            let k = CGFloat(i) / CGFloat(covers.count - 1)
            let width = (0.8 + (3 - 0.8) * k) * (hot ? 1.15 : 1)
            let opacity = (0.4 + (0.9 - 0.4) * k) * dim
            ctx.stroke(path.trimmedPath(from: 0, to: cover),
                       with: .color(color.opacity(opacity)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        // 入点消融圆点
        let dot = Path(ellipseIn: CGRect(x: to.x - 2.5, y: to.y - 2.5, width: 5, height: 5))
        ctx.fill(dot, with: .color(color.opacity(min(1, 0.4 * 1.6) * dim)))
    }

    private func bowForCurrent(length: CGFloat) -> CGFloat {
        let hash: CGFloat = 0.6   // 静态微弯方向由边决定，见 bow(for:) 的哈希；Canvas 内逐边调用
        return bow(for: currentEdge, length: length)
    }
    private var currentEdge: Edge!   // 实现注：见下

    // MARK: - 跨界弯折（土线）
    private func drawCrossing(ctx: GraphicsContext, from out: CGPoint, to end: CGPoint,
                              color: Color, hot: Bool) {
        let mainOut = direction == .up || direction == .down ? out.y : out.x
        let mainEnd = direction == .up || direction == .down ? end.y : end.x
        let t = max(0.05, min(0.95, (soilLine - mainOut) / (mainEnd - mainOut)))
        let s = CGPoint(x: out.x + (end.x - out.x) * t, y: out.y + (end.y - out.y) * t)
        let g = sign
        let bow = min(8, hypot(end.x - out.x, end.y - out.y) * 0.05)
        let perp = CGPoint(x: -g.y * bow, y: g.x * bow)
        // 地上段：锥度茎到土线
        var above = Path()
        above.move(to: out)
        above.addCurve(to: s,
                       control1: CGPoint(x: out.x + g.x * 40 + perp.x * 0.7, y: out.y + g.y * 40 + perp.y * 0.7),
                       control2: CGPoint(x: s.x - g.x * 24 + perp.x * 0.9, y: s.y - g.y * 24 + perp.y * 0.9))
        let dim: Double = hot ? 1 : 0.3
        for (i, cover) in [CGFloat(1), 0.76, 0.52, 0.28].enumerated() {
            let k = CGFloat(i) / 3
            ctx.stroke(above.trimmedPath(from: 0, to: cover),
                       with: .color(color.opacity((0.4 + 0.4 * k) * dim)),
                       style: StrokeStyle(lineWidth: (1 + 1.6 * k), lineCap: .round))
        }
        // 地下段：虚线扎进土壤
        var below = Path()
        below.move(to: s)
        below.addCurve(to: end,
                       control1: CGPoint(x: s.x + g.x * 30, y: s.y + g.y * 30),
                       control2: CGPoint(x: end.x - g.x * 40, y: end.y - g.y * 40))
        ctx.stroke(below, with: .color(color.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
    }
}
```

**实现注**：`currentEdge` 占位是坏的——把 `bow(for:length:)` 改成在 for 循环里直接内联调用（`let bow = bow(for: edge, length: ...)`），删掉 `bowForCurrent` 和 `currentEdge`。另外 `color.opacity(...)` 在 GraphicsContext 里可用；`Path.trimmedPath(from:to:)` 是 SwiftUI 内建。实现者先修这两处再编译。

- [ ] **Step 2: 构建通过**

Run: `swift build`
Expected: 零告警

- [ ] **Step 3: Commit**

```bash
git add Sources/TwigApp/Widget/StemEdgeCanvas.swift
git commit -m "feat: 茎线画布（多层锥度/张力弯曲/土壤弯折/悬停聚焦）"
```

---

### Task 8: 树画布容器 + 手势路由（TreeCanvasView）

**Files:**
- Create: `Sources/TwigApp/Widget/TreeCanvasView.swift`

**Interfaces:**
- Consumes: `AppState`（树状态/手势方法）、`NodeCardView`、`StemEdgeCanvas`、`HoverHud`（Task 9）
- Produces：
  - `struct TreeCanvasView: View`，`init(appState: AppState, size: CGSize)` —— 每帧渲染：`positions = placements + 树偏移（分量节点按 BFS 深度滞后跟随）`
  - 手势路由（**最终手势约定**）：
    - 节点 `DragGesture`（普通拖动）→ `startMoveNode`：只改该节点位置（松手写 customX/Y）
    - 把手（HUD 的 ⇄）拖动 → `startPull`：更新 `pullSession.targetOffset`；`TimelineView(.periodic(1/60))` 驱动 `PullPhysics.step` + 出土判定 + 回弹动画
    - 点击节点 → 无详情窗（v3 定稿：什么都不做，或选可未来扩展）
    - 双击连线 → `toggleEdgeType`（由 StemEdgeCanvas 的命中区触发——SwiftUI Canvas 无法命中，改为在 Task 8 用透明路径覆盖层做双击命中）
  - 出土流程：step 后对组件内未出土节点做 `checkReveal`（埋深 = |节点主轴坐标 − soil| + 20；且 seq 父节点已出土才判定）→ `appState.reveal(goal)`；位置用"从土里滑入槽位"动画（`.animation(.spring(duration: 0.45, bounce: 0.2))`）
  - 松手回弹：`springBack()` rAF（用 TimelineView 帧）以 `springEase` 把 offset 缓动回 0，结束清 session

- [ ] **Step 1: 实现 TreeCanvasView**

```swift
import SwiftUI
import TwigCore

/// 树画布：节点 + 茎线 + 手势路由（每帧驱动）
struct TreeCanvasView: View {
    let appState: AppState
    let size: CGSize

    @State private var movingGoal: Goal?
    @State private var springT: CGFloat? = nil   // 回弹进行中

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60)) { _ in
            let rect = CGRect(origin: .zero, size: size)
            let positions = currentPositions(in: rect)
            ZStack(alignment: .topLeading) {
                StemEdgeCanvas(edges: appState.goalsAndEdges().edges,
                               positions: positions,
                               direction: appState.pullDirection,
                               soilLine: soilLine(in: rect),
                               focusGoal: appState.hoveredGoal?.persistentModelID,
                               crossPull: crossPull,
                               crossVel: crossVel)
                ForEach(appState.goalsAndEdges().goals, id: \.persistentModelID) { goal in
                    if let frame = positions[goal.persistentModelID] {
                        NodeCardView(goal: goal,
                                     color: Color(hex: goal.project?.colorHint ?? "#D97757") ?? .orange,
                                     isBuried: !goal.revealed,
                                     isFocusing: appState.timerStore.activeTask?.goal?.persistentModelID == goal.persistentModelID)
                        .position(x: frame.midX, y: frame.midY)
                        .gesture(nodeDrag(goal))
                        .onHover { inside in
                            appState.hoveredGoal = inside ? goal : (appState.hoveredGoal == goal ? nil : appState.hoveredGoal)
                        }
                    }
                }
                HoverHud(appState: appState, positions: positions)
            }
            .onChange(of: timeline.date) { _, _ in tick() }   // TimelineView 上下文里驱动物理帧
        }
    }

    // MARK: - 每帧位置（布局 + 拔树偏移，末端滞后）
    private func currentPositions(in rect: CGRect) -> [PersistentIdentifier: CGRect] {
        var base = appState.placements(in: rect)
        // 手动位置覆盖
        for (id, _) in base {
            if let g = appState.goalsAndEdges().goals.first(where: { $0.persistentModelID == id }),
               let cx = g.customX, let cy = g.customY {
                base[id] = CGPoint(x: cx, y: cy)
            }
        }
        var frames: [PersistentIdentifier: CGRect] = [:]
        let offset = appState.treeOffset
        for (id, pt) in base {
            var p = pt
            if let session = appState.pullSession,
               appState.pullComponent.contains(id) {
                let depth = CGFloat(appState.pullDepths[id] ?? 0)
                let follow = 1 / (1 + depth * 0.25)
                p = CGPoint(x: pt.x + offset.width * follow, y: pt.y + offset.height * follow)
            }
            frames[id] = CGRect(x: p.x - 70, y: p.y - 24, width: 140, height: 48)   // 节点近似尺寸，NodeCard 实际尺寸由内容撑开；挂点以中心算
        }
        _ = session_none // 占位防误用
        return frames
    }

    ...
}
```

**实现注（重要，避免实现者踩坑）**：
- 上面 `.onChange(of: timeline.date)` 在 `TimelineView` content closure 里拿不到 `timeline` 变量名——正确做法：content 参数是 `TimelineViewDefaultContext`，直接用它的 `date`：`TimelineView(.periodic(from: .now, by: 1.0/60)) { context in ... 在 body 计算前调用 tickIfNeeded(context.date) }`。把 `tick()` 改成幂等按时间戳驱动（记录 lastTickDate，每帧 step 一次即可，60fps 的 periodic 本身已是帧节奏）。
- 节点矩形不需要估算：用 preference/anchor 读取 NodeCard 真实尺寸太重，**挂点直接用节点中心 + 近似半宽半高**（原型里也是 fixed 近似），半宽取 75/半高 24 即可；后续手感迭代再精化。
- `session_none` 占位行删掉。

`tick()` 核心逻辑：

```swift
    private func tick() {
        if var session = appState.pullSession {
            PullPhysics.step(&session, direction: appState.pullDirection)
            appState.pullSession = session
            appState.treeOffset = session.offset
            // 出土判定：组件内、父已出土、未出土的最近一个
            let (goals, edges) = appState.goalsAndEdges()
            for g in goals where !g.revealed && appState.pullComponent.contains(g.persistentModelID) {
                if let parent = TreeTopology.parent(of: g, edges: edges), !parent.revealed { continue }
                let buried = buriedDepth(of: g) + 20
                if PullPhysics.checkReveal(&session, direction: appState.pullDirection, buriedDepth: buried) {
                    appState.pullSession = session
                    appState.reveal(g)
                }
            }
        } else if springT != nil {
            // 回弹帧：offset = start × (1 − easeOutBack(t))
            let t = min(1, (springT! + 1/60 / 0.38))
            springT = t >= 1 ? nil : t
            // springStart 在 mouseup 时记录到 appState.springStartOffset
            let e = PullPhysics.springEase(min(t, 1))
            appState.treeOffset = CGSize(width: appState.springStartOffset.width * (1 - e),
                                         height: appState.springStartOffset.height * (1 - e))
            if springT == nil { appState.treeOffset = .zero }
        }
    }
```

`AppState` 需补 `var springStartOffset: CGSize = .zero`。手势：

```swift
    private func nodeDrag(_ goal: Goal) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if movingGoal?.persistentModelID != goal.persistentModelID {
                    movingGoal = goal
                    appState.hoverLockedForDrag = true   // 拖动时隐藏 HUD（AppState 加此标志，HoverHud 尊重它）
                }
                goal.customX = (goal.customX ?? basePos(of: goal).x) + value.translation.width
                goal.customY = (goal.customY ?? basePos(of: goal).y) + value.translation.height
                // 注意：需要记录拖拽起点——实现时加 @State dragOrigin
            }
            .onEnded { _ in
                appState.setCustomPosition(goal, x: goal.customX ?? 0, y: goal.customY ?? 0)
                movingGoal = nil
                appState.hoverLockedForDrag = false
            }
    }
```

实现注：`onChanged` 里直接累加 translation 会重复叠加——正解：在 `movingGoal` 首次设置时记录 `dragOrigin = goal.customX ?? basePos`，然后 `customX = dragOrigin.x + value.translation.width`。`basePos(of:)` = `appState.placements(in:)[id]`。`hoverLockedForDrag` 加到 AppState（默认 false）。

**拔树入口**（HUD ⇄ 把手）：Task 9 的 HoverHud 提供 `onPullStart: (Goal, CGPoint) -> Void`，TreeCanvasView 传入：

```swift
    private func startPull(_ goal: Goal) {
        let comp = TreeTopology.component(of: goal, edges: appState.goalsAndEdges().edges)
        appState.pullComponent = comp.ids
        appState.pullDepths = comp.depths
        appState.pullProject = goal.project
        appState.pullSession = PullSession()
    }

    // HUD 的把手 DragGesture.onChanged 调这个：
    private func pullDrag(_ translation: CGSize) {
        guard var session = appState.pullSession else { return }
        session.targetOffset = CGSize(width: translation.width * 0.9, height: translation.height * 0.9)
        appState.pullSession = session
    }

    private func endPull() {
        appState.springStartOffset = appState.treeOffset
        springT = 0
        appState.pullSession = nil
        appState.pullComponent = []
    }
```

- [ ] **Step 2: 构建通过 + 冒烟**

Run: `swift build && .build/debug/TwigApp &`（3 秒存活后 pkill）
Expected: 零告警；悬浮窗显示节点树（短期根贴出土侧边缘，中长期埋土线外半透明）

- [ ] **Step 3: Commit**

```bash
git add Sources/TwigApp/Widget/TreeCanvasView.swift Sources/TwigApp/AppState.swift
git commit -m "feat: 树画布容器 + 手势路由（移动/拔树/回弹/出土判定）"
```

---

### Task 9: 悬停 HUD（功能排 + 叶子排 + 挂点 + 任务详情）

**Files:**
- Create: `Sources/TwigApp/Widget/HoverHud.swift`
- Create: `Sources/TwigApp/Widget/TaskLeafPopover.swift`
- Modify: `Sources/TwigApp/Widget/TreeCanvasView.swift`（接入 HUD）

**Interfaces:**
- Consumes: `AppState`、`TreeCanvasView` 的 `startPull/pullDrag/endPull`
- Produces：
  - `struct HoverHud: View`，`init(appState:positions:)` —— 悬停上下文（节点+功能区+叶子=一体，180ms 防抖）
  - 上排按钮（圆形 26px 玻璃）：＋新增独立节点（内联输入）/ 🗑删除 / ⇄拔树把手（DragGesture → 上面三个回调）/ ↺单树重置（仅根节点）
  - 下排叶子：任务 ≤2 字关键字（最多 6 + "+N"），点击 → `TaskLeafPopover`
  - 出挂点小圆点：按住拖到另一节点松开 → `appState.addEdge`（橡皮线用 Canvas 临时画）
  - `struct TaskLeafPopover: View`，`init(task: Task, goal: Goal, appState:)` —— 全标题 + 目标/项目/预估 + ▶开始番茄（`timerStore.start(task:mode:.pomodoro)`）/ ✓完成 / 🗑删除

- [ ] **Step 1: 实现 HoverHud + TaskLeafPopover**

```swift
import SwiftUI
import TwigCore

/// 悬停 HUD：上排功能钮 + 下排叶子 + 出挂点（与节点同一悬停上下文）
struct HoverHud: View {
    let appState: AppState
    let positions: [PersistentIdentifier: CGRect]

    var body: some View {
        if let goal = appState.hoveredGoal, !appState.hoverLockedForDrag,
           let frame = positions[goal.persistentModelID] {
            let color = Color(hex: goal.project?.colorHint ?? "#D97757") ?? .orange
            // 上排功能钮
            HStack(spacing: 6) {
                hudButton("＋", color: Color(red: 0.49, green: 0.61, blue: 0.46), help: "新增分支") {
                    appState.addingNodeNear = goal   // AppState 加此状态：内联输入卡
                }
                hudButton("🗑", color: .secondary, help: "删除") {
                    appState.deleteGoalTree(goal)
                }
                pullHandle(color: Color(red: 0.62, green: 0.76, blue: 0.92), goal: goal)
                if TreeTopology.isRoot(goal, edges: appState.goalsAndEdges().edges) {
                    hudButton("↺", color: Color(red: 0.91, green: 0.76, blue: 0.48), help: "重置这棵树") {
                        if let p = goal.project { appState.resetTree(p) }
                    }
                }
            }
            .position(x: frame.midX, y: frame.minY - 18)

            // 下排叶子
            LeafRow(goal: goal, color: color, appState: appState)
                .position(x: frame.midX, y: frame.maxY + 18)

            // 出挂点
            PortDot(appState: appState, goal: goal, frame: frame)
        }
    }

    private func hudButton(_ label: String, color: Color, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.78))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func pullHandle(color: Color, goal: Goal) -> some View {
        Text("⇄").font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(.white.opacity(0.78))
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
            .help("拔树（按住沿方向拽）")
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if appState.pullSession == nil { onPullStart?(goal) }
                        onPullDrag?(value.translation)
                    }
                    .onEnded { _ in onPullEnd?() }
            )
    }

    // 由 TreeCanvasView 注入
    var onPullStart: ((Goal) -> Void)?
    var onPullDrag: ((CGSize) -> Void)?
    var onPullEnd: (() -> Void)?
}
```

`LeafRow`（同一文件）：

```swift
/// 叶子排：任务关键字（≤2 字），点击开任务详情
struct LeafRow: View {
    let goal: Goal
    let color: Color
    let appState: AppState

    private var openTasks: [TwigCore.Task] {
        goal.tasks.filter { !$0.isDone }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(openTasks.prefix(6), id: \.persistentModelID) { task in
                Text(String(task.title.prefix(2)))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.24, green: 0.23, blue: 0.21))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.white.opacity(0.8))
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(topLeadingRadius: 12, bottomLeadingRadius: 3,
                                     bottomTrailingRadius: 12, topTrailingRadius: 12))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 3,
                                               bottomTrailingRadius: 12, topTrailingRadius: 12)
                            .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1)
                    )
                    .onTapGesture { appState.leafTask = (task, goal) }   // AppState 加此状态
                    .help(task.title)
            }
            if openTasks.count > 6 {
                Text("+\(openTasks.count - 6)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
```

`TaskLeafPopover.swift`：

```swift
import SwiftUI
import TwigCore

/// 任务详情（点叶子弹出）：番茄挂任务级
struct TaskLeafPopover: View {
    let appState: AppState

    var body: some View {
        if let (task, goal) = appState.leafTask {
            let color = Color(hex: goal.project?.colorHint ?? "#D97757") ?? .orange
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.title).font(.system(size: 13, weight: .semibold, design: .serif))
                    Spacer()
                    Button { appState.leafTask = nil } label: {
                        Text("✕").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                Text("\(goal.title) · \(goal.project?.name ?? "") · \(task.estimateMin.map { "约\($0)分钟" } ?? "未定")")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    leafAction("▶", color: Color(red: 0.85, green: 0.47, blue: 0.34), help: "开始番茄") {
                        appState.timerStore.start(task: task, mode: .pomodoro)
                        appState.leafTask = nil
                    }
                    leafAction("✓", color: Color(red: 0.49, green: 0.61, blue: 0.46), help: "完成") {
                        appState.taskStore.toggleTask(task)
                        appState.leafTask = nil
                        appState.exportSnapshot()
                    }
                    leafAction("🗑", color: .secondary, help: "删除任务") {
                        if let g = task.goal {
                            g.tasks.removeAll { $0.persistentModelID == task.persistentModelID }
                            try? appState.container.mainContext.save()
                        }
                        appState.leafTask = nil
                    }
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(.white.opacity(0.82))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
    }

    private func leafAction(_ label: String, color: Color, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.78))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
```

`PortDot`（放 HoverHud 同文件）：

```swift
/// 出挂点：按住拖到另一节点建立顺序关联
struct PortDot: View {
    let appState: AppState
    let goal: Goal
    let frame: CGRect
    @State private var dragPoint: CGPoint?

    var body: some View {
        let portPos = CGPoint(x: frame.maxX, y: frame.midY)   // 简化：恒右侧；方向化后续迭代
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color(red: 0.65, green: 0.64, blue: 0.62), lineWidth: 1.5))
            .frame(width: 10, height: 10)
            .position(portPos)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragPoint = CGPoint(x: portPos.x + value.translation.width,
                                            y: portPos.y + value.translation.height)
                    }
                    .onEnded { value in
                        // 命中检测：松手点在某个节点 frame 内 → 建边
                        for (id, frame) in positionsRef where frame.contains(value.location) {
                            if let target = appState.goalsAndEdges().goals.first(where: { $0.persistentModelID == id }),
                               target.persistentModelID != goal.persistentModelID {
                                appState.addEdge(from: goal, to: target)
                            }
                            break
                        }
                        dragPoint = nil
                    }
            )
            .overlay {
                if let dragPoint {
                    Path { p in
                        p.move(to: portPos)
                        p.addLine(to: dragPoint)
                    }
                    .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
    }

    var positionsRef: [PersistentIdentifier: CGRect] = [:]
}
```

实现注：`positionsRef` 由 HoverHud 传入（`PortDot(appState:goal:frame:)` 调用处补 `positionsRef: positions`）。`value.location` 是相对手势起点的视图坐标——SwiftUI DragGesture 的 `location` 在父视图坐标系，命中检测直接用即可（frames 也是同坐标系）。

- [ ] **Step 2: TreeCanvasView 接入**

在 `TreeCanvasView` 的 ZStack 里：

```swift
                HoverHud(appState: appState, positions: positions,
                         onPullStart: startPull, onPullDrag: pullDrag, onPullEnd: endPull)
                TaskLeafPopover(appState: appState)
```

`HoverHud` 的 init 需要补上三个回调参数（改成 memberwise 传参）。

- [ ] **Step 3: 构建 + 冒烟 + 手动验收清单**

Run: `swift build && .build/debug/TwigApp &`

手动验收（对照原型）：
- [ ] 悬停节点：上排 ＋🗑⇄（根节点多 ↺），下排叶子（关键字），右侧出挂点
- [ ] 普通拖动节点 = 移位置（重启后保留）；按住 ⇄ 拖 = 拔树（重力感、末端甩动）
- [ ] 点叶子 → 任务详情；▶ 起番茄（横条倒计时）；✓ 完成；🗑 删除
- [ ] 挂点拉线连到另一节点 → 出现茎线；双击线 → 变引用虚线
- [ ] ↺ 单树重置：中长期埋回土里

- [ ] **Step 4: Commit**

```bash
git add Sources/TwigApp
git commit -m "feat: 悬停 HUD（功能排+叶子+挂点拉线）+ 任务级番茄详情"
```

---
### Task 10: 悬浮窗集成（默认展开 + 方向切换 + 折叠）

**Files:**
- Create: `Sources/TwigApp/Widget/TreeWidgetController.swift`
- Modify: `Sources/TwigApp/Widget/WidgetView.swift`（替换三态为 树画板/折叠）
- Modify: `Sources/TwigApp/Widget/WidgetWindowController.swift`（尺寸随内容）
- Modify: `Sources/TwigApp/Main/SettingsView.swift`（方向 Picker 已有，改存 `twig.pullDirection`）
- Modify: `Sources/TwigApp/TwigAppMain.swift`（启动默认展开）

**Interfaces:**
- Consumes: `TreeCanvasView`（Task 8）、`AppState.pullDirection`
- Produces：
  - `enum WidgetMode { case tree, folded }`；`AppState.widgetMode`（默认 `.tree`，折叠时只显示横条 + 虚线末梢）
  - `TreeWidgetController`：窗口尺寸 = 树内容包围盒 + 边距（展开时按需扩窗，最大不超过屏幕 1/3）；折叠时 560×64

- [ ] **Step 1: WidgetView 改为树画板 + 折叠切换**

```swift
import SwiftUI
import TwigCore

/// 悬浮窗主体：默认节点树画板，可折叠成横条
struct WidgetView: View {
    let appState: AppState
    var controller: WidgetWindowController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 0) {
                CollapsedBarView(appState: appState)   // 头部横条（当前任务+番茄+折叠钮）
                if appState.widgetMode == .tree {
                    TreeCanvasView(appState: appState, size: treeSize)
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                appState.timerStore.tick()
            }
        }
    }

    private var treeSize: CGSize {
        controller.contentSize   // 控制器提供当前内容区尺寸
    }
}
```

`AppState` 增加：

```swift
    var widgetMode: WidgetMode = .tree
    var addingNodeNear: Goal?     // HUD ＋ 的内联输入目标
    var leafTask: (TwigCore.Task, Goal)?   // 叶子弹窗
    var hoverLockedForDrag = false
    var springStartOffset: CGSize = .zero
```

`CollapsedBarView` 增加折叠钮（▾/▸）切换 `appState.widgetMode`，折叠态画虚线末梢（沿用 v1 的 DashedExtensionView 即可，方向化由 `pullDirection` 决定朝向）。

`WidgetWindowController` 增加：

```swift
    /// 内容区尺寸（树画板）：默认 760×440，按节点包围盒扩展
    var contentSize: CGSize = CGSize(width: 760, height: 440)

    func resizeToFit(content: CGSize, animated: Bool = true) {
        guard let panel else { return }
        let w = max(560, content.width + 40)
        let h = 64 + (content.height > 0 ? content.height + 40 : 0)
        var frame = panel.frame
        frame.origin.y += frame.height - h
        frame.size = NSSize(width: w, height: h)
        panel.setFrame(frame, display: true, animate: animated)
    }
```

`TreeCanvasView` 里在布局后把内容包围盒回写 `controller.contentSize` 并调 `resizeToFit`（通过 AppState 中转：`appState.reportedTreeBounds`）。

- [ ] **Step 2: 设置页方向 Picker 接到 pullDirection**

`SettingsView` 的枝干 Section 改为：

```swift
            Section("枝干") {
                Picker("出土方向", selection: Binding(
                    get: { appState.pullDirection },
                    set: { appState.pullDirection = $0 }
                )) {
                    Text("向下拽").tag(PullDirection.down)
                    Text("向上拽").tag(PullDirection.up)
                    Text("向左拽").tag(PullDirection.left)
                    Text("向右拽").tag(PullDirection.right)
                }
                Text("拖拽方向 = 出土方向；树朝反方向的土壤长")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

删掉旧的 `twig.branchDirection` @AppStorage。

- [ ] **Step 3: 构建 + 冒烟 + 手动验收**

Run: `swift build && .build/debug/TwigApp &`

手动验收：
- [ ] 启动即展开树画板（不再是"悬停才展开"）
- [ ] ▾ 折叠 → 只剩横条 + 虚线末梢；▸ 展开恢复
- [ ] 设置里切方向 → 树朝向/土壤位置立即切换
- [ ] 窗口随节点数量扩缩，不裁切节点

- [ ] **Step 4: Commit**

```bash
git add Sources/TwigApp
git commit -m "feat: 悬浮窗默认展开树画板 + 折叠 + 方向切换接线"
```

---

### Task 11: 主窗口报表分项目 + 选中态持久化

**Files:**
- Modify: `Sources/TwigApp/Main/ReportsView.swift`
- Modify: `Sources/TwigApp/Main/ProjectListView.swift` / `MainWindowView.swift`

**Interfaces:**
- Consumes: `ReportAggregator`、`TaskStore.allProjects()`
- Produces：报表页顶部范围切换（全部项目 / 各项目），与侧边栏选中态共享；选中项目持久化 UserDefaults `twig.selectedProject`

- [ ] **Step 1: 报表范围切换**

`ReportsView` 增加：

```swift
    @State private var scopeProject: String? = nil   // nil = 全部；否则项目名
```

顶部加 Picker（segmented）：`全部项目` + 各项目名。过滤逻辑：day/week 聚合不变，过滤 `entries` 为该项目任务的 TimeEntry（`entry.task?.goal?.project?.name == scopeProject`）；单项目时"分项目专注"改为"分目标专注"（按 goal.title 聚合）。

- [ ] **Step 2: 选中态持久化 + 三处共享**

`MainWindowView` 的 `selectedProject` 改为读初始值：

```swift
    @State private var selectedProject: Project? = nil
    // onAppear 时恢复
    .onAppear {
        if let name = UserDefaults.standard.string(forKey: "twig.selectedProject") {
            selectedProject = appState.taskStore.allProjects().first { $0.name == name }
        }
    }
    .onChange(of: selectedProject) { _, p in
        UserDefaults.standard.set(p?.name, forKey: "twig.selectedProject")
        if let p { scopeProject = p.name }   // 报表范围联动（把 scopeProject 提升到 MainWindowView 传入 ReportsView）
    }
```

- [ ] **Step 3: 构建 + 手动验收**

Run: `swift build && .build/debug/TwigApp &`
- [ ] 报表顶部可切范围；选单项目时显示分目标横条
- [ ] 选中项目后切 tab 再回来选中态还在；重启 app 也在

- [ ] **Step 4: Commit**

```bash
git add Sources/TwigApp/Main
git commit -m "feat: 报表分项目范围切换 + 项目选中态持久化"
```

---

### Task 12: 总验收 + 打包

**Files:**
- Modify: `Sources/TwigApp/Widget/PeekListView.swift`（悬停横条的今日浮层保留，行尾 ▶ 起番茄——如已存在则核对，不存在则从原型补）

- [ ] **Step 1: 全量测试**

Run: `swift test`
Expected: 全绿（60+ 测试）

- [ ] **Step 2: 打包 + 手动总验收**（对照设计 v3 手势词汇表逐项）

```bash
./scripts/make-app.sh && open build/Twig.app
```

- [ ] 默认展开树画板；根贴出土侧边缘；中长期埋土线外半透明
- [ ] ⇄ 把手拔树：重力回滑、猛拽出土、一拉一个、松手回弹、根迁移
- [ ] 普通拖动 = 移位置且持久化；拖动时 HUD 隐藏
- [ ] 悬停 HUD：＋🗑⇄（根↺）；叶子排；叶子详情 ▶✓🗑
- [ ] 挂点拉线建关联；双击改型
- [ ] 番茄：暂停/停止、结束确认勾掉发起任务
- [ ] CLI 加任务 → 画板出现（收件箱链路）
- [ ] 报表分项目；主窗口选中态持久化
- [ ] `kill -9` 重启：数据/出土状态/位置都在；未闭合计时弹补记

- [ ] **Step 3: Commit + 推送**

```bash
git add -A
git commit -m "feat: v2 拔树画板总验收"
git push origin main
```

---

## Self-Review 记录

**Spec 覆盖**（设计 v3 章节 → 任务）：

- 产品形态（默认展开/折叠/今日浮层）→ Task 10、12
- 拔树模型（重力/峰值/消耗/根迁移/朝向约定/顺序约束）→ Task 2-4（引擎）、Task 8（接线）
- 手势词汇表（移动/把手拔树/HUD/叶子/挂点/双击改型/悬停上下文）→ Task 8-9
- 节点与连线视觉 → Task 6-7
- Edge 一等实体 + 持久化 → Task 1、5
- 主窗口报表分项目 → Task 11
- 番茄任务级 → Task 9（popover）+ Task 12（验收）

**已知有意简化**：

- 挂点恒在节点右侧（不随方向旋转），原型里也是如此简化，交互迭代期再方向化
- 节点挂点用近似半宽（75/24），不读真实渲染尺寸
- 土堆（mound）、边界发光预热、出土滑入动画在 Task 8/10 提供挂载点但不强制像素级还原，手感迭代期细化
- 叶子关键字 = 任务标题前 2 字（原型同款）

**Type 一致性**：`PullSession`/`PullPhysics.*`、`TreeLayout.place(goals:edges:rect:direction:)`、`TreeTopology.*`、`AppState` 新增成员在 Task 5/8/9/10 间已对齐（`hoverLockedForDrag`、`springStartOffset`、`addingNodeNear`、`leafTask` 均在 Task 10 Step 1 统一声明）。
