#!/bin/bash
# 启动一个 worker，并把它的 pid 写入 pid 文件（watch.sh 据此判断 worker 是否还在运行）。
# 用法：
#   launch.sh --dir <工作目录> --prompt <提示文件> --pid <pid文件> \
#             [--mode tab|background] [--prompt-mode arg|stdin|file] [--log <日志文件>] -- <启动命令> [参数...]
# --mode tab（默认）：在 iTerm2 新标签页交互式运行。
# --mode background：后台无交互运行，输出写入 --log（默认与 pid 文件同目录的 worker.log）。
# --prompt-mode arg（默认）：提示内容作为最后一个参数；stdin：从标准输入传入；
#                file：启动命令里的 {prompt_file} 替换为提示文件路径（命令里必须有这个占位符）。
#   --stdin 等同于 --prompt-mode stdin（兼容旧用法）。
# pid 文件已存在且进程仍在运行时拒绝启动（退出码 6），避免同一次运行被启动两次。
set -euo pipefail

dir= prompt= pidfile= mode=tab log= pmode=arg
while [ $# -gt 0 ]; do
  case $1 in
    --dir) dir=$2; shift 2 ;;
    --prompt) prompt=$2; shift 2 ;;
    --pid) pidfile=$2; shift 2 ;;
    --mode) mode=$2; shift 2 ;;
    --log) log=$2; shift 2 ;;
    --stdin) pmode=stdin; shift ;;
    --prompt-mode) pmode=$2; shift 2 ;;
    --) shift; break ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
done
[ $# -gt 0 ] || { echo "缺少 -- 之后的启动命令" >&2; exit 1; }
[ -d "$dir" ] || { echo "工作目录不存在：$dir" >&2; exit 1; }
[ -f "$prompt" ] || { echo "提示文件不存在：$prompt" >&2; exit 1; }
[ -n "$pidfile" ] || { echo "缺少 --pid" >&2; exit 1; }
if [ -s "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  echo "pid 文件 ${pidfile} 对应的进程仍在运行，拒绝重复启动" >&2; exit 6
fi
rm -f "$pidfile"
mkdir -p "$(dirname "$pidfile")"
if printf '%s\n' "$@" | grep -v '{prompt_file}' | grep -qE '\{[a-z_]+\}'; then
  echo "启动命令里还有没替换的占位符（例如 {model}、{effort}）：$*" >&2; exit 1
fi
case $pmode in
  arg|stdin) ;;
  file) printf '%s\n' "$@" | grep -qF '{prompt_file}' || { echo "--prompt-mode file 要求启动命令里有 {prompt_file} 占位符" >&2; exit 1; } ;;
  *) echo "未知 --prompt-mode：${pmode}" >&2; exit 1 ;;
esac

# 生成启动文件：先记录自身 pid，再 exec 成 worker（exec 后 pid 不变）
launcher_dir="${TMPDIR:-/tmp}/agent-loop"
mkdir -p "$launcher_dir"
launcher="$launcher_dir/$(basename "$dir" | tr -c 'A-Za-z0-9._-\n' '_')-$(date +%Y%m%d%H%M%S).command"
case $launcher in *" "*) echo "启动文件路径含空格，请设置不含空格的 TMPDIR：$launcher" >&2; exit 1 ;; esac
{
  echo '#!/bin/bash'
  printf 'cd %q || exit 1\n' "$dir"
  printf 'echo $$ > %q\n' "$pidfile"
  printf 'exec'
  for a in "$@"; do
    if [ "$pmode" = file ]; then a=${a//\{prompt_file\}/$prompt}; fi
    printf ' %q' "$a"
  done
  case $pmode in
    stdin) printf ' < %q\n' "$prompt" ;;
    arg) printf ' "$(cat %q)"\n' "$prompt" ;;
    file) printf '\n' ;;
  esac
} > "$launcher"
chmod +x "$launcher"

case $mode in
  tab)
    osascript - "$launcher" <<'APPLESCRIPT'
on run argv
  set launcherPath to item 1 of argv
  tell application "iTerm2"
    if (count of windows) = 0 then
      create window with default profile command launcherPath
    else
      tell current window to create tab with default profile command launcherPath
    end if
  end tell
end run
APPLESCRIPT
    ;;
  background)
    log=${log:-$(dirname "$pidfile")/worker.log}
    nohup "$launcher" > "$log" 2>&1 < /dev/null &
    ;;
  *) echo "未知 --mode：$mode" >&2; exit 1 ;;
esac

# 等 pid 文件出现（最多 15 秒）
for _ in $(seq 1 30); do
  [ -s "$pidfile" ] && break
  sleep 0.5
done
if [ -s "$pidfile" ]; then
  echo "已启动 worker：pid $(cat "$pidfile")，启动文件 $launcher${log:+，日志 $log}"
else
  echo "警告：15 秒内没有生成 pid 文件 ${pidfile}，请检查启动文件 $launcher" >&2
  exit 3
fi
