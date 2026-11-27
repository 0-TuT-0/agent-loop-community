#!/bin/bash
# 在当前 iTerm2 窗口新开一个标签页，在指定目录交互式启动一个 CLI，并把提示文件内容作为最后一个参数传入。
# 用法：open-tab.sh <工作目录> <提示文件> <命令> [参数...]
# 例：  open-tab.sh /path/to/wt /tmp/p3-05.prompt codex -m gpt-6.2-sol -c model_reasoning_effort="medium" -s danger-full-access
#       open-tab.sh /path/to/wt /tmp/p3-03.prompt claude --model claude-fable-5-2 --permission-mode plan
# 提示文件写 - 时不传提示（用于恢复已有会话）。
# 提示写在文件里，避免长文本和引号在 AppleScript / shell 之间转义出错。
# 输出里有一行「window-id: <标识>」，记下来可以用 close-tab.sh 关闭这个标签页。
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "用法：$0 <工作目录> <提示文件> <命令> [参数...]" >&2
  exit 1
fi

workdir=$1
prompt_file=$2
shift 2

[ -d "$workdir" ] || { echo "工作目录不存在：$workdir" >&2; exit 1; }
[ "$prompt_file" = - ] || [ -f "$prompt_file" ] || { echo "提示文件不存在：$prompt_file" >&2; exit 1; }

launcher_dir="${TMPDIR:-/tmp}/agent-loop"
mkdir -p "$launcher_dir"
# iTerm2 按空格切分 command 字符串，启动文件路径里不能有空格
launcher="$launcher_dir/$(basename "$workdir" | tr -c 'A-Za-z0-9._-\n' '_')-$(date +%Y%m%d%H%M%S).command"
case $launcher in *" "*) echo "启动文件路径含空格，请设置不含空格的 TMPDIR：$launcher" >&2; exit 1 ;; esac

{
  echo '#!/bin/bash -l'
  printf 'cd %q || exit 1\n' "$workdir"
  # 用登录 shell 的 PATH 解析命令
  printf ' %q' "$@"
  if [ "$prompt_file" = - ]; then printf '\n'; else printf ' "$(cat %q)"\n' "$prompt_file"; fi
  # 正常退出时标签页随之关闭；启动失败或异常退出时留下标签页，便于看到报错
  printf 'rc=$?; if [ $rc -ne 0 ]; then echo "窗口异常退出，退出码 $rc"; exec "${SHELL:-/bin/bash}" -l; fi\n'

} > "$launcher"
chmod +x "$launcher"

sid=$(osascript - "$launcher" <<'APPLESCRIPT'
on run argv
  set launcherPath to item 1 of argv
  tell application "iTerm2"
    if (count of windows) = 0 then
      set w to (create window with default profile command launcherPath)
      return unique id of current session of current tab of w
    else
      tell current window
        set t to (create tab with default profile command launcherPath)
        return unique id of current session of t
      end tell
    end if
  end tell
end run
APPLESCRIPT
) || { echo "iTerm2 开标签页失败" >&2; exit 1; }

echo "已在 iTerm2 新标签页启动：$launcher"
# 这一行供总控记录：自动关窗时用 close-tab.sh <标识> 关闭这个标签页
echo "window-id: $sid"
