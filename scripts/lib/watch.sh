# 监视：检测功能目录里的变化（票头状态、完成标记、可选窗口留的事、迟迟没被接收的裁决、开了窗却没开始的窗口），把它告诉总控。
# 两种总控共用这一份，区别只在最后一步怎么送达：
#   Codex 总控：agent-loop watch restart  常驻进程，用 codex queue 给总控发消息（Codex 不能自己挂后台任务再被唤醒）
#   Claude 总控：agent-loop watch wait    挂成后台任务，有变化就打印并退出，后台任务结束会唤醒总控
# 总控启动、恢复、接手时一律重启监视（Codex：watch restart；Claude：watch wait --restart）：上一个总控留下的监视
# 可能指向旧会话、用的是旧代码，或者是另一种送达方式。重启只换进程，状态文件保留
# 由 agent-loop 主脚本 source。状态文件在 <功能目录>/ledger/：
#   watch.state   已经通知过的状态：<文件>\t<状态或标记>；hello::<窗口编号>\tseen = 这个窗口没签到的事已经通知过
#   watch.pending.issues、watch.pending.profile   已经通知过的可选窗口留言（所在小节的标题加内容）
#   expect.tsv    裁决送出后等待接收：<票文件>\t<裁决编号>\t<送出秒数>
#   watch.log     通知记录
#   coordinator   Codex 总控：<命令行>|<会话ID>
#   watch.pid、watch.lock（Codex 的常驻进程）、watch.wait.lock（Claude 的等待）   单实例用

