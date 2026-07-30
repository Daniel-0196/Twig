# Twig — 个人 Mac 桌面 Todo App 设计文档

日期：2026-07-30
状态：已与作者逐节评审确认

## 1. 定位与动机

为自己定制的 macOS 桌面 todo 工具。市面工具不满足的核心诉求：**聚焦短线 + 长线任务、多项目管理 + 时间管理，追踪开发进度和开发目标**。

名字 **Twig**（小枝），呼应"未来任务像枝干一样延展"的核心意象。

## 2. 核心需求（已确认）

- **三层数据结构**：项目（Project）→ 目标节点（Goal，短/中/长期）→ 任务（Task）
- **时间管理**：实际耗时统计、截止/预估管理、番茄钟/专注计时、日报/周报回顾
- **桌面常驻展示**：悬浮部件上能看到短/中/长期目标节点
- **git 集成**：项目绑定本地 git 仓库，自动读取提交记录辅助追踪开发进度
- **Agent 接口**：Claude Code / Codex 等 agent 可通过 skill 快速添加任务
- **个人单机使用**，数据只存本机，不做同步（YAGNI）

## 3. 技术方案

- **单 Xcode App 工程，Swift + SwiftUI，最低 macOS 14**
- 存储：**SwiftData**（本机）
- 悬浮窗：`NSPanel` 配成无边框 / 透明 / 置顶 / 非激活样式，毛玻璃用 `NSVisualEffectView`
- git 读取：`Process` 调系统 `git log`（只读）
- 零第三方依赖
- 工程内部按职责分层（不拆独立 SPM 模块）：

| 模块 | 职责 | 依赖 |
|---|---|---|
| `Models` | SwiftData 实体定义 | 无 |
| `Stores` | 业务状态与逻辑（任务 CRUD、番茄钟状态机、git 读取、报表统计） | Models |
| `Widget/` | 悬浮部件：横条视图、枝干展开视图、窗口控制器 | Stores |
| `Main/` | 主窗口：项目管理、目标时间轴、日报周报、设置 | Stores |
| `Infra/` | git 子进程封装、窗口行为工具、登录项启动 | 无 |

两类窗口（悬浮部件 + 主窗口）共享同一个 SwiftData 容器。App 设为登录项自启；默认显示 Dock 图标，设置里可切到纯菜单栏模式。

## 4. 数据模型

```
Project（项目）
├─ name: String
├─ colorHint: String        ← 差异色彩，目标/任务继承显示
├─ repoPath: String?        ← 绑定的本地 git 仓库路径，可空
├─ goals: [Goal]
└─ createdAt: Date

Goal（目标节点）
├─ project → Project
├─ title: String
├─ horizon: enum { short, mid, long }
├─ targetDate: Date?        ← 长期目标只定到季度时，存该季度末日期，UI 显示为「Q4」
├─ isDone: Bool
├─ sortOrder: Double        ← 枝干上的排列
└─ tasks: [Task]

Task（任务）
├─ goal → Goal
├─ title: String
├─ isDone: Bool
├─ estimateMin: Int?        ← 预估分钟
├─ dueDate: Date?
├─ completedAt: Date?
└─ sortOrder: Double

TimeEntry（一段计时记录）
├─ task → Task?             ← 可空，允许"只计时没选任务"
├─ startedAt / endedAt: Date
├─ kind: enum { pomodoro, stopwatch, break }
└─ lastHeartbeat: Date      ← 崩溃恢复用
```

约定：

- 日报/周报**不是表**，是 TimeEntry + Task.completedAt + git 提交的查询结果，现算现用
- 预估（estimateMin）vs 实际（TimeEntry 总和）是进度追踪的核心对比

## 5. 悬浮部件交互

### 视觉风格（已锁定）

半透明毛玻璃质感；圆润的块（节点本身是圆角玻璃块）；极简文字（能省则省）；差异色彩；远处节点渐隐表达距离感。设计语言参考 Claude（暖米白 + 赤陶橙基调）。

**颜色规则**：颜色以项目为单位（`Project.colorHint`），一个项目 = 一条枝干 = 一个颜色，其下的目标节点和任务块都继承该项目色；多个项目的枝干在悬浮窗里并排展开时靠颜色区分归属。

### 状态机

```
Collapsed（紧凑横条 + 半透明虚线向屏幕外延展，末梢低透明度彩色小圆块）
  ├─ 悬停/点击 → Peeked（滑出今日任务清单，可直接勾选；移开/点击别处回 Collapsed）
  └─ 拖动末梢节点 → Expanded
Peeked ─ 拖动末梢节点 → Expanded
Expanded（枝干沿贝塞尔曲线完全展开，节点 = 圆润玻璃块，近实远虚）
  ├─ 拖动节点改变时间轴位置 = 改排期；拖到另一枝干 = 改归属项目
  └─ 点击空白 / ESC → Collapsed
```

行为约定：

