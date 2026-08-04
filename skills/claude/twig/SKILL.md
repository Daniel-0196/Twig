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
7. CLI 直接写数据库（与运行中的 app 共享同一 SwiftData 库）。告诉用户"已记到 Twig"即可。

## 批量记录

用户一次性说多件事时，逐条 `twig add`，全部加完后汇总列出加了哪几条。

## 查任务

`twig list`（全部项目）或 `twig list --project 项目名`。输出含 ☐/☑ 状态，回答"我还有什么要做"类问题时按 项目 → 目标 组织转述。
