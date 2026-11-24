#!/bin/bash
# 汇总票目录中每张票的状态和「能否派工」，供选票、开窗清单和恢复核对共用（同一份就绪判定）。
# 用法：loop-state.sh <票目录> [可派工的分诊状态，逗号分隔；默认 ready-for-agent]
# 输出（制表符分隔）：
#   id  status(分诊)  run  risk  deliverable  depends  dispatchable  reason  worker  deadline
#   dispatchable=yes 时 reason 为空；否则 reason 写明原因（例如 dep:03=claimed、unknown-dep:x9、external:X1、triage:needs-info）。
#   worker：alive / dead / -
# 发布关口：票头有 Kind: release 的票，会被票目录中任何一张票上 pending 且 blocks 含 release 的外部前置阻塞
#   （reason 写 release-gate:<外部ID>@<票ID>）。
set -uo pipefail

dir=${1:?用法：$0 <票目录> [可派工的分诊状态]}
allowed=",${2:-ready-for-agent},"
[ -d "$dir" ] || { echo "票目录不存在：$dir" >&2; exit 1; }

field() { grep -m1 -E "^\**$2:?\**:?[[:space:]]" "$1" 2>/dev/null | sed -E "s/^\**$2:?\**:?[[:space:]]*//"; }
run_of() { # 旧票没有 Run 时，从 Status 映射
  local r s
  r=$(field "$1" Run | awk '{print $1}')
  if [ -z "$r" ]; then
    s=$(field "$1" Status | awk '{print $1}')
    case $s in
      claimed|planning|needs-decision|plan-review|done|abandoned) r=$s ;;
      merged) r=accepted ;;
      *) r=idle ;;
    esac
  fi
  echo "$r"
}
parse_deps() { # 把依赖文本解析成 ID 列表（每行一个），兼容带注释的自由文本：
  # 以「无」「none」开头 → 没有依赖；去掉（…）(...) 和 `…` 中的注释；按逗号、顿号、分号、空白切分；
  # 「01–20」「01~20」展开为范围；ID 后面直接跟着的说明文字被截掉；以非 ASCII 开头的词视为说明文字。
  # 剩下的 ASCII 词如果对不上任何票，照样报 unknown-dep，提示拆票窗口按 templates/ticket.md 规范化。
  local raw=$1 t a b w i
  case $raw in 无*|none*|None*|-|"") return 0 ;; esac
  raw=$(printf '%s' "$raw" | perl -Mutf8 -CSD -pe 's/（[^）]*）//g; s/\([^)]*\)//g; s/`[^`]*`//g; s/[，、；;,]/ /g')
  for t in $raw; do
    printf '%s' "$t" | grep -q '^[A-Za-z0-9]' || continue   # 以中文等非 ASCII 开头的词是说明文字，跳过
    t=$(printf '%s' "$t" | perl -Mutf8 -CSD -pe 's/^([A-Za-z0-9_.~\x{2013}-]+).*$/$1/')
    if printf '%s' "$t" | grep -qE '^[0-9]+(–|~)[0-9]+$'; then
      a=$(printf '%s' "$t" | sed -E 's/^([0-9]+).*/\1/'); b=$(printf '%s' "$t" | sed -E 's/.*[^0-9]([0-9]+)$/\1/'); w=${#a}
      i=$((10#$a)); while [ $i -le $((10#$b)) ]; do printf "%0${w}d\n" $i; i=$((i+1)); done
    else
      printf '%s\n' "$t"
    fi
  done
}
resolve() { # 按 ID 精确找票：文件名等于 <ID>.md，或者以 <ID>- / <ID>_ 开头；唯一时输出路径
  local hits
  hits=$(ls "$dir/$1.md" "$dir/$1"-*.md "$dir/$1"_*.md 2>/dev/null)
  [ "$(printf '%s\n' "$hits" | grep -c .)" -eq 1 ] && echo "$hits"
}

# 第一遍：收集所有阻塞发布的、未满足的外部前置
gates=""
for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  gid=$(basename "$f" .md)
  while IFS= read -r line; do
    xid=$(echo "$line" | sed -E 's/^\**External-([^:*]+).*/\1/')
    val=$(echo "$line" | sed -E 's/^\**External-[^:]+:?\**:?[[:space:]]*//')
    if echo "$val" | grep -q '^pending' && echo "$val" | grep -qE 'blocks=[^ ]*release'; then gates="$gates release-gate:${xid}@${gid}"; fi
  done < <(grep -E '^\**External-' "$f" 2>/dev/null)
done

printf 'id\tstatus\trun\trisk\tdeliverable\tdepends\tdispatchable\treason\tworker\tdeadline\n'
for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  grep -qE '^\**(Status|Run):?\**:?[[:space:]]' "$f" || continue
  id=$(basename "$f" .md)
  status=$(field "$f" Status | awk '{print $1}')
  run=$(run_of "$f")
  deps=$(field "$f" Depends); [ -n "$deps" ] || deps=$(field "$f" "Blocked by")
  reasons=()

  [ "$run" = idle ] || reasons+=("run:$run")
  if [ -n "$status" ] && [[ $allowed != *",$status,"* ]]; then
    # 旧票把运行状态写在 Status 里，这些值已由 run_of 映射，不算分诊阻塞
    case $status in claimed|planning|needs-decision|plan-review|done|merged|abandoned|ready) ;; *) reasons+=("triage:$status") ;; esac
  fi
  if [ -n "$deps" ]; then
    for d in $(parse_deps "$deps"); do
      df=$(resolve "$d")
      if [ -z "$df" ]; then reasons+=("unknown-dep:$d"); continue; fi
      dr=$(run_of "$df"); [ "$dr" = accepted ] || reasons+=("dep:$d=$dr")
    done
  fi
  while IFS= read -r line; do
    xid=$(echo "$line" | sed -E 's/^\**External-([^:*]+).*/\1/')
    val=$(echo "$line" | sed -E 's/^\**External-[^:]+:?\**:?[[:space:]]*//')
    if echo "$val" | grep -q '^pending' && echo "$val" | grep -qE 'blocks=[^ ]*dispatch'; then reasons+=("external:$xid"); fi
  done < <(grep -E '^\**External-' "$f" 2>/dev/null)

  if [ "$(field "$f" Kind | awk '{print $1}')" = release ]; then
    for g in $gates; do reasons+=("$g"); done
  fi

  worker=-
  pidfile=$(field "$f" Worker | sed -E 's/[[:space:]]+(session|会话).*$//')
  if [ -n "$pidfile" ] && [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then worker=alive; else worker=dead; fi
  fi
  if [ ${#reasons[@]} -eq 0 ]; then disp=yes reason=; else disp=no; reason=$(IFS=';'; echo "${reasons[*]}"); fi
  risk=$(field "$f" Risk | awk '{print $1}'); dlv=$(field "$f" Deliverable | awk '{print $1}'); dl=$(field "$f" Deadline | awk '{print $1}')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${status:--}" "$run" "${risk:--}" "${dlv:--}" \
    "$(echo "${deps:--}" | tr -d ' ')" "$disp" "${reason:--}" "$worker" "${dl:--}"
done
