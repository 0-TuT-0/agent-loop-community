# 功能目录的定位、窗口登记、票台账（含用量）。由 agent-loop 主脚本 source。
# 数据放在 <功能目录>/ledger/ 下，每行一条、制表符分隔，空值写成 -；给人看的表由命令生成到 <功能目录>/ledger.md。
#   windows.tsv  窗口登记：编号 开窗时间 开窗秒数 阶段 票 环节 模型编号 命令行 工作目录 会话ID 窗口标识 启动器 关窗时间 签到时间 提示文件
#                签到时间：- = 还没签到（监视会盯）；「不适用」= 不盯（手动开的、恢复的会话）。旧版本登记的行没有后两列，也不盯
#   events.tsv   事件：时间 类型(done|rework|plan-revise|audit|source) 对象 取值
#   usage.tsv    用量快照：窗口编号 取数时间 输入 缓存读取 输出
TAB=$(printf '\t')

# ---------- 功能目录 ----------
feature_names() {
  td="${REPO}/$(task_dir "${REPO}")"
  for d in "${td}"/*/; do
    [ -d "${d}" ] || continue
    if [ -f "${d}dev-plan.md" ] || [ -f "${d}map.md" ] || [ -d "${d}ledger" ] || [ -f "${d}todo.md" ]; then basename "${d}"; fi
  done
}
# 定位功能目录，结果写进 FEATURE 和 FD。$1 是 --feature 给的名字，可以为空
need_feature() {
  td="${REPO}/$(task_dir "${REPO}")"
  FEATURE=${1:-${AGENT_LOOP_FEATURE:-}}
  if [ -z "${FEATURE}" ]; then
    feature_names > "${VALS}.f"
    n=$(grep -c . "${VALS}.f")
    if [ "${n}" -eq 1 ]; then FEATURE=$(cat "${VALS}.f")
    elif [ "${n}" -eq 0 ]; then die "任务目录 ${td} 下还没有功能。先启动总控：agent-loop start <功能名>"
    elif [ -t 0 ]; then
      echo "有多个功能：" >&2; i=0
      while IFS= read -r f; do i=$((i+1)); echo "  ${i}. ${f}" >&2; done < "${VALS}.f"
      ask "选择编号："
      FEATURE=$(sed -n "${REPLY}p" "${VALS}.f" 2>/dev/null); [ -n "${FEATURE}" ] || die "无效的编号。"
    else
      die "有多个功能（$(tr '\n' ' ' < "${VALS}.f")），请用 --feature <功能名> 指定。"
    fi
  fi
  case ${FEATURE} in *[!A-Za-z0-9._-]*|.*) die "功能名只用英文字母、数字、点、下划线和连字符：${FEATURE}" ;; esac
  FD="${td}/${FEATURE}"
  [ -d "${FD}" ] || die "没有这个功能目录：${FD}"
  LD="${FD}/ledger"; WIN="${LD}/windows.tsv"; EV="${LD}/events.tsv"; USE="${LD}/usage.tsv"
}
ledger_init() { mkdir -p "${LD}"; touch "${WIN}" "${EV}" "${USE}"; }
# 项目级的记录：可选窗口（规范维护、错误对接）不属于某个功能，登记在 <任务目录>/.agent-loop/ 下
scope_project() {
  LD="${REPO}/$(task_dir "${REPO}")/.agent-loop"; WIN="${LD}/windows.tsv"; EV="${LD}/events.tsv"; USE="${LD}/usage.tsv"
  ledger_init
}
# 可选窗口的用量，按窗口名各占一行；不计入任何功能的合计
project_usage_print() {
  ( scope_project
    [ -s "${WIN}" ] || exit 0
    usage_refresh_all
    awk -F'\t' -v fm="${MODELS}" -v fu="${USE}" '
      function human(n) { if (n >= 1000000) return sprintf("%.2fM", n/1000000); if (n >= 1000) return sprintf("%.1fk", n/1000); return sprintf("%d", n) }
      BEGIN {
        while ((getline l < fm) > 0) { if (l ~ /^#/ || l == "") continue; split(l, a, "|"); ML[a[1]] = a[3] }
        while ((getline l < fu) > 0) { split(l, a, "\t"); UI[a[1]] = a[3] + 0; UR[a[1]] = a[4] + 0; UO[a[1]] = a[5] + 0; HAS[a[1]] = 1 }
        NAME["maintainer"] = "规范维护窗口"; NAME["error-intake"] = "错误对接窗口" }
      { s = $6; if (!(s in SEEN)) { SEEN[s] = 1; ord[++n] = s }
        C[s]++; M[s] = ($7 in ML) ? ML[$7] : $7; if ($1 in HAS) { H[s] = 1; I[s] += UI[$1]; O[s] += UO[$1]; R[s] += UR[$1] } }
      END {
        print ""; print "可选窗口（属于整个项目，单独计算，不计入功能的合计）"; print ""
        print "| 窗口 | 模型 | 会话数 | 输入 | 输出 | 缓存读取 |"
        print "| --- | --- | --- | --- | --- | --- |"
        for (i = 1; i <= n; i++) { s = ord[i]
          print "| " ((s in NAME) ? NAME[s] : s) " | " M[s] " | " C[s] " | " (H[s] ? human(I[s]) " | " human(O[s]) " | " human(R[s]) : "- | - | -") " |" } }' "${WIN}" )
}

# ---------- 票文件 ----------
# 票号形如 p1-03：阶段 p1，票文件 <功能目录>/p1/issues/03-*.md
ticket_stage() { echo "${1%-*}"; }
ticket_file() {
  nn=${1##*-}; st=${1%-*}
  [ "${st}" != "$1" ] || return 1
  for f in "${FD}/${st}/issues/${nn}"-*.md "${FD}/${st}/issues/${nn}.md"; do [ -f "${f}" ] && { echo "${f}"; return 0; }; done
  return 1
}
# 风险只取等级本身：票头常写成「中（理由……）」，括号和后面的说明不要
ticket_risk() {
  f=$(ticket_file "$1") && grep -m1 -E '^\**Risk:?\**:?' "${f}" | sed -E 's/^\**Risk:?\**:?[[:space:]]*//' | awk '{print $1}' | sed -e 's/（.*//' -e 's/(.*//' -e 's/[，,：:；;].*//'
}
ticket_rulings() { f=$(ticket_file "$1") && grep -c '^### 裁决 ' "${f}"; }

