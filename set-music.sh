#!/bin/bash
# 换背景音乐:./set-music.sh <音频文件路径>
# 不带参数就列出 ~/Music/ShoulderBreak 里现有的曲子
set -euo pipefail
CONFIG="$HOME/.config/shoulder-break/config.json"
DIR="$HOME/Music/ShoulderBreak"

if [ $# -eq 0 ]; then
	echo "现有曲目($DIR):"
	if [ -d "$DIR" ]; then
		for f in "$DIR"/*; do
			[ -f "$f" ] || continue
			d=$(afinfo "$f" 2>/dev/null | awk -F': ' '/estimated duration/{printf "%.0f", $2}')
			echo "  $(basename "$f")  ${d:-?}秒"
		done
	else
		echo "  (还没有,把音频文件放进这个目录即可)"
	fi
	echo ""
	echo "当前使用:$(python3 -c "import json;print(json.load(open('$CONFIG')).get('ambientFile') or '(合成音)')")"
	echo "用法:./set-music.sh <文件路径>"
	echo "      ./set-music.sh off        改回合成的颂钵"
	exit 0
fi

if [ "$1" = "off" ]; then
	python3 - "$CONFIG" <<'PY'
import json, sys, collections
p = sys.argv[1]
c = json.load(open(p), object_pairs_hook=collections.OrderedDict)
c['ambientStyle'] = 'bowl'; c['ambientFile'] = ''
json.dump(c, open(p, 'w'), indent=2, ensure_ascii=False)
print("已改回合成的颂钵")
PY
else
	[ -f "$1" ] || { echo "找不到文件:$1"; exit 1; }
	python3 - "$CONFIG" "$1" <<'PY'
import json, sys, collections, os
p, f = sys.argv[1], os.path.abspath(sys.argv[2])
c = json.load(open(p), object_pairs_hook=collections.OrderedDict)
c['ambientStyle'] = 'file'; c['ambientFile'] = f
json.dump(c, open(p, 'w'), indent=2, ensure_ascii=False)
print("背景音乐已换成:", os.path.basename(f))
PY
fi
shoulder-break reload >/dev/null 2>&1 || true
echo "配置已重新载入,下次黑幕生效"
