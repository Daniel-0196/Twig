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
