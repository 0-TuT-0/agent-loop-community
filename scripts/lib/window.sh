# 开窗入口：按参数文件「启动器」选用具体系统的开窗脚本，并在开窗时自动登记到票台账。
# 给窗口送消息的命令也在这里。由 agent-loop 主脚本 source。
# 启动器清单在 launchers.conf：编号|开窗脚本|关窗脚本|名称|可用性检查|存活脚本。脚本的约定：
#   <开窗脚本> <工作目录> <提示文件或 -> <命令> [参数...]   输出里有一行「window-id: <标识>」
#   <关窗脚本> <标识>                                        退出码 0 = 已关闭，1 = 找不到
#   <存活脚本> <标识>                                        退出码 0 = 还在，1 = 已经不在，其他 = 查不了
# 这个文件不认识任何具体的系统：脚本、名称、是否可用都从 launchers.conf 读

launcher_line() { grep -v '^#' "${SKILL_DIR}/launchers.conf" | awk -F'|' -v k="${1:-$(getv launcher)}" '$1==k {print; exit}'; }
launcher_ids() { grep -v '^#' "${SKILL_DIR}/launchers.conf" | awk -F'|' 'NF > 1 { printf "%s%s", (n++ ? "," : ""), $1 }'; }
launcher_name() { n=$(field "$(launcher_line "${1:-}")" 4); echo "${n:-${1:-$(getv launcher)}}"; }
# 这个系统上能不能用：清单里「可用性检查」一栏是路径或命令名，存在就算可用
launcher_installed() {
  line=$(launcher_line "${1:-}"); [ -n "${line}" ] || return 1
  c=$(field "${line}" 5); [ -z "${c}" ] || [ -e "${c}" ] || command -v "${c}" >/dev/null 2>&1
}
launcher_script() {  # open | close | alive [启动器编号]
  l=${2:-$(getv launcher)}
  line=$(launcher_line "${l}")
  [ -n "${line}" ] || die "launchers.conf 里没有启动器「${l}」。"
  case $1 in open) ls_n=2 ;; close) ls_n=3 ;; *) ls_n=6 ;; esac
  ls_s=$(field "${line}" "${ls_n}"); [ -n "${ls_s}" ] || return 1
  echo "${SKILL_DIR}/scripts/${ls_s}"
}
# 这个窗口的标签页是不是确定已经不在了。查不了的（手动开的窗口、启动器不可用、脚本出错）一律当成还在
win_gone() {
  g_id=$(win_get "$1" 11); case ${g_id} in ""|-) return 1 ;; esac
  if [ -n "${AGENT_LOOP_ALIVE_CMD:-}" ]; then ${AGENT_LOOP_ALIVE_CMD} "${g_id}" >/dev/null 2>&1; g_rc=$?
  else
    [ -z "${AGENT_LOOP_NO_LAUNCH:-}" ] || return 1
    g_l=$(win_get "$1" 12); case ${g_l} in ""|-) return 1 ;; esac
    launcher_installed "${g_l}" || return 1
    g_s=$(launcher_script alive "${g_l}") || return 1
    "${g_s}" "${g_id}" >/dev/null 2>&1; g_rc=$?
  fi
  [ "${g_rc}" -eq 1 ]
}
win_mark_gone() { win_set "$1" 13 "$(now) 已消失"; }
# 把台账里还开着、标签页却已经不在的窗口登记为关闭，每个打印一行
win_sweep() {
  for sw in $(awk -F'\t' '$13=="-" {print $1}' "${WIN}"); do
    win_gone "${sw}" || continue
    win_mark_gone "${sw}"
    sw_t=$(win_get "${sw}" 5)
    echo "  [已消失] ${sw}（$(win_get "${sw}" 6)$( [ "${sw_t}" = - ] || echo "，票 ${sw_t}" )）的标签页已经不在，已登记为关闭。它的工作没做完时重开：agent-loop window open … --again"
  done
}
launcher_ok() {
  [ -z "${AGENT_LOOP_NO_LAUNCH:-}" ] || return 1
  launcher_installed
}
# 开一个窗口并打印窗口标识：目录 提示文件 命令...
launch() {
  out=$("$(launcher_script open)" "$@") || { echo "${out}" >&2; return 1; }
  echo "${out}" | sed -n 's/^window-id: //p' | tail -1
}
print_manual() {  # 目录 提示文件 命令字符串 [直接写出的短提示]
  echo "在新终端里执行："
  echo "  cd \"$1\""
  if [ "$2" = - ]; then echo "  $3"; elif [ -n "${4:-}" ]; then echo "  $3 \"$4\""; else echo "  $3 \"\$(cat $2)\""; fi
}

