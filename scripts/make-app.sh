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
