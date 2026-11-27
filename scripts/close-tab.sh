#!/bin/bash
# 按 iTerm2 会话标识关闭一个标签页（标识由 open-tab.sh 启动时打印）。里面的进程随之结束。
# 用法：close-tab.sh <会话标识>      退出码 0 = 已关闭；1 = 找不到（多半已经被关掉了）
set -uo pipefail
[ $# -eq 1 ] || { echo "用法：$0 <iTerm2 会话标识>" >&2; exit 2; }
out=$(osascript - "$1" <<'APPLESCRIPT'
on run argv
  set target to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if (unique id of s) is target then
            tell s to close
            return "closed"
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return "not-found"
end run
APPLESCRIPT
)
if [ "${out}" = closed ]; then echo "已关闭：$1"; else echo "找不到这个标签页（可能已经关闭）：$1"; exit 1; fi