# ---------- 窗口登记 ----------
win_get() { awk -F'\t' -v w="$1" -v c="$2" '$1==w {print $c; exit}' "${WIN}"; }
win_set() {
  awk -F'\t' -v OFS='\t' -v w="$1" -v c="$2" -v v="$3" '$1==w {$c=v} {print}' "${WIN}" > "${VALS}.w" && cat "${VALS}.w" > "${WIN}"
}
win_add() {  # 阶段 票 环节 模型 命令行 目录 会话 → 打印窗口编号
  n=$(grep -c . "${WIN}"); wid=$(printf 'W-%03d' $((n+1)))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-\t-\t-\t-\t-\n' "${wid}" "$(now)" "$(epoch)" "${1:--}" "${2:--}" "$3" "$4" "$5" "$6" "${7:--}" >> "${WIN}"
  echo "${wid}"
}
# 同一张票的同一环节是否有还没关的窗口
win_open_for() { awk -F'\t' -v t="$1" -v s="$2" '$5==t && $6==s && $13=="-" {print $1; exit}' "${WIN}"; }
# 按窗口编号、窗口标识或票号找到窗口编号。一张票有几个窗口时，取还没关的里面最近开的；都关了就取最近开的
win_find() {
  awk -F'\t' -v k="$1" '$1==k || $11==k {r=$1} $5==k {t=$1; if ($13=="-") o=$1} END { if (r!="") print r; else if (o!="") print o; else if (t!="") print t }' "${WIN}"
}