- 所有展开非模态，窗口永远不抢键盘焦点（勾选任务除外）
- 手势手感（拖多远触发、动画曲线、磁吸）做成可调参数，开发时出多版原型迭代，不在设计阶段定死

## 6. 番茄钟 / 计时器

- **三种模式**：番茄钟倒计时 / 正计时（手动停）/ 单次自定义倒计时
- **全局默认可配**：专注时长、短休息、长休息、几个番茄后长休息（出厂默认 25/5/15/4）
- **单次可临时改**：开始专注时单独设时长，不改全局默认
- **提醒可配**：提示音开关/音量、系统通知开关、到点是否自动开始休息
- 开始方式：横条计时区 / 任务右键"开始专注"
- 结束：通知 + 提示音，自动记 TimeEntry，并询问"任务完成了吗？"
- 休息也计时（kind = .break），日报区分专注/休息
- 中途停止 → 询问保留还是丢弃这段时长

## 7. 主窗口

左侧项目列表（带颜色）；中间目标时间轴（短/中/长期泳道）；右侧任务详情；顶部"今日 / 本周"报表页签（TimeEntry 聚合 + git 提交列表 + 已完成任务清单）；设置页（计时器配置、仓库绑定、导入失败列表、Dock/菜单栏模式）。

## 8. git 集成

- 项目可绑定本地仓库路径；`GitStore` 用 `Process` 执行 `git log`（只读：log、分支名）
- 提交记录按时间范围展示在项目时间线和日报里
- 任务关联采用保守策略：commit message 含 `#任务序号` 或任务标题完全匹配时，**提示**用户勾选关联，确认后才写入；不自动勾

## 9. Agent 接口 + Skill 套件

**agent 不直接碰数据库，走收件箱文件**：

```
agent → twig CLI（随 app 构建的薄命令行工具）
      → 追加一行 JSON 到 ~/Library/Application Support/Twig/inbox.jsonl
      → Twig.app 监视该文件（DispatchSource + 启动时全量检查）
      → 校验、去重、导入 SwiftData，清空已处理行
```

理由：app 不在运行也能加任务；无 IPC / 端口 / 权限弹窗；多进程直写 SwiftData 的 SQLite 有损坏风险，收件箱规避；CLI 极薄，将来换存储方案 agent 侧不用改。

CLI 用法：

```bash
twig add "修复渲染管线内存泄漏" --project mergeCook4 --goal "demo可玩" \
        --due 2026-08-05 --estimate 120
twig list --project mergeCook4   # 查重用
```

Skill 套件：仓库 `skills/` 目录，一份能力源文件生成两种形态：

- `skills/claude/twig/SKILL.md` → 部署到 `~/.claude/skills/twig/`
- `skills/codex/twig.md` → 部署到 `~/.codex/prompts/`

内容：什么场景该加任务、`twig` 命令用法、加之前先 `twig list` 查重、项目名对照表。

## 10. 错误处理

原则：不崩、不丢数据、出错给一条人话提示。

| 场景 | 策略 |
|---|---|
| 绑定的 git 仓库路径失效 | 项目卡片显示灰色"仓库失联"标记，git 功能静默降级；点击可重新选择 |
| `git log` 失败/超时 | 5 秒超时杀子进程，本次跳过下轮再试；不阻塞 UI |
| 收件箱 JSON 坏行 | 跳过并移到 `inbox.bad.jsonl` 留档，设置页显示"有 N 条导入失败" |
| 计时中崩溃/重启 | TimeEntry 启动即落盘 + 每分钟心跳；重启发现未闭合记录，询问是否补记 |
| SwiftData 迁移失败 | 启动时先自动备份（留最近 3 份）再迁移，失败回滚并提示 |
| 悬浮窗被拖出屏幕 | 启动时校验位置可见性，出界则回默认位置 |

## 11. 测试策略

- **单元测试**：番茄钟状态机（时长计算）、收件箱解析（好/坏/重复行）、报表聚合（日/周边界，如跨午夜）、git log 输出解析
- **不做 UI 自动化测试**：悬浮窗交互靠手动原型迭代验证
- **手动验收清单**：每个里程碑过核心路径（加任务 → 计时 → 完成 → 看日报 → 重启数据还在）

## 12. 其他决定

- App icon 用 dreamina 生成（本机已装 dreamina CLI 并已登录），视觉方向：Claude 设计语言（暖米白 + 赤陶橙、衬线气质）
- 工程托管在 GitHub（账号 Daniel-0196，凭据在 macOS 钥匙串），开发过程同步 git 管理，按里程碑频繁 commit
- 仓库地址：开发启动时创建（github.com/Daniel-0196/twig）

## 13. 明确不做（YAGNI）

- 云同步 / 多设备 / iPhone 版
- 协作、分享、评论
- 标签系统、看板视图（泳道时间轴已覆盖需求）
- commit 与任务的智能自动关联（只做提示式保守匹配）
- 目标层级再加深（三层够了）
