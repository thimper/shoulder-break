#!/bin/bash
# 编译 → 装到 ~/Applications → 建命令行软链 → 注册 launchd 开机自启
# 覆盖安装时旧版本会被移到临时目录(不直接删),需要时还能捞回来。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ShoulderBreak"
LABEL="com.shoulderbreak.agent"
DEST_APP="$HOME/Applications/$APP_NAME.app"
BIN_LINK="$HOME/.local/bin/shoulder-break"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="$HOME/.local/state/shoulder-break"
LOG_FILE="$STATE_DIR/logs/service.log"

./build.sh

echo "==> 停掉可能在跑的旧版本"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
# 1.0.0 之前用过别的服务名,一并清掉,免得两份服务同时跑
for OLD_LABEL in com.mason.shoulder-break; do
	OLD_PLIST="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
	if [ -f "$OLD_PLIST" ]; then
		echo "    清理旧服务 $OLD_LABEL"
		launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || launchctl unload "$OLD_PLIST" 2>/dev/null || true
		unlink "$OLD_PLIST"
	fi
done
pkill -f "$APP_NAME run" 2>/dev/null || true
sleep 1

echo "==> 安装到 $DEST_APP"
mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$STATE_DIR/logs"
if [ -d "$DEST_APP" ]; then
	BACKUP_DIR="$(mktemp -d)"
	mv "$DEST_APP" "$BACKUP_DIR/$APP_NAME.app"
	echo "    旧版本已移到 $BACKUP_DIR(重启后系统会自动清理)"
fi
cp -R "build/$APP_NAME.app" "$DEST_APP"

echo "==> 建命令行软链 $BIN_LINK"
ln -sf "$DEST_APP/Contents/MacOS/$APP_NAME" "$BIN_LINK"

echo "==> 写 launchd 配置 $PLIST"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>

	<key>ProgramArguments</key>
	<array>
		<string>$DEST_APP/Contents/MacOS/$APP_NAME</string>
		<string>run</string>
	</array>

	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
		<key>HOME</key>
		<string>$HOME</string>
	</dict>

	<key>RunAtLoad</key>
	<true/>

	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>

	<key>ThrottleInterval</key>
	<integer>5</integer>

	<key>StandardOutPath</key>
	<string>$LOG_FILE</string>
	<key>StandardErrorPath</key>
	<string>$LOG_FILE</string>
</dict>
</plist>
PLISTEOF

echo "==> 启动服务"
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST"
sleep 2

if pgrep -f "$APP_NAME run" > /dev/null; then
	echo ""
	echo "安装完成,服务已在运行。菜单栏右上角会出现一个小人图标。"
	echo ""
	"$BIN_LINK" status
	echo ""
	echo "常用命令:"
	echo "  shoulder-break status   查看下次提醒时间和统计"
	echo "  shoulder-break now      立刻做一次"
	echo "  shoulder-break pause    暂停 1 小时"
	echo "  shoulder-break panic    紧急解除黑幕"
	echo "  配置文件:$HOME/.config/shoulder-break/config.json"
else
	echo "服务没能起来,看日志:$LOG_FILE"
	tail -20 "$LOG_FILE" 2>/dev/null || true
	exit 1
fi
