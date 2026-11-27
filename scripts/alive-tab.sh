#!/bin/bash
# 查一个 iTerm2 标签页还在不在（标识由 open-tab.sh 启动时打印）。
# 用法：alive-tab.sh <会话标识>      退出码 0 = 还在；1 = 已经不在；2 = 查不了（调用方当成还在）
set -uo pipefail
[ $# -eq 1 ] || { echo "用法：$0 <iTerm2 会话标识>" >&2; exit 2; }
# iTerm2 没有运行时不去问它（问了会把它启动起来）：标签页自然不在
run=$(osascript -e 'application "iTerm2" is running' 2>/dev/null) || exit 2
[ "${run}" = true ] || { echo "iTerm2 没有在运行：$1"; exit 1; }
out=$(osascript - "$1" <<'APPLESCRIPT'
on run argv
  set target to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if (unique id of s) is target then return "alive"
        end repeat
      end repeat
    end repeat
  end tell
  return "not-found"
end run
APPLESCRIPT
) || exit 2
case ${out} in alive) echo "还在：$1" ;; not-found) echo "找不到这个标签页：$1"; exit 1 ;; *) exit 2 ;; esac
