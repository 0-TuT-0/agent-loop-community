# 系统兼容函数：macOS（BSD 工具、bash 3.2）与 Linux / WSL（GNU 工具）的差异集中在这里。
# 其他脚本只调用这些函数，不直接写带系统差异的命令。由 agent-loop 主脚本 source。

# macOS 的 awk 在 UTF-8 locale 下比较中文字符串会把不同的串判为相等，所以 awk 一律按字节比较
awk() { LC_ALL=C command awk "$@"; }

now() { date '+%Y-%m-%d %H:%M'; }
epoch() { date +%s; }

# 文件的修改时间（秒）
mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then stat -f %m "$1"; else stat -c %Y "$1" 2>/dev/null || echo 0; fi
}

# 生成小写的 UUID
new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'
  elif [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid
  else die "生成不了会话 ID：系统里没有 uuidgen。"; fi
}

# 把秒数换成「YYYY-MM-DD HH:MM:SS」（供 find -newermt 用）
epoch_to_stamp() {
  if date -r "$1" '+%Y-%m-%d %H:%M:%S' >/dev/null 2>&1; then date -r "$1" '+%Y-%m-%d %H:%M:%S'
  else date -d "@$1" '+%Y-%m-%d %H:%M:%S'; fi
}

# 把数字写成带单位的短形式：1234 → 1.2k，1234567 → 1.23M
human() {
  awk -v n="${1:-0}" 'BEGIN { if (n >= 1000000) printf "%.2fM", n/1000000; else if (n >= 1000) printf "%.1fk", n/1000; else printf "%d", n }'
}

# 后台常驻运行一条命令，不随当前终端结束
detach() {
  if command -v setsid >/dev/null 2>&1; then setsid nohup "$@" >/dev/null 2>&1 < /dev/null &
  else nohup "$@" >/dev/null 2>&1 < /dev/null & fi
  echo $!
}
