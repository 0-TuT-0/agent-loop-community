#!/bin/bash
# 总控的唯一唤醒源：只报告「还没处理过」的事件，报告后退出。等待期间只是 shell 循环，不调用模型。
# 由 Monitor 工具或后台 Bash 运行。
#
# 用法：
#   watch.sh [-i 间隔秒数] [-t 超时秒数] -s <已处理事件文件> <目标>...
#   watch.sh -s <已处理事件文件> --ack <事件键>...      处理完一个事件后登记，以后不再报告
#
# 目标：
#   <票文件>[@<pid文件>]   票头 Run（旧票没有 Run 时读 Status）变为 needs-decision / done / plan-review 时报告；
#                          给了 pid 文件、进程已退出、Run 又不是 done / plan-review / 终态时报告 exited；
#                          Run 为 claimed / planning 且超过 Deadline 时报告 overdue。
#                          Run 未到终态、Status 里却出现 done / needs-decision / plan-review（worker 按别的协议写错了字段）时报告 status-mismatch。
#   <产物文件>::<Run-id>   产物最后一个非空行等于「LOOP-DONE <Run-id>」时报告 artifact-done。
#
# 输出：每个新事件一行「<事件>\t<文件>\t<事件键>」，退出码 0；超时打印 TIMEOUT，退出码 2。
# 事件键包含 Run-id（以及裁决序号或期限），所以同一事件重挂监视不会再次报告，新的裁决、新的运行仍会报告。
set -uo pipefail

interval=30 timeout=1800 seen= ack=0
while [ $# -gt 0 ]; do
  case $1 in
    -i) interval=$2; shift 2 ;;
    -t) timeout=$2; shift 2 ;;
    -s) seen=$2; shift 2 ;;
    --ack) ack=1; shift ;;
    --) shift; break ;;
    -*) echo "未知参数：$1" >&2; exit 1 ;;
    *) break ;;
  esac
done
[ -n "$seen" ] || { echo "必须用 -s 指定已处理事件文件" >&2; exit 1; }
mkdir -p "$(dirname "$seen")"; touch "$seen"

if [ $ack -eq 1 ]; then
  for k in "$@"; do grep -qxF -- "$k" "$seen" || printf '%s\n' "$k" >> "$seen"; done
  exit 0
fi
[ $# -gt 0 ] || { echo "至少给一个目标" >&2; exit 1; }

field() { # field <文件> <字段名>：取票头第一处该字段的值（兼容 **字段:** 写法）
  grep -m1 -E "^\**$2:?\**:?[[:space:]]" "$1" 2>/dev/null | sed -E "s/^\**$2:?\**:?[[:space:]]*//"
}
to_epoch() {
  date -j -f "%Y-%m-%dT%H:%M" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || true
}
last_line() { awk 'NF{l=$0} END{print l}' "$1" 2>/dev/null | sed -E 's/[[:space:]]+$//'; }

deadline_watch=$(( $(date +%s) + timeout ))
while :; do
  now=$(date +%s)
  out=()
  emit() { # emit <事件> <文件> <键>
    grep -qxF -- "$3" "$seen" || out+=("$1"$'\t'"$2"$'\t'"$3")
  }
  for target in "$@"; do
    if [[ $target == *"::"* ]]; then
      file=${target%%::*}; rid=${target#*::}
      [ -f "$file" ] && [ "$(last_line "$file")" = "LOOP-DONE $rid" ] && emit artifact-done "$file" "$file|$rid|LOOP-DONE"
      continue
    fi
    file=${target%@*}; pidfile=
    [[ $target == *"@"* ]] && pidfile=${target##*@}
    [ -f "$file" ] || { emit missing "$file" "$file|missing"; continue; }
    run=$(field "$file" Run | awk '{print $1}')
    [ -n "$run" ] || run=$(field "$file" Status | awk '{print $1}')
    rid=$(field "$file" Run-id | awk '{print $1}'); rid=${rid:-norun}
    st=$(field "$file" Status | awk '{print $1}')
    if [ -n "$(field "$file" Run)" ]; then
      case $run in dispatched|claimed|planning)
        case $st in done|needs-decision|plan-review) emit status-mismatch "$file" "$file|$rid|status-mismatch|$st" ;; esac ;;
      esac
    fi
    case $run in
      needs-decision)
        n=$(grep -cE '^### 待裁决' "$file")
        emit needs-decision "$file" "$file|$rid|needs-decision|$n"; continue ;;
      done|plan-review) emit "$run" "$file" "$file|$rid|$run"; continue ;;
      accepted|merged|abandoned|paused|idle) continue ;;
    esac
    if [ -n "$pidfile" ]; then
      pid=$(cat "$pidfile" 2>/dev/null || true)
      if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        emit exited "$file" "$file|$rid|exited"; continue
      fi
    fi
    if [ "$run" = claimed ] || [ "$run" = planning ]; then
      dl=$(field "$file" Deadline | awk '{print $1}')
      if [ -n "$dl" ]; then
        e=$(to_epoch "$dl")
        [ -n "$e" ] && [ "$now" -ge "$e" ] && emit overdue "$file" "$file|$rid|overdue|$dl"
      fi
    fi
  done
  if [ ${#out[@]} -gt 0 ]; then
    printf '%s\n' "${out[@]}"
    exit 0
  fi
  if [ "$now" -ge "$deadline_watch" ]; then
    echo "TIMEOUT"
    exit 2
  fi
  sleep "$interval"
done
