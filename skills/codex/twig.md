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