# ---------- 会话与用量 ----------
codex_root() { echo "${CODEX_HOME:-${HOME}/.codex}/sessions"; }
# Codex 的会话 ID 开窗时还不知道：按工作目录和启动时间到会话记录里对上（文件名里带本地启动时间）
codex_session_for() {  # 目录 开窗秒数
  root=$(codex_root); [ -d "${root}" ] || return 1
  since=$(epoch_to_stamp $(( $2 - 5 )) | tr ' :' 'T-')
  find "${root}" -name 'rollout-*.jsonl' 2>/dev/null | sort | while IFS= read -r f; do
    b=$(basename "${f}"); t=${b#rollout-}; t=$(echo "${t}" | cut -c1-19)
    [ "${t}" \< "${since}" ] && continue
    head -c 4000 "${f}" | head -1 | grep -qF "\"cwd\":\"$1\"" || continue
    id=$(head -c 4000 "${f}" | sed -n '1s/.*"session_id":"\([^"]*\)".*/\1/p')
    [ -n "${id}" ] || continue
    grep -qF "${TAB}${id}${TAB}" "${WIN}" && continue
    echo "${id}"; break
  done
}
# 补上还不知道的 Codex 会话 ID
win_resolve() {
  awk -F'\t' '$8=="codex" && $10=="-" {print $1 "\t" $9 "\t" $3}' "${WIN}" > "${VALS}.r"
  while IFS="${TAB}" read -r w d e; do
    id=$(codex_session_for "${d}" "${e}"); [ -n "${id}" ] && win_set "${w}" 10 "${id}"
  done < "${VALS}.r"
}
usage_claude() {  # 会话ID → 「输入 缓存读取 输出」。同一条回复在记录里出现多次，按回复编号去重
  f=$(ls "${HOME}"/.claude/projects/*/"$1".jsonl 2>/dev/null | head -1); [ -n "${f}" ] || return 1
  awk '
    function num(s, k,   q, t) { q = index(s, k); if (!q) return 0; t = substr(s, q + length(k), 15); sub(/[^0-9].*/, "", t); return t + 0 }
    index($0, "\"type\":\"assistant\"") == 0 { next }
    { p = index($0, "\"usage\":{"); if (!p) next
      s = substr($0, p, 700)
      if (match($0, /"id":"msg_[A-Za-z0-9_]+"/)) id = substr($0, RSTART, RLENGTH); else id = "line" NR
      I[id] = num(s, "\"input_tokens\":") + num(s, "\"cache_creation_input_tokens\":")
      R[id] = num(s, "\"cache_read_input_tokens\":"); O[id] = num(s, "\"output_tokens\":") }
    END { for (k in I) { a += I[k]; b += R[k]; c += O[k] } printf "%d %d %d\n", a, b, c }' "${f}"
}
usage_codex() {  # 会话ID → 「输入 缓存读取 输出」。记录里的累计值取最后一条
  f=$(ls "$(codex_root)"/*/*/*/rollout-*-"$1".jsonl 2>/dev/null | head -1); [ -n "${f}" ] || return 1
  l=$(grep '"total_token_usage"' "${f}" | tail -1); [ -n "${l}" ] || { echo "0 0 0"; return 0; }
  echo "${l}" | awk '
    function num(s, k,   q, t) { q = index(s, k); if (!q) return 0; t = substr(s, q + length(k), 15); sub(/[^0-9].*/, "", t); return t + 0 }
    { p = index($0, "\"total_token_usage\":{"); s = substr($0, p, 400)
      i = num(s, "\"input_tokens\":"); c = num(s, "\"cached_input_tokens\":"); o = num(s, "\"output_tokens\":")
      printf "%d %d %d\n", (i > c ? i - c : 0), c, o }'
}
# 重新取一个窗口的用量并存下；会话记录已经不在时保留上次存的数
usage_refresh() {
  w=$1; cli=$(win_get "${w}" 8); sid=$(win_get "${w}" 10)
  [ -n "${sid}" ] && [ "${sid}" != - ] || return 0
  case ${cli} in claude) u=$(usage_claude "${sid}") ;; codex) u=$(usage_codex "${sid}") ;; *) return 0 ;; esac
  [ -n "${u}" ] || return 0
  awk -F'\t' -v w="${w}" '$1!=w' "${USE}" > "${VALS}.u"
  # shellcheck disable=SC2086
  set -- ${u}
  printf '%s\t%s\t%s\t%s\t%s\n' "${w}" "$(now)" "$1" "$2" "$3" >> "${VALS}.u"
  cat "${VALS}.u" > "${USE}"
}
usage_refresh_all() {
  win_resolve
  for w in $(cut -f1 "${WIN}"); do usage_refresh "${w}"; done
}

# ---------- 事件 ----------
ev_add() { printf '%s\t%s\t%s\t%s\n' "$(now)" "$1" "$2" "${3:--}" >> "${EV}"; }

