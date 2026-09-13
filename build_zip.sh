#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$DIR/magisk_module"
VERSION=$(grep '^version=' "$MODULE_DIR/module.prop" | cut -d= -f2 | tr -d '\r\n ')
OUTPUT_ZIP="$DIR/Lenovo-TB522FU-Brightness-Fix-${VERSION}.zip"

echo "正在打包 Magisk / KernelSU 即刷模块 (版本: $VERSION)..."
rm -f "$OUTPUT_ZIP"
cd "$MODULE_DIR"
zip -r "$OUTPUT_ZIP" . -x "*.DS_Store" "*.git*" "*webui.log" "logs/*" "*~"

echo "=========================================="
echo "✅ 打包完成: $OUTPUT_ZIP"
echo "📦 文件大小: $(du -h "$OUTPUT_ZIP" | cut -f1)"
echo "🚀 可直接在 KernelSU / APatch / Magisk 管理器中从本地存储刷入！"
echo "=========================================="
