#!/bin/bash
# 停服务、注销开机自启、把程序移到废纸篓(可恢复)。配置和历史记录保留。
set -euo pipefail

LABEL="com.shoulderbreak.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DEST_APP="$HOME/Applications/ShoulderBreak.app"
BIN_LINK="$HOME/.local/bin/shoulder-break"

echo "==> 停服务"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
pkill -f "ShoulderBreak run" 2>/dev/null || true
sleep 1

if [ -f "$PLIST" ]; then unlink "$PLIST"; echo "==> 已移除开机自启配置"; fi
if [ -L "$BIN_LINK" ]; then unlink "$BIN_LINK"; echo "==> 已移除命令行软链"; fi
if [ -d "$DEST_APP" ]; then
	osascript -e "tell application \"Finder\" to delete POSIX file \"$DEST_APP\"" >/dev/null 2>&1 \
		&& echo "==> 程序已移到废纸篓(需要时可以还原)" \
		|| echo "==> 移废纸篓失败,请手动删除 $DEST_APP"
fi

echo ""
echo "已卸载。配置和历史记录还留着:"
echo "  $HOME/.config/shoulder-break/"
echo "  $HOME/.local/state/shoulder-break/"