# ---------- 生成表 ----------
# $1 阶段（空 = 全部） $2 视图：full | summary
ledger_render() {
  : > "${VALS}.ti"
  for t in $( { awk -F'\t' '$5!="-" {print $5}' "${WIN}"; awk -F'\t' '$2!="audit" || $3 ~ /-[0-9]+$/ {print $3}' "${EV}"; } | awk '!seen[$0]++'); do
    ticket_file "${t}" >/dev/null 2>&1 || continue
    printf '%s\t%s\t%s\n' "${t}" "$(ticket_risk "${t}")" "$(ticket_rulings "${t}")" >> "${VALS}.ti"
  done
  awk -F'\t' -v stage="$1" -v view="$2" -v feature="${FEATURE}" -v gen="$(now)" \
      -v fm="${MODELS}" -v fti="${VALS}.ti" -v fu="${USE}" -v fe="${EV}" -v fw="${WIN}" '
    function human(n) { if (n >= 1000000) return sprintf("%.2fM", n/1000000); if (n >= 1000) return sprintf("%.1fk", n/1000); return sprintf("%d", n) }
    function label(m,   x) { if (m in ML) return ML[m]; x = m; sub(/^custom:/, "", x); return x }
    function stof(t,   x) { x = t; sub(/-[^-]*$/, "", x); return x }
    function inscope(st) { return stage == "" || st == stage }
    function auditstr(t,   i, s, k) { s = ""; for (i = 1; i <= nsev; i++) { k = sev[i]; if (AU[t, k] > 0) s = s (s == "" ? "" : "、") k " " AU[t, k] } return s == "" ? "-" : s }
    BEGIN {
      while ((getline l < fm) > 0) { if (l ~ /^#/ || l == "") continue; split(l, a, "|"); ML[a[1]] = a[3] }
      while ((getline l < fti) > 0) { split(l, a, "\t"); RISK[a[1]] = a[2]; RUL[a[1]] = a[3] + 0 }
      while ((getline l < fu) > 0) { split(l, a, "\t"); UI[a[1]] = a[3] + 0; UR[a[1]] = a[4] + 0; UO[a[1]] = a[5] + 0 }
      while ((getline l < fe) > 0) {
        split(l, a, "\t"); ty = a[2]; t = a[3]
        if (!(t in SEEN)) { SEEN[t] = 1 }
        if (ty == "done") DONE[t] = a[1]
        else if (ty == "rework") RW[t]++
        else if (ty == "plan-revise") PR[t]++
        else if (ty == "source") SRC[t] = a[4]
        else if (ty == "audit") {
          n = split(a[4], p, ",")
          for (i = 1; i <= n; i++) { split(p[i], kv, "="); if (!((kv[1]) in SEVSEEN)) { SEVSEEN[kv[1]] = 1; sev[++nsev] = kv[1] } AU[t, kv[1]] += kv[2]; AUN[t] += kv[2] }
          if (t !~ /-[0-9]+$/ && !(t in STSEEN)) { STSEEN[t] = 1; stages[++nst] = t }
        }
      }
      while ((getline l < fw) > 0) {
        split(l, a, "\t"); w = a[1]; nw++; W[nw] = w
        OP[w] = a[2]; ST[w] = a[4]; TK[w] = a[5]; SP[w] = a[6]; MD[w] = a[7]; DIR[w] = a[9]; SID[w] = a[10]; CL[w] = a[13]
        t = a[5]
        if (t != "-") {
          if (!(t in TFIRST)) { TFIRST[t] = a[2]; tickets[++nt] = t; TST[t] = a[4] }
          step = a[6] " " label(a[7])
          if (TLAST[t] != step) { CHAIN[t] = CHAIN[t] (CHAIN[t] == "" ? "" : " → ") step; TLAST[t] = step }
          # 票的返工、裁决、审计问题算在做开发的模型上：取 dev 或 fix 环节的模型；没有这两个环节时取第一个窗口的模型
          if (a[6] == "dev" || a[6] == "fix") { DEVM[t] = a[7]; DEVSET[t] = 1 } else if (!(t in DEVM)) DEVM[t] = a[7]
          TI[t] += UI[w]; TR[t] += UR[w]; TO[t] += UO[w]; if (w in UI) TU[t] = 1
        }
      }
      # 只有事件、没有窗口登记的票（例如手工开的窗口）也列出来
      for (t in SEEN) if (t ~ /-[0-9]+$/ && !(t in TFIRST)) { tickets[++nt] = t; TFIRST[t] = "-"; TST[t] = stof(t); CHAIN[t] = "-" }

      if (view == "full") {
        print "# 票台账：" feature (stage == "" ? "" : "（" stage "）"); print ""
        print "由 `agent-loop ledger` 生成于 " gen "，请勿手工编辑。用量单位是 token：输入含写入缓存的部分，缓存读取单列；写 - 表示还没取到这个窗口的会话记录。"; print ""
        print "## 票"; print ""
        print "| 票 | 风险 | 执行 | 开窗 | 完成 | 裁决 | 返工 | 计划修改 | 审计问题 | 输入 | 输出 | 缓存读取 | 来源票 |"
        print "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
        for (i = 1; i <= nt; i++) { t = tickets[i]; if (!inscope(TST[t])) continue
          print "| " t " | " (RISK[t] == "" ? "-" : RISK[t]) " | " CHAIN[t] " | " TFIRST[t] " | " (t in DONE ? DONE[t] : "-") " | " RUL[t] + 0 " | " RW[t] + 0 " | " PR[t] + 0 " | " auditstr(t) " | " (TU[t] ? human(TI[t]) " | " human(TO[t]) " | " human(TR[t]) : "- | - | -") " | " (t in SRC ? SRC[t] : "-") " |" }
        for (i = 1; i <= nst; i++) { t = stages[i]; if (!inscope(t)) continue
          print "| " t "（归不到单张票） | - | - | - | - | - | - | - | " auditstr(t) " | - | - | - | - |" }
        print ""; print "## 其他窗口"; print ""
        print "| 窗口 | 阶段 | 环节 | 模型 | 开窗 | 输入 | 输出 | 缓存读取 |"
        print "| --- | --- | --- | --- | --- | --- | --- | --- |"
        for (i = 1; i <= nw; i++) { w = W[i]; if (TK[w] != "-") continue; if (!(ST[w] == "-" || inscope(ST[w]))) continue
          print "| " w " | " ST[w] " | " SP[w] " | " label(MD[w]) " | " OP[w] " | " ((w in UI) ? human(UI[w]) " | " human(UO[w]) " | " human(UR[w]) : "- | - | -") " |" }
        print ""
      }

      # 按模型汇总：一张票的返工、裁决、审计问题算在做开发那一步的模型上（审计、计划窗口的模型不算）；用量按窗口算在各自的模型上
      for (i = 1; i <= nt; i++) { t = tickets[i]; if (!inscope(TST[t])) continue
        tot++; if (RISK[t] == "高") high++
        m = DEVM[t]; if (m == "") m = "-"
        if (!(m in MSEEN)) { MSEEN[m] = 1; models[++nm] = m }
        MT[m]++; MRW[m] += RW[t]; MRU[m] += RUL[t]; MAU[m] += AUN[t] }
      for (i = 1; i <= nw; i++) { w = W[i]
        if (TK[w] != "-") { if (!inscope(ST[w])) continue; m = MD[w]; if (!(m in MSEEN)) { MSEEN[m] = 1; models[++nm] = m }
          MI[m] += UI[w]; MO[m] += UO[w]; MR[m] += UR[w] }
        else { if (!(ST[w] == "-" || inscope(ST[w]))) continue; s = SP[w]
          # 总控换过会话时每个会话单列一行、各标各的模型，下面另有合计：合在一行会把几种总控的用量算到最后一个的模型名下
          if (s == "coordinator") { nco++; CI += UI[w]; CO += UO[w]; CR += UR[w]; s = "coordinator " w; OT[s] = OP[w] " 至 " (CL[w] == "-" ? "现在" : CL[w]) }
          if (!(s in OSEEN)) { OSEEN[s] = 1; others[++no] = s }
          OI[s] += UI[w]; OO[s] += UO[w]; OR_[s] += UR[w]; OL[s] = label(MD[w]) }
        GI += UI[w]; GO += UO[w]; GR += UR[w] }
      for (i = 1; i <= nst; i++) if (inscope(stages[i])) stageaudit += AUN[stages[i]]
      print (view == "full" ? "## 按模型汇总" : (stage == "" ? feature : stage) " 票统计：" tot + 0 " 张票（高风险 " high + 0 "）"); print ""
      print "| 模型 | 票数 | 返工 | 裁决 | 审计问题 | 输入 | 输出 | 缓存读取 |"
      print "| --- | --- | --- | --- | --- | --- | --- | --- |"
      for (i = 1; i <= nm; i++) { m = models[i]
        print "| " label(m) " | " (MT[m] > 0 ? MT[m] : "-") " | " (MT[m] > 0 ? MRW[m] + 0 : "-") " | " (MT[m] > 0 ? MRU[m] + 0 : "-") " | " (MT[m] > 0 ? MAU[m] + 0 : "-") " | " human(MI[m]) " | " human(MO[m]) " | " human(MR[m]) " |" }
      for (i = 1; i <= no; i++) { s = others[i]
        if (s ~ /^coordinator / && nco == 1) nm_ = "coordinator（" OL[s] "）"
        else if (s ~ /^coordinator /) nm_ = s "（" OL[s] "，" OT[s] "）"
        else nm_ = s "（" OL[s] "）"
        print "| 其他窗口：" nm_ " | - | - | - | - | " human(OI[s]) " | " human(OO[s]) " | " human(OR_[s]) " |" }
      if (nco > 1) print "| 其他窗口：coordinator 合计（" nco " 个会话） | - | - | - | - | " human(CI) " | " human(CO) " | " human(CR) " |"
      if (stageaudit > 0) print "| 归不到单张票的审计问题 | - | - | - | " stageaudit " | - | - | - |"
      print "| 合计 | " tot + 0 " | | | | " human(GI) " | " human(GO) " | " human(GR) " |"

      if (view == "full") {
        print ""; print "## 会话"; print ""
        print "| 窗口 | 票 | 环节 | 会话 ID | 工作目录 | 关窗 |"
        print "| --- | --- | --- | --- | --- | --- |"
        for (i = 1; i <= nw; i++) { w = W[i]; if (!(ST[w] == "-" || inscope(ST[w]))) continue
          print "| " w " | " TK[w] " | " SP[w] " | " SID[w] " | " DIR[w] " | " CL[w] " |" }
      }
    }'
}

# ---------- 子命令：ledger ----------
cmd_ledger() {
  need_profile
  feat=""; stage=""; view=full; act=""; args=""
  while [ $# -gt 0 ]; do
    case $1 in
      --feature) feat=${2:-}; shift ;;
      --summary) view=summary ;;
      done|rework|plan-revise|audit|source|snapshot|undo) [ -z "${act}" ] && act=$1 || args="${args} $1" ;;
      -*) die "未知参数：$1" ;;
      *) if [ -n "${act}" ]; then args="${args} $1"; else stage=$1; fi ;;
    esac
    shift
  done
  need_feature "${feat}"; ledger_init
  # shellcheck disable=SC2086
  set -- ${args}
  case ${act} in
    "")
      usage_refresh_all
      ledger_render "" full > "${FD}/ledger.md"
      ledger_render "${stage}" "${view}"
      project_usage_print ;;
    done)
      [ $# -ge 1 ] || die "用法：agent-loop ledger done <票>"
      ev_add done "$1"
      win_resolve
      for w in $(awk -F'\t' -v t="$1" '$5==t {print $1}' "${WIN}"); do usage_refresh "${w}"; done
      echo "已记录：$1 完成于 $(now)" ;;
    rework|plan-revise)
      [ $# -ge 1 ] || die "用法：agent-loop ledger ${act} <票>"
      ev_add "${act}" "$1"; echo "已记录：$1 $( [ "${act}" = rework ] && echo 返工 || echo 计划修改 )一次" ;;
    audit)
      [ $# -ge 2 ] || die "用法：agent-loop ledger audit <票或阶段> <严重程度>=<数量> ...   例：agent-loop ledger audit p1-03 阻塞=1 应修=2"
      t=$1; shift; v=""
      for kv in "$@"; do
        case ${kv} in ?*=*) n=${kv#*=}; case ${n} in ""|*[!0-9]*) die "数量要写数字：${kv}" ;; esac ;; *) die "写成 <严重程度>=<数量>：${kv}" ;; esac
        v="${v}${v:+,}${kv}"
      done
      ev_add audit "${t}" "${v}"; echo "已记录：${t} 的审计问题 ${v}" ;;
    source)
      [ $# -ge 2 ] || die "用法：agent-loop ledger source <修复票> <来源票>"
      ev_add source "$1" "$2"; echo "已记录：$1 修的是 $2 的问题" ;;
    snapshot)
      usage_refresh_all; ledger_render "" full > "${FD}/ledger.md"; echo "已更新用量：${FD}/ledger.md" ;;
    undo)
      [ -s "${EV}" ] || die "没有可撤销的记录。"
      echo "已撤销：$(tail -1 "${EV}" | tr '\t' ' ')"
      sed '$d' "${EV}" > "${VALS}.e" && cat "${VALS}.e" > "${EV}" ;;
  esac
}