# 环节 → 用哪一项模型设置；没有对应设置的环节跟着总控走
step_model() {
  case $1 in
    spec) getv model.spec ;; tickets) getv model.tickets ;; plan) getv model.plan ;;
    dev|fix) getv model.dev ;; closing) getv model.closing ;; audit) getv model.audit ;;
    merge) getv model.merge ;; testdoc|regress) getv model.testdoc ;;
    *) coordinator_model ;;
  esac
}
coordinator_model() { case $(getv coordinator) in codex) echo codex-astra-high ;; *) echo claude-fable ;; esac; }
cli_of() { echo "$1" | awk '{print $1}'; }

cmd_window() {
  act=${1:-}; [ $# -gt 0 ] && shift
  case ${act} in
    open) window_open "$@" ;;
    close) window_close "$@" ;;
    list) window_list "$@" ;;
    register) window_register "$@" ;;
    hello) window_hello "$@" ;;
    *) die "用法：agent-loop window open --step <环节> --dir <工作目录> --prompt <提示文件> [--ticket <票>] [--stage <阶段>] [--model <模型编号>] [--feature <功能>] [--again] [--print]
      agent-loop window close <窗口编号|窗口标识|票号> [--record-only] [--feature <功能>]
      agent-loop window list [--feature <功能>]                  顺带查每个窗口的标签页还在不在，不在的登记为关闭
      agent-loop window hello <窗口编号> [--feature <功能>]       窗口启动后签到一次（初始提示的第一行会要求它这么做）
      agent-loop window register --step <环节> --session <会话ID> [--cli claude|codex] [--model <模型编号>] [--dir <目录>] [--ticket <票>] [--stage <阶段>]
                                 登记一个不是用 window open 开的窗口（例如没指定功能名启动的总控、用户手动开的窗口）" ;;
  esac
}
window_open() {
  need_profile
  feat=""; stage=""; ticket=""; step=""; dir=""; pf=""; model=""; again=no; print=no
  while [ $# -gt 0 ]; do
    case $1 in
      --feature) feat=${2:-}; shift ;; --stage) stage=${2:-}; shift ;; --ticket) ticket=${2:-}; shift ;;
      --step) step=${2:-}; shift ;; --dir) dir=${2:-}; shift ;; --prompt) pf=${2:-}; shift ;;
      --model) model=${2:-}; shift ;; --again) again=yes ;; --print) print=yes ;;
      *) die "未知参数：$1" ;;
    esac
    shift
  done
  [ -n "${step}" ] && [ -n "${dir}" ] && [ -n "${pf}" ] || die "--step、--dir、--prompt 都要给。环节：spec tickets plan dev fix closing audit merge testdoc regress，或其他自定的名字。"
  [ -d "${dir}" ] || die "工作目录不存在：${dir}"
  dir=$(cd -P "${dir}" && pwd -P)
  [ "${pf}" = - ] || [ -f "${pf}" ] || die "提示文件不存在：${pf}"
  need_feature "${feat}"; ledger_init
  [ -n "${ticket}" ] && [ -z "${stage}" ] && stage=$(ticket_stage "${ticket}")
  [ -n "${model}" ] || model=$(step_model "${step}")
  case ${model} in custom:?*) ;; *) [ -n "$(model_line "${model}")" ] || die "模型清单里没有：${model}" ;; esac
  cmd=$(model_cmd "${model}"); cli=$(cli_of "${cmd}"); sid=-
  if [ "${cli}" = claude ]; then
    [ "${step}" = plan ] && cmd="${cmd} --permission-mode plan"
    sid=$(new_uuid); cmd="${cmd} --session-id ${sid}"
  fi
  if [ "${print}" = yes ]; then print_manual "${dir}" "${pf}" "${cmd}"; return 0; fi
  profile_changes_notice
  if [ -n "${ticket}" ] && [ "${again}" = no ]; then
    w=$(win_open_for "${ticket}" "${step}")
    [ -z "${w}" ] || die "${ticket} 的 ${step} 环节已经有一个窗口开着（${w}，$(win_get "${w}" 2) 开的）。它已经结束时先运行 agent-loop window close ${w}；确实要再开一个时加 --again。"
  fi
  # 第一次开窗之前把监视的现状记成已知：之后这个窗口写下的东西才会被当成新的变化
  watch_baseline_once
  wid=$(win_add "${stage}" "${ticket}" "${step}" "${model}" "${cli}" "${dir}" "${sid}")
  # 签到：在初始提示最前面加一行，要窗口启动后先运行 agent-loop window hello。三分钟没签到，监视会通知总控。
  # 两种窗口不加这一行：Claude 的计划模式不能执行命令；以 / 开头的提示是斜杠命令，前面不能有别的字。
  # 这两种靠「会话记录已经出现」来认（见 watch_pass）
  track=no
  if [ "${pf}" != - ]; then
    track=yes
    if ! { [ "${cli}" = claude ] && [ "${step}" = plan ]; } && [ "$(head -c 1 "${pf}")" != / ]; then
      mkdir -p "${LD}/prompts"; wpf="${LD}/prompts/${wid}.prompt"
      { printf '【开始前】先运行一次这条命令向总控签到（表示这个窗口已经开始），然后再做下面的事：agent-loop window hello %s --feature %s\n\n' "${wid}" "${FEATURE}"; cat "${pf}"; } > "${wpf}"
      pf=${wpf}
    elif [ "${cli}" != claude ]; then track=no
    fi
    win_set "${wid}" 15 "${pf}"
  fi
  if launcher_ok; then
    # shellcheck disable=SC2086
    winid=$(launch "${dir}" "${pf}" ${cmd}) || die "开窗失败。登记 ${wid} 已保留，处理后可以加 --again 重开。"
    [ -n "${winid}" ] && { win_set "${wid}" 11 "${winid}"; win_set "${wid}" 12 "$(getv launcher)"; }
  else
    print_manual "${dir}" "${pf}" "${cmd}"; winid=""; track=no
  fi
  [ "${track}" = yes ] || win_set "${wid}" 14 "不适用"
  echo "window: ${wid}"
  echo "window-id: ${winid:--}"
  echo "session: $( [ "${sid}" = - ] && echo "（Codex 的会话 ID 在它启动后自动对上）" || echo "${sid}" )"
  [ "${track}" = no ] || echo "这个窗口三分钟内没有开始时，监视会通知你，不用自己去看它启动了没有。"
  [ "${step}" = coordinator ] || dispatch_hint
}
window_register() {
  need_profile
  feat=""; stage=""; ticket=""; step=""; dir=""; model=""; sid=""; cli=""
  while [ $# -gt 0 ]; do
    case $1 in
      --feature) feat=${2:-}; shift ;; --stage) stage=${2:-}; shift ;; --ticket) ticket=${2:-}; shift ;;
      --step) step=${2:-}; shift ;; --dir) dir=${2:-}; shift ;; --model) model=${2:-}; shift ;;
      --session) sid=${2:-}; shift ;; --cli) cli=${2:-}; shift ;;
      *) die "未知参数：$1" ;;
    esac
    shift
  done
  [ -n "${step}" ] && [ -n "${sid}" ] || die "--step 和 --session 都要给。"
  need_feature "${feat}"; ledger_init
  if grep -qF "${TAB}${sid}${TAB}" "${WIN}"; then echo "这个会话已经登记过：$(awk -F'\t' -v s="${sid}" '$10==s {print $1; exit}' "${WIN}")"; return 0; fi
  [ -n "${dir}" ] || dir=${REPO}
  [ -n "${ticket}" ] && [ -z "${stage}" ] && stage=$(ticket_stage "${ticket}")
  [ -n "${model}" ] || model=$(step_model "${step}")
  [ -n "${cli}" ] || cli=$(cli_of "$(model_cmd "${model}")")
  wid=$(win_add "${stage}" "${ticket}" "${step}" "${model}" "${cli}" "${dir}" "${sid}")
  win_set "${wid}" 14 "不适用"
  echo "已登记：${wid}（${step}，会话 ${sid}）"
}
window_hello() {
  need_profile
  key=""; feat=""
  while [ $# -gt 0 ]; do case $1 in --feature) feat=${2:-}; shift ;; *) key=$1 ;; esac; shift; done
  [ -n "${key}" ] || die "用法：agent-loop window hello <窗口编号> [--feature <功能>]"
  need_feature "${feat}"; ledger_init
  wid=$(win_find "${key}"); [ -n "${wid}" ] || die "台账里找不到这个窗口：${key}"
  win_set "${wid}" 14 "$(now)"
  echo "已签到：${wid}。继续做初始提示里的工作。"
}
window_close() {
  need_profile
  key=""; feat=""; record=no
  while [ $# -gt 0 ]; do case $1 in --feature) feat=${2:-}; shift ;; --record-only) record=yes ;; *) key=$1 ;; esac; shift; done
  [ -n "${key}" ] || die "用法：agent-loop window close <窗口编号|窗口标识|票号> [--record-only]"
  need_feature "${feat}"; ledger_init
  wid=$(win_find "${key}"); [ -n "${wid}" ] || die "台账里找不到这个窗口：${key}"
  win_resolve; usage_refresh "${wid}"
  winid=$(win_get "${wid}" 11)
  # --record-only：只登记这个窗口的工作已经结束，窗口留给用户自己关
  if [ "${record}" = no ] && [ "${winid}" != - ] && launcher_ok; then "$(launcher_script close)" "${winid}" || true; fi
  win_set "${wid}" 13 "$(now)"
  echo "已登记关窗：${wid}"
}
window_list() {
  need_profile
  feat=""; while [ $# -gt 0 ]; do case $1 in --feature) feat=${2:-}; shift ;; esac; shift; done
  need_feature "${feat}"; ledger_init
  win_sweep
  echo "还开着的窗口（${FEATURE}）："
  awk -F'\t' '$13=="-" {printf "  %s  %s  票 %s  %s  %s  %s\n", $1, $2, $5, $6, $7, $9; n++} END { if (!n) print "  （没有）" }' "${WIN}"
}

# 派发（开窗、送消息）之后给总控的一句提醒。写在命令输出里，是因为总控要决定「接下来等不等、怎么等」正是在这一刻
dispatch_hint() {
  if [ "$(getv coordinator)" = codex ]; then
    echo "已派发。若只剩等待本次结果，现在就回复并结束本轮；由常驻监视在约定标记出现时唤醒你，无需查收件日志或轮询文件。"
  elif ! watch_waiting; then
    echo "已派发。监视现在没有挂着，结果出来时没有东西会唤醒你：在后台运行 agent-loop watch wait --feature ${FEATURE}"
  fi
}
# ---------- 给窗口送消息 ----------
# Claude 会话的当前名称：~/.claude/sessions/<pid>.json 记着在线会话
claude_name() {
  for sf in "${HOME}"/.claude/sessions/*.json; do
    [ -f "${sf}" ] || continue
    grep -qF "\"sessionId\":\"$1\"" "${sf}" || continue
    kill -0 "$(basename "${sf}" .json)" 2>/dev/null || continue
    sed -n 's/.*"name":"\([^"]*\)".*/\1/p' "${sf}" | head -1; return 0
  done
  return 1
}
cmd_send() {
  need_profile
  key=""; msg=""; feat=""; expect=""; redo=""
  while [ $# -gt 0 ]; do
    case $1 in
      --feature) feat=${2:-}; shift ;; --expect) expect=${2:-}; shift ;; --redo) redo=${2:-}; shift ;;
      -*) die "未知参数：$1" ;;
      *) if [ -z "${key}" ]; then key=$1; else msg=$1; fi ;;
    esac
    shift
  done
  [ -n "${key}" ] && [ -n "${msg}" ] || die "用法：agent-loop send <窗口编号|票号> \"<消息>\" [--expect <裁决编号>] [--redo <文件>]"
  need_feature "${feat}"; ledger_init
  if [ -n "${redo}" ]; then
    rf=$(watch_resolve_file "${redo}") || die "--redo 指的文件不存在：${redo}"
    case ${rf} in */issues/*) ;; *) msg="${msg}（返工时先删掉 $(basename "${rf}") 末尾的完成标记，全部改完再把它写回最后一行。）" ;; esac
  fi
  # 按票号送、而这张票开着不止一个窗口时不猜：猜错了，对的窗口没收到，错的窗口照着做了
  if ! awk -F'\t' -v k="${key}" '$1==k || $11==k {f=1} END {exit !f}' "${WIN}"; then
    amb=$(awk -F'\t' -v k="${key}" '$5==k && $13=="-" {s = s (n++ ? "、" : "") $1 " " $6} END {if (n > 1) print n " 个开着的窗口：" s}' "${WIN}")
    [ -z "${amb}" ] || die "票 ${key} 有 ${amb}。消息没有送出，请改用窗口编号：agent-loop send <窗口编号> \"<消息>\""
  fi
  wid=$(win_find "${key}"); [ -n "${wid}" ] || die "台账里找不到这个窗口：${key}"
  # 送之前确认对方还在：给已经没有进程的 Codex 会话排消息，codex queue 照样返回成功
  wcl=$(win_get "${wid}" 13)
  [ "${wcl}" = - ] || die "${wid} 已经登记关窗（${wcl}），消息没有送出。这件事还要继续时重开窗口：agent-loop window open … --again"
  if win_gone "${wid}"; then
    win_mark_gone "${wid}"
    die "${wid} 的标签页已经关闭，消息没有送出。台账里已把它登记为关闭；这件事还要继续时重开窗口：agent-loop window open … --again"
  fi
  win_resolve
  cli=$(win_get "${wid}" 8); sid=$(win_get "${wid}" 10)
  [ "${sid}" != - ] || die "${wid} 的会话 ID 还没对上（窗口可能还没启动完）。稍后再试，或者请用户在那个窗口说「继续」。"
  if [ -n "${AGENT_LOOP_SEND_CMD:-}" ]; then
    ${AGENT_LOOP_SEND_CMD} "${cli}" "${sid}" "${msg}" || die "送出失败。"
  else
    case ${cli} in
      codex) codex queue --thread "${sid}" --message "${msg}" >/dev/null || die "codex queue 执行失败。请用户在那个窗口说「继续」。" ;;
      claude)
        name=$(claude_name "${sid}") || die "那个 Claude 窗口不在运行（会话 ${sid}）。"
        # 借一次性的小模型用 SendMessage 转发：消息带着「来自另一个会话」的标记，对方不会当成用户本人说的
        ( cd "${REPO}" && claude -p --model claude-haiku-5-5 --allowedTools "SendMessage,ListAgents,ToolSearch" -- \
          "用 SendMessage 把下面「消息」一节的文字原样发给名为 ${name} 的本机 Claude 会话。不要做别的事，不要改写。发完只回答「已发出」；发不出去时回答原因。

消息：
${msg}" ) || die "转发失败。请用户在那个窗口说「继续」。" ;;
      *) die "不知道怎么给这种窗口送消息（${cli}）。请用户在那个窗口说「继续」。" ;;
    esac
  fi
  if [ -n "${expect}" ]; then
    t=$(win_get "${wid}" 5); f=$(ticket_file "${t}") || die "找不到 ${t} 的票文件，没有登记等待接收。"
    printf '%s\t%s\t%s\n' "${f}" "${expect}" "$(epoch)" >> "${LD}/expect.tsv"
  fi
  [ -z "${redo}" ] || watch_redo "${rf}"
  # 票头已经是 done 的开发窗口又收到消息：多半是返工。自动登记，否则窗口很快改完时监视两次看到的都是 done，不会再通知
  auto=""; sstep=$(win_get "${wid}" 6)
  if [ -z "${expect}${redo}" ]; then
    case ${sstep} in dev|fix)
      st=$(win_get "${wid}" 5)
      if [ "${st}" != - ] && stf=$(ticket_file "${st}") && [ "$(watch_status_of "${stf}")" = done ]; then watch_redo "${stf}"; auto=yes; fi ;;
    esac
  fi
  if [ -n "${expect}" ]; then echo "已送出给 ${wid}。五分钟后票头仍是 needs-decision 时，监视会通知你「裁决 ${expect} 未被接收」。"
  elif [ -n "${redo}" ]; then
    case ${rf} in */issues/*) echo "已送出给 ${wid}。已登记返工：票的内容变了、票头又是 done 时，监视会再通知一次。" ;;
      *) echo "已送出给 ${wid}。$(basename "${rf}") 改完、末尾重新写上完成标记时，监视会再通知一次。" ;; esac
  elif [ -n "${auto}" ]; then echo "已送出给 ${wid}。${st} 的票头已经是 done，已登记返工：窗口改完、票头再次是 done 时，监视会再通知一次。"
  else echo "已送出给 ${wid}。"; fi
  dispatch_hint
  # 只在用得上的时候提醒：这个窗口负责的产物已经通知过完成标记，而这次没有登记返工
  if [ -z "${expect}${redo}" ]; then
    case ${sstep} in spec) hp='/spec.md::' ;; tickets) hp='/tickets-common.md::' ;; audit) hp='/reviews/' ;; merge) hp='/merges/' ;; testdoc) hp='/regression/' ;; *) hp="" ;; esac
    if [ -n "${hp}" ] && awk -F'\t' -v p="${hp}" 'index($1, p) && index($1, "::") && $2 == "seen" {f=1} END {exit !f}' "${LD}/watch.state" 2>/dev/null; then
      echo "注意：这个窗口的产物已经通知过完成标记。如果这次是让它返工，要加 --redo <文件>，否则同一个标记监视不会再通知。"
    fi
  fi
}