PENDING_MARK='【待总控处理】'
watch_status_of() {
  grep -m1 -E '^\**Status:?\**:?' "$1" 2>/dev/null | sed -E 's/^\**Status:?\**:?[[:space:]]*//' | awk '{print $1}'
}
# 返工：让窗口重改一份已经通知过完成标记的文件时，把它的状态记成「redo:<当时的校验和>」。
# 之后文件内容变了、末尾又有完成标记，才再通知一次（见 agent-loop send --redo）。
# 票也一样：票头已经是 done 的票登记返工后，内容变了、票头又是 done，再通知一次
watch_sum() { cksum < "$1" | awk '{print $1}'; }
watch_redo() {
  touch "${LD}/watch.state"
  awk -F'\t' -v OFS='\t' -v f="$1" -v p="$1::" -v v="redo:$(watch_sum "$1")" 'index($1, p) == 1 || $1 == f { $2 = v } { print }' "${LD}/watch.state" > "${LD}/watch.state.n.$$"
  mv "${LD}/watch.state.n.$$" "${LD}/watch.state"
}
# 这个完成标记要不要通知：没通知过的要；返工中的，文件内容变了才要
watch_marker_due() {
  v=$(watch_state_get "$1")
  case ${v} in "") return 0 ;; redo:*) [ "${v#redo:}" != "$(watch_sum "$2")" ] ;; *) return 1 ;; esac
}
watch_state_get() { awk -F'\t' -v f="$1" '$1==f {print $2; exit}' "${LD}/watch.state" 2>/dev/null; }
watch_state_set() {
  touch "${LD}/watch.state"
  awk -F'\t' -v f="$1" '$1!=f' "${LD}/watch.state" > "${LD}/watch.state.n.$$"
  printf '%s\t%s\n' "$1" "$2" >> "${LD}/watch.state.n.$$"; mv "${LD}/watch.state.n.$$" "${LD}/watch.state"
}
# 发通知；WATCH_BASELINE=1 时只记状态不发（第一次启动时把现状记成已知）
# 一轮检查里最多逐条发 WATCH_MAX 条。超过说明多半出了问题（状态文件丢了、一次改了很多文件），
# 剩下的只记状态不发，这一轮结束时合成一条提醒，免得把总控的队列塞满。
# 发送失败之后这一轮不再尝试，状态不更新，下一轮重试。
watch_notify() {
  [ -z "${WATCH_BASELINE:-}" ] || return 0
  [ -z "${WATCH_FAILED:-}" ] || return 1
  if [ "${WATCH_SENT:-0}" -ge "${WATCH_MAX:-8}" ]; then WATCH_SUPPRESSED=$(( ${WATCH_SUPPRESSED:-0} + 1 )); return 0; fi
  WATCH_SENT=$(( ${WATCH_SENT:-0} + 1 ))
  watch_send "$1"
}
watch_send() {
  msg="[agent-loop 监视] $1"
  # 怎么把话送到总控：Claude 的等待是打印后退出；Codex 的常驻进程用 codex queue
  if [ "${WATCH_DELIVER:-}" = print ]; then echo "${msg}"; rc=0
  elif [ -n "${AGENT_LOOP_NOTIFY_CMD:-}" ]; then ${AGENT_LOOP_NOTIFY_CMD} "${msg}"; rc=$?
  else watch_deliver_codex "${msg}" "$1"; rc=$?; fi
  echo "$(now) $( [ ${rc} -eq 0 ] && echo 已通知 || echo 通知失败，这一轮不再发送，下一轮重试 )：$1" >> "${LD}/watch.log"
  [ ${rc} -eq 0 ] || WATCH_FAILED=1
  return ${rc}
}
# 第一次用：把现状记成已知，不为已经发生过的事补发通知
watch_baseline_once() { [ -f "${LD}/watch.state" ] || { WATCH_BASELINE=1 watch_pass; touch "${LD}/watch.state"; }; }
# 检查一遍：票头状态、完成标记、等待接收的裁决
watch_pass() {
  WATCH_SENT=0; WATCH_SUPPRESSED=0; WATCH_FAILED=""
  for f in "${FD}"/*/issues/*.md; do
    [ -f "${f}" ] || continue
    s=$(watch_status_of "${f}"); [ -n "${s}" ] || continue
    ws=$(watch_state_get "${f}")
    [ "${s}" = "${ws}" ] && continue
    case ${ws} in redo:*)
      if [ "${s}" = done ]; then
        [ "${ws#redo:}" != "$(watch_sum "${f}")" ] || continue
        watch_notify "${f#"${FD}"/} 的票头变为 done（返工后）" && watch_state_set "${f}" done
        continue
      fi ;;
    esac
    case ${s} in
      needs-decision|done|plan-approved) watch_notify "${f#"${FD}"/} 的票头变为 ${s}" && watch_state_set "${f}" "${s}" ;;
      *) watch_state_set "${f}" "${s}" ;;
    esac
  done
  # 完成标记写在产物的末尾
  for pair in "*/spec.md::spec 已审定" "*/tickets-common.md::拆票完成" "*/reviews/*.md::审计完成" \
              "regression/*-prereq.md::前提清单已写完" "regression/*.md::已完成" "*/reviews/local-test-plan.md::已完成" \
              "merges/*.md::合并完成" "merges/*.md::合并停止"; do
    glob=${pair%%::*}; marker=${pair#*::}
    for f in "${FD}"/${glob}; do
      [ -f "${f}" ] || continue
      case ${f} in */regression/*-result.md) continue ;; esac   # 回归结果按轮通知，见下
      key="${f}::${marker}"
      tail -n 5 "${f}" | grep -qF -- "${marker}" || continue
      watch_marker_due "${key}" "${f}" || continue
      watch_notify "${f#"${FD}"/} 出现完成标记「${marker}」" && watch_state_set "${key}" seen
    done
  done
  # 回归结果：每一轮做完，执行窗口在末尾写一行「第 N 轮已完成」。按这一行的内容记状态，所以每一轮各通知一次
  for f in "${FD}"/regression/*-result.md; do
    [ -f "${f}" ] || continue
    last=$(awk 'NF { l = $0 } END { gsub(/^[ \t]+|[ \t]+$/, "", l); print l }' "${f}")
    case ${last} in 第*轮已完成) ;; *) continue ;; esac
    key="${f}::${last}"
    watch_marker_due "${key}" "${f}" || continue
    watch_notify "${f#"${FD}"/} 出现完成标记「${last}」，运行 agent-loop regress 收口" && watch_state_set "${key}" seen
  done
  # 可选窗口留给总控的事：问题记录和参数文件里标着「待总控处理」的条目。
  # 按具体条目比对：出现了上次没有的条目就通知；总控处理后把标记改掉，条目随之消失。
  # 条目用「所在小节的标题加这一行的内容」来认，不带行号：前面插入或删掉别的内容不会让旧条目被当成新的
  for pair in "issues::${FD}/regression/issues-log.md" "profile::${REPO}/${PROFILE_REL}"; do
    tag=${pair%%::*}; f=${pair#*::}; seen="${LD}/watch.pending.${tag}"
    [ -f "${f}" ] || continue
    awk -v m="${PENDING_MARK}" '/^#/ { h = $0 } index($0, m) { print h "\t" $0 }' "${f}" > "${seen}.now"; touch "${seen}"
    if [ -s "${seen}.now" ] && grep -vxFf "${seen}" "${seen}.now" >/dev/null 2>&1; then
      case ${f} in "${FD}"/*) rel=${f#"${FD}"/} ;; *) rel=${f#"${REPO}"/} ;; esac
      watch_notify "${rel} 里有 $(grep -c . "${seen}.now") 条标着「待总控处理」的条目（可选窗口留的）。读完处理后，把标记改成「总控已处理」并写明时间和结果" && mv "${seen}.now" "${seen}"
    else
      mv "${seen}.now" "${seen}"
    fi
  done
  # 裁决送出后迟迟没被接收：票头还是 needs-decision
  if [ -s "${LD}/expect.tsv" ]; then
    lim=${AGENT_LOOP_EXPECT_SECS:-300}; nowe=$(epoch); : > "${LD}/expect.n.$$"
    while IFS="${TAB}" read -r f n e; do
      [ -n "${f}" ] || continue
      [ "$(watch_status_of "${f}")" = needs-decision ] || continue
      if [ $(( nowe - e )) -ge "${lim}" ]; then
        watch_notify "裁决 ${n} 未被接收：${f#"${FD}"/} 的票头仍是 needs-decision（已等 $(( (nowe - e) / 60 )) 分钟）。请重送一次；重送后仍未接收时，请告诉用户在那个窗口说「继续」" \
          || printf '%s\t%s\t%s\n' "${f}" "${n}" "${e}" >> "${LD}/expect.n.$$"
      else
        printf '%s\t%s\t%s\n' "${f}" "${n}" "${e}" >> "${LD}/expect.n.$$"
      fi
    done < "${LD}/expect.tsv"
    mv "${LD}/expect.n.$$" "${LD}/expect.tsv"
  fi
  # 开了窗却迟迟没有开始：窗口启动后第一件事是签到（agent-loop window hello）。到点没签到就告诉总控一次。
  # Claude 窗口另认一种证据：会话记录已经出现（计划模式的窗口不能执行命令，签不了到）
  hlim=${AGENT_LOOP_HELLO_SECS:-180}
  awk -F'\t' -v n="$(epoch)" -v lim="${hlim}" '$13 == "-" && $14 == "-" && $6 != "coordinator" && n - $3 >= lim { print $1 "\t" int((n - $3) / 60) }' "${WIN}" 2>/dev/null > "${LD}/hello.n.$$"
  while IFS="${TAB}" read -r hw hm; do
    [ -n "${hw}" ] || continue
    [ -z "$(watch_state_get "hello::${hw}")" ] || continue
    if [ "$(win_get "${hw}" 8)" = claude ] && ls "${HOME}"/.claude/projects/*/"$(win_get "${hw}" 10)".jsonl >/dev/null 2>&1; then win_set "${hw}" 14 "$(now)"; continue; fi
    ht=$(win_get "${hw}" 5); hp=$(win_get "${hw}" 15)
    watch_notify "${hw}（$(win_get "${hw}" 6)$( [ "${ht}" = - ] || echo "，票 ${ht}" )）开窗已 ${hm} 分钟还没有开始。运行 agent-loop window list 看它的标签页还在不在：不在会登记为关闭，重开即可；还在，多半停在启动时的提示上，请告诉用户去那个窗口看一眼，过了提示之后对它说：读 ${hp:-初始提示文件} 并照做" \
      && watch_state_set "hello::${hw}" seen
  done < "${LD}/hello.n.$$"
  rm -f "${LD}/hello.n.$$"
  if [ "${WATCH_SUPPRESSED}" -gt 0 ] && [ -z "${WATCH_FAILED}" ]; then
    watch_send "这一轮检查到的变化很多，另有 ${WATCH_SUPPRESSED} 项没有逐条通知。请自己把全部票的票头和各个产物的完成标记看一遍，按现状处理"
  fi
}

