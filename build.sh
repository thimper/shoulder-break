#!/bin/bash
# 把 Sources/*.swift 编译成一个可执行文件,再手工组装成 .app
# 不需要 Xcode 工程文件,只用命令行工具链。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ShoulderBreak"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DEPLOY_TARGET="13.0"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

ARCH="$(uname -m)"
echo "==> 编译 ($ARCH, macOS $DEPLOY_TARGET+)"
swiftc \
  -O \
  -target "${ARCH}-apple-macos${DEPLOY_TARGET}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreGraphics \
  Sources/*.swift \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME"

cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "==> 本地签名(未签名的 app 在部分系统上拿不到菜单栏图标)"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "    (签名跳过,不影响本机使用)"

echo "==> 完成:$APP_DIR"
"$APP_DIR/Contents/MacOS/$APP_NAME" version