cmd_watch() {
  need_profile
  act=${1:-status}; [ $# -gt 0 ] && shift
  feat=""; thread=""; interval=""; timeout=""; a1=""; a2=""; restart=no
  while [ $# -gt 0 ]; do
    case $1 in
      --feature) feat=${2:-}; shift ;; --thread) thread=${2:-}; shift ;; --interval) interval=${2:-}; shift ;;
      --timeout) timeout=${2:-}; shift ;;
      --stop) act=stop ;; --restart) restart=yes ;;
      -*) die "未知参数：$1" ;;
      *) if [ -z "${a1}" ]; then a1=$1; else a2=$1; fi ;;
    esac
    shift
  done
  need_feature "${feat}"; ledger_init
  case ${act} in
    # 两种总控通用
    once) watch_pass; echo "已检查一遍。" ;;
    expect)
      [ -n "${a1}" ] && [ -n "${a2}" ] || die "用法：agent-loop watch expect <票> <裁决编号>"
      f=$(ticket_file "${a1}") || die "找不到 ${a1} 的票文件。"
      printf '%s\t%s\t%s\n' "${f}" "${a2}" "$(epoch)" >> "${LD}/expect.tsv"; echo "已登记：${a1} 的裁决 ${a2} 等待接收。" ;;
    redo)
      [ -n "${a1}" ] || die "用法：agent-loop watch redo <文件或票号>"
      rf=$(watch_resolve_file "${a1}") || die "文件不存在：${a1}"
      watch_redo "${rf}"
      case ${rf} in */issues/*) echo "已登记返工：$(basename "${rf}") 的内容变了、票头又是 done 时，监视会再通知一次。" ;;
        *) echo "已登记返工：$(basename "${rf}") 改完、末尾重新写上完成标记时，监视会再通知一次。请让窗口先删掉末尾的完成标记，全部改完再写回。" ;; esac ;;
    # Claude 总控
    stop)
      watch_stop_all
      if [ "${WATCH_STOPPED}" -gt 0 ]; then echo "监视已停止（${WATCH_STOPPED} 个进程）。已经通知过哪些事的记录保留着，重新启动后不会重报，也不会漏报。"; else echo "监视没有在运行。"; fi ;;
    wait)
      # --restart：总控启动、恢复、接手时用。先停掉这个功能上别的监视（上一个总控留下的），再开始等
      if [ "${restart}" = yes ]; then watch_stop_all; [ "${WATCH_STOPPED}" -eq 0 ] || echo "$(now) 接手：停掉了上一个总控留下的监视（${WATCH_STOPPED} 个进程）" >> "${LD}/watch.log"; fi
      watch_wait "${interval:-30}" "${timeout}" ;;
    restart)
      # Codex 总控启动、恢复、接手时用：停掉别的监视，再启动指向自己的常驻监视
      watch_stop_all; [ "${WATCH_STOPPED}" -eq 0 ] || echo "已停掉原来的监视（${WATCH_STOPPED} 个进程）。"
      cmd_watch_codex start "${interval:-15}" ;;
    # Codex 总控
    start|run|adopt|status) cmd_watch_codex "${act}" "${interval:-15}" ;;
    *) die "用法：agent-loop watch wait [--restart] [--timeout <秒>]          Claude 总控：在后台等，有变化就打印并退出；默认没有时限
      agent-loop watch restart --thread <总控会话ID> | status        Codex 总控：常驻监视
      agent-loop watch stop | once | expect <票> <裁决编号> | redo <文件或票号>   两种总控通用
      总控启动、恢复、接手时一律重启监视：Claude 用 wait --restart，Codex 用 restart
      都可以加 --feature <功能>" ;;
  esac
}
# 停掉这个功能上的所有监视：Codex 的常驻进程和 Claude 的等待都算。只停命令行确实是 agent-loop watch 的进程，
# 免得进程号文件过期后误停别的进程。状态文件（watch.state 等）不动：重新启动后既不重报也不漏报
watch_stop_all() {
  ps_=$( { cat "${LD}/watch.pid" "${LD}/watch.lock/pid" "${LD}/watch.wait.lock/pid" 2>/dev/null; watch_pids; watch_pids wait; } | sort -u )
  WATCH_STOPPED=0; killed=""
  for p in ${ps_}; do
    [ "${p}" != "$$" ] || continue
    ps -p "${p}" -o command= 2>/dev/null | grep -q "agent-loop watch" || continue
    kill "${p}" 2>/dev/null && { WATCH_STOPPED=$((WATCH_STOPPED + 1)); killed="${killed:-} ${p}"; }
  done
  # 等它们真正退出再返回，免得紧接着启动的监视以为旧的还在
  i=0; while [ "${i}" -lt 20 ]; do
    left=0; for p in ${killed:-}; do pid_alive "${p}" && left=1; done
    [ "${left}" -eq 0 ] && break; sleep 0.2; i=$((i+1))
  done
  rm -rf "${LD}/watch.pid" "${LD}/watch.lock" "${LD}/watch.wait.lock"
}
# 把用户给的文件名对到实际的文件：绝对路径、相对功能目录、相对仓库；也可以给票号
watch_resolve_file() {
  for c in "$1" "${FD}/$1" "${REPO}/$1"; do
    [ -f "${c}" ] && { echo "$(cd "$(dirname "${c}")" && pwd -P)/$(basename "${c}")"; return 0; }
  done
  ticket_file "$1"
}

# ---------- 送达方式一：Codex 总控的常驻进程 ----------
watch_deliver_codex() {
  co=$(cat "${LD}/coordinator" 2>/dev/null); id=${co#*|}
  [ -n "${id}" ] || { echo "$(now) 没有登记总控会话，通知没发出：$2" >> "${LD}/watch.log"; return 1; }
  codex queue --thread "${id}" --message "$1" >/dev/null 2>&1
}
# 成为监视进程本身：记下进程号，循环检查
# 一个功能只能有一个监视进程：两个同时跑会互相覆盖状态文件，状态一丢，所有旧事件都会被当成新的重发一遍。
# 用建目录当锁（建目录是原子操作）。进程在不在用 ps 判断，不用 kill -0：有的运行环境不允许给别的进程发信号。
pid_alive() { [ -n "$1" ] && ps -p "$1" -o pid= >/dev/null 2>&1; }
# 这个功能的所有监视进程（按命令行找，不只看进程号文件）
watch_pids() {
  ps -axo pid=,command= | awk -v f="--feature ${FEATURE}" -v me="$$" -v re="agent-loop watch ${1:-(run|adopt)}" '
    $1 != me && $0 ~ re { i = index($0, f); if (i) { c = substr($0, i + length(f), 1); if (c == "" || c == " ") print $1 } }'
}
# 两次检查之间的等待。放到后台再 wait：这样收到停止信号时立刻退出，不用等这一觉睡完
watch_sleep() { sleep "$1" & WATCH_SLP=$!; wait "${WATCH_SLP}" 2>/dev/null; }
watch_loop() {
  if ! mkdir "${LD}/watch.lock" 2>/dev/null; then
    holder=$(cat "${LD}/watch.lock/pid" 2>/dev/null)
    if pid_alive "${holder}" && [ "${holder}" != "$$" ]; then echo "$(now) 已经有监视在运行（进程 ${holder}），进程 $$ 退出" >> "${LD}/watch.log"; exit 0; fi
  fi
  echo $$ > "${LD}/watch.lock/pid"; echo $$ > "${LD}/watch.pid"
  trap 'kill "${WATCH_SLP:-}" 2>/dev/null; rm -rf "${LD}/watch.lock" "${LD}/watch.pid"; exit 0' TERM INT
  watch_baseline_once
  while :; do watch_pass; watch_sleep "$1"; done
}
# Claude 总控的等待是不是挂着
watch_waiting() { pid_alive "$(cat "${LD}/watch.wait.lock/pid" 2>/dev/null)" || [ -n "$(watch_pids wait)" ]; }
watch_alive() { p=$(cat "${LD}/watch.pid" 2>/dev/null); pid_alive "${p}" || [ -n "$(watch_pids)" ]; }

cmd_watch_codex() {
  act=$1; interval=$2
  case ${act} in
    start)
      [ -n "${thread}" ] && echo "codex|${thread}" > "${LD}/coordinator"
      [ -s "${LD}/coordinator" ] || [ -n "${AGENT_LOOP_NOTIFY_CMD:-}" ] || die "要告诉监视把通知发给谁：agent-loop watch start --thread <总控的会话 ID>（Codex 里是 \$CODEX_THREAD_ID）。Claude 总控不用常驻监视，用 agent-loop watch wait。"
      if watch_alive; then echo "监视已经在运行（进程 $(cat "${LD}/watch.pid" 2>/dev/null; watch_pids | tr '\n' ' ')），没有再启动一个。"; return 0; fi
      watch_baseline_once
      p=$(cd "${REPO}" && detach /bin/bash "${SELF}" watch run --feature "${FEATURE}" --interval "${interval}")
      echo "${p}" > "${LD}/watch.pid"
      echo "监视已启动（进程 ${p}），每 ${interval} 秒检查一次 ${FD}。停止：agent-loop watch stop --feature ${FEATURE}" ;;
    run) watch_loop "${interval}" ;;
    adopt)
      # agent-loop start 新开 Codex 总控之后在后台运行：等总控的会话出现，对上会话 ID，然后自己成为监视进程
      [ -n "${a1}" ] || die "用法：agent-loop watch adopt <总控的窗口编号>"
      i=0
      while [ "${i}" -lt 60 ]; do
        win_resolve; sid=$(win_get "${a1}" 10)
        if [ -n "${sid}" ] && [ "${sid}" != - ]; then
          echo "codex|${sid}" > "${LD}/coordinator"
          # 上一个总控留下的监视：停掉，由这个进程接手（状态记录保留）
          watch_stop_all
          watch_loop "${interval}"
        fi
        sleep "${AGENT_LOOP_ADOPT_WAIT:-3}"; i=$((i+1))
      done
      echo "$(now) 没能对上 Codex 总控的会话，监视没有启动。请总控运行 agent-loop watch start --thread <会话ID>" >> "${LD}/watch.log"
      exit 1 ;;
    status)
      if watch_alive; then echo "监视在运行（进程 $(cat "${LD}/watch.pid")），总控：$(cat "${LD}/coordinator" 2>/dev/null)"; else echo "监视没有在运行。启动：agent-loop watch start --thread <总控的会话 ID> --feature ${FEATURE}"; return 1; fi ;;
  esac
}

# ---------- 送达方式二：Claude 总控的后台等待 ----------
# 默认没有时限：没有变化就一直等，不为「没有变化」唤醒总控。按时间提醒的事（裁决没被接收、窗口没签到）在 watch_pass 里自己计时。
# 退出码一律是 0：有变化时每行一条通知；给了 --timeout 而到时限时只打印 TIMEOUT（测试用）。总控处理完之后原样再挂一次，不用列目标
watch_wait() {
  interval=$1; timeout=$2
  if watch_alive; then die "这个功能有 Codex 总控的常驻监视在运行（进程 $(cat "${LD}/watch.pid" 2>/dev/null)）。两种监视共用一份状态，不能同时用；Claude 总控接手时运行 agent-loop watch wait --restart --feature ${FEATURE}。"; fi
  # 同一时刻只留一个在等：再挂一个会让同一件事被报两次
  if ! mkdir "${LD}/watch.wait.lock" 2>/dev/null; then
    holder=$(cat "${LD}/watch.wait.lock/pid" 2>/dev/null)
    if pid_alive "${holder}" && [ "${holder}" != "$$" ]; then echo "已经有一个 agent-loop watch wait 在等（进程 ${holder}），不用再挂。"; return 0; fi
  fi
  echo $$ > "${LD}/watch.wait.lock/pid"
  trap 'rm -rf "${LD}/watch.wait.lock"' EXIT
  trap 'kill "${WATCH_SLP:-}" 2>/dev/null; exit 0' TERM INT
  watch_baseline_once
  started=$(epoch)
  while :; do
    WATCH_DELIVER=print watch_pass
    [ "${WATCH_SENT}" -gt 0 ] && exit 0
    if [ -n "${timeout}" ] && [ $(( $(epoch) - started )) -ge "${timeout}" ]; then echo "TIMEOUT"; exit 0; fi
    watch_sleep "${interval}"
  done
}
