# 票的三个机械动作各一条命令：开工（建 worktree 并开窗）、核对、合入并登记。由 agent-loop 主脚本 source。
# 目的是减少总控的模型调用次数：这些步骤原来由总控一条条命令执行，每条命令都要重读一遍上下文。
# 判断仍然归总控：核对命令只列出事实，提交范围是否合适、回报是否可信由总控看。

# 参数文件「路径」一节里某一行的反引号内容：profile_item 取第一个，profile_items 取全部
profile_item() { grep -m1 "^- $1" "${REPO}/${PROFILE_REL}" | sed 's/^[^：]*：//' | sed -n 's/^[^`]*`\([^`]*\)`.*/\1/p'; }
profile_items() { grep -m1 "^- $1" "${REPO}/${PROFILE_REL}" | sed 's/^[^：]*：//' | tr '`' '\n' | awk 'NR % 2 == 0'; }
worktree_root() {
  r=$(profile_item 'worktree 根目录'); r=${r%/}
  [ -n "${r}" ] || r="$(basename "${REPO}")-worktrees"
  case ${r} in /*) echo "${r}" ;; *) echo "$(dirname "${REPO}")/${r}" ;; esac
}
ticket_hdr() { grep -m1 -E "^\**$2:?\**:?" "$1" 2>/dev/null | sed -E "s/^\**$2:?\**:?[[:space:]]*//"; }
ticket_branch() { ticket_hdr "$1" Branch | sed -e 's/（.*//' -e 's/(.*//' | awk '{print $1}'; }
ticket_worktree() { ticket_hdr "$1" Worktree | awk '{print $1}'; }
ticket_title() { sed -n '1s/^# *//p' "$1"; }
# 这张票要合入的分支：修复分支上的票合入修复分支，其余合入阶段分支
ticket_into() {  # 票号 票分支
  fixb=$(profile_item '修复分支名'); pre=$(profile_item '分支前缀')
  if [ -n "${fixb}" ] && case $2 in "${fixb}"-*) true ;; *) false ;; esac; then echo "${fixb}"; else echo "${pre}$(ticket_stage "$1")"; fi
}
# 参数文件自上次开窗以来的变更：有新增就列出来，总控不用为此专门重读参数文件
profile_changes_notice() {
  awk '/^## 变更记录/ {s=1; next} /^## / {s=0} s && /^- /' "${REPO}/${PROFILE_REL}" > "${VALS}.cl"
  n=$(grep -c . "${VALS}.cl"); old=$(cat "${LD}/profile.seen" 2>/dev/null); old=${old:-${n}}
  if [ "${n}" -gt "${old}" ]; then
    echo "参数文件自上次开窗以来有 $((n - old)) 条变更（涉及「设置」表以外的内容时，重读对应的一节）："
    tail -n "$((n - old))" "${VALS}.cl" | sed 's/^/  /'
  fi
  echo "${n}" > "${LD}/profile.seen"
}

# 机械核对：把事实列出来，返回 0 表示机械条件都满足
ticket_facts() {  # 票号 合入的目标分支（可空）
  T_FILE=$(ticket_file "$1") || die "找不到票文件：$1（应当在 ${FD}/$(ticket_stage "$1")/issues/ 下）"
  T_STATUS=$(watch_status_of "${T_FILE}"); T_BRANCH=$(ticket_branch "${T_FILE}"); T_WT=$(ticket_worktree "${T_FILE}")
  T_TITLE=$(ticket_title "${T_FILE}"); T_PROBLEMS=""
  [ -n "${T_BRANCH}" ] || die "票头里没有 Branch 行：${T_FILE}"
  git -C "${REPO}" rev-parse --verify -q "${T_BRANCH}" >/dev/null || die "没有这个分支：${T_BRANCH}"
  T_INTO=${2:-$(ticket_into "$1" "${T_BRANCH}")}
  git -C "${REPO}" rev-parse --verify -q "${T_INTO}" >/dev/null || die "没有要合入的目标分支：${T_INTO}。用 --into <分支> 指定。"
  T_HEAD=$(git -C "${REPO}" rev-parse --short "${T_BRANCH}")
  T_AHEAD=$(git -C "${REPO}" rev-list --count "${T_INTO}..${T_BRANCH}")
  git -C "${REPO}" diff --name-only "${T_INTO}...${T_BRANCH}" > "${VALS}.tf"
  T_DIRTY=""
  if [ -n "${T_WT}" ] && [ -d "${T_WT}" ]; then T_DIRTY=$(git -C "${T_WT}" status --porcelain | head -8); fi
  [ "${T_STATUS}" = done ] || T_PROBLEMS="${T_PROBLEMS}票头是 ${T_STATUS:-空}，不是 done；"
  [ "${T_AHEAD}" -gt 0 ] || T_PROBLEMS="${T_PROBLEMS}票分支相对 ${T_INTO} 没有新提交（可能已经合入）；"
  [ -z "${T_DIRTY}" ] || T_PROBLEMS="${T_PROBLEMS}工作区有未提交的修改；"
}

cmd_ticket() {
  need_profile
  act=${1:-}; [ $# -gt 0 ] && shift
  t=""; feat=""; into=""; pf=""; step=dev; fix=no; br=""; base=""; dir=""; again=""; model=""
  while [ $# -gt 0 ]; do
    case $1 in
      --feature) feat=${2:-}; shift ;; --into) into=${2:-}; shift ;; --prompt) pf=${2:-}; shift ;;
      --step) step=${2:-}; shift ;; --fix) fix=yes ;; --branch) br=${2:-}; shift ;; --base) base=${2:-}; shift ;;
      --dir) dir=${2:-}; shift ;; --again) again=--again ;; --model) model=${2:-}; shift ;;
      -*) die "未知参数：$1" ;;
      *) t=$1 ;;
    esac
    shift
  done
  [ -n "${act}" ] && [ -n "${t}" ] || die "用法：agent-loop ticket open <票> --prompt <提示文件> [--step dev|plan|fix] [--fix] [--branch <票分支>] [--base <基点分支>] [--dir <worktree>] [--again]
      agent-loop ticket verify <票> [--into <目标分支>]
      agent-loop ticket merge <票> [--into <目标分支>]"
  need_feature "${feat}"; ledger_init
  case ${act} in
    verify)
      ticket_facts "${t}" "${into}"
      echo "票 ${t}「${T_TITLE}」"
      echo "票头：${T_STATUS:-空}    风险：$(ticket_risk "${t}")"
      echo "分支：${T_BRANCH} @ ${T_HEAD}，相对 ${T_INTO} 多 ${T_AHEAD} 个提交"
      if [ -z "${T_DIRTY}" ]; then echo "工作区：干净（${T_WT:-票头没有 Worktree 行}）"; else echo "工作区：有未提交的修改"; echo "${T_DIRTY}" | sed 's/^/  /'; fi
      echo "改动的文件（$(grep -c . "${VALS}.tf") 个）："; sed 's/^/  /' "${VALS}.tf"
      echo "票里最后一节（一般是完成回报）："
      awk '/^### / {buf = ""} {buf = buf $0 "\n"} END {printf "%s", buf}' "${T_FILE}" | head -60 | sed 's/^/  /'
      if [ -z "${T_PROBLEMS}" ]; then echo "机械核对：通过。还要你看两件事：提交范围是否只含本票的文件；测试结论以上面的完成回报为准（看里面的命令和通过、失败、跳过的数），回报不全就让窗口补。你不重跑测试：合入之后的结果由阶段审计和合并窗口来测。"
      else echo "机械核对：不通过。${T_PROBLEMS}"; return 1; fi ;;
    merge)
      ticket_facts "${t}" "${into}"
      [ -z "${T_PROBLEMS}" ] || die "不能合入：${T_PROBLEMS}"
      iw=$(git -C "${REPO}" worktree list --porcelain | awk -v b="refs/heads/${T_INTO}" '/^worktree / {w = substr($0, 10)} $1 == "branch" && $2 == b {print w; exit}')
      [ -n "${iw}" ] || die "没有检出 ${T_INTO} 的 worktree（集成 worktree）。先建一个：git worktree add <目录> ${T_INTO}"
      [ -z "$(git -C "${iw}" status --porcelain | head -1)" ] || die "集成 worktree 有未提交的修改，没有合入：${iw}"
      if git -C "${iw}" merge --no-ff --no-edit -m "Merge ${T_BRANCH}: ${T_TITLE}" "${T_BRANCH}" >/dev/null 2>&1; then
        mc=$(git -C "${iw}" rev-parse --short HEAD)
      else
        cf=$(git -C "${iw}" diff --name-only --diff-filter=U | tr '\n' ' ')
        git -C "${iw}" merge --abort >/dev/null 2>&1
        echo "合入有冲突，已经撤销这次合入，${T_INTO} 保持原样。冲突的文件：${cf}"
        echo "按规则停下来交给用户。"
        return 2
      fi
      ev_add done "${t}"
      win_resolve
      closed=""
      for w in $(awk -F'\t' -v t="${t}" '$5==t {print $1}' "${WIN}"); do
        usage_refresh "${w}"
        [ "$(win_get "${w}" 13)" = - ] || continue
        winid=$(win_get "${w}" 11)
        if [ "$(getv window.auto-close)" = "${ON}" ] && [ "${winid}" != - ] && launcher_ok; then "$(launcher_script close)" "${winid}" >/dev/null 2>&1 || true; fi
        win_set "${w}" 13 "$(now)"; closed="${closed} ${w}"
      done
      echo "已合入：${T_BRANCH}（${T_HEAD}）→ ${T_INTO}，合并提交 ${mc}，在 ${iw}"
      # 票已经合入，它的 worktree 不再需要：干净就删掉，分支保留。窗口留给用户关的时候不删，免得把窗口所在的目录抽掉
      if [ "$(getv worktree.auto-clean)" = "${ON}" ] && [ -n "${T_WT}" ] && [ -d "${T_WT}" ] && [ "${T_WT}" != "${REPO}" ] && [ "${T_WT}" != "${iw}" ]; then
        if [ "$(getv window.auto-close)" != "${ON}" ]; then echo "worktree 先留着（窗口由用户关）：${T_WT}。窗口关掉后运行 agent-loop worktree prune"
        elif git -C "${REPO}" worktree remove "${T_WT}" >/dev/null 2>&1; then echo "已清理 worktree：${T_WT}（分支 ${T_BRANCH} 保留，需要时 git worktree add 重建）"
        else echo "worktree 没有清理：${T_WT}（git 拒绝了，多半是有没提交或没跟踪的文件；没有强制删除）"; fi
      fi
      echo "已登记完成时间。${closed:+已登记关窗：${closed# }$( [ "$(getv window.auto-close)" = "${ON}" ] && echo "（窗口已关）" || echo "（窗口留给用户关）" )}" ;;
    open)
      [ -n "${pf}" ] || die "要给 --prompt <提示文件>。提示里可以写 {{WORKTREE}}、{{BRANCH}}、{{BASE}}、{{BASE_COMMIT}}、{{TICKET_FILE}}，命令会替换成实际值。"
      [ "${pf}" = - ] || [ -f "${pf}" ] || die "提示文件不存在：${pf}"
      T_FILE=$(ticket_file "${t}") || die "找不到票文件：${t}"
      nn=${t##*-}; st=$(ticket_stage "${t}")
      hb=$(ticket_branch "${T_FILE}"); hw=$(ticket_worktree "${T_FILE}")
      pre=$(profile_item '分支前缀'); fixb=$(profile_item '修复分支名'); root=$(worktree_root)
      if [ "${fix}" = yes ]; then
        [ -n "${fixb}" ] || die "参数文件里没有填修复分支名。用 --branch、--base、--dir 指定，或者先补齐参数文件。"
        : "${br:=${hb:-${fixb}-${nn}}}"; : "${base:=${fixb}}"; : "${dir:=${hw:-${root}/fix-${nn}}}"
      else
        [ -n "${pre}" ] || [ -n "${br}${hb}" ] || die "参数文件里没有填分支前缀。用 --branch、--base、--dir 指定，或者先补齐参数文件。"
        : "${br:=${hb:-${pre}${st}-${nn}}}"; : "${base:=${pre}${st}}"; : "${dir:=${hw:-${root}/${st}-${nn}}}"
      fi
      if [ ! -d "${dir}" ]; then
        git -C "${REPO}" rev-parse --verify -q "${base}" >/dev/null || die "没有基点分支：${base}。用 --base <分支> 指定。"
        mkdir -p "$(dirname "${dir}")"
        if git -C "${REPO}" rev-parse --verify -q "${br}" >/dev/null; then git -C "${REPO}" worktree add "${dir}" "${br}" >/dev/null 2>&1 || die "建 worktree 失败：${dir}"
        else git -C "${REPO}" worktree add "${dir}" -b "${br}" "${base}" >/dev/null 2>&1 || die "建 worktree 失败：${dir}"; fi
        # 本机专用文件复制进去；参数文件只留主工作树一份
        profile_items '本机专用文件' > "${VALS}.lf"
        while IFS= read -r p; do
          p=${p%/}; [ -n "${p}" ] && [ -e "${REPO}/${p}" ] || continue
          mkdir -p "$(dirname "${dir}/${p}")"; cp -R "${REPO}/${p}" "${dir}/${p}"
        done < "${VALS}.lf"
        rm -f "${dir}/${PROFILE_REL}"
        echo "已建 worktree：${dir}（分支 ${br}，基于 ${base}）"
      else
        echo "沿用已有的 worktree：${dir}"
      fi
      dir=$(cd -P "${dir}" && pwd -P)
      basec=$(git -C "${REPO}" rev-parse --short "${base}" 2>/dev/null)
      # 票头补上 Branch 和 Worktree 两行，核对和合入命令靠它们
      if [ -z "${hb}" ]; then
        awk -v b="Branch: ${br}（基点 ${base} ${basec}）" -v w="Worktree: ${dir}" '
          {print} !done && /^\**Status:?\**:?/ {print b; print w; done = 1}' "${T_FILE}" > "${VALS}.th" && cat "${VALS}.th" > "${T_FILE}"
      fi
      rp=${pf}
      if [ "${pf}" != - ]; then
        rp="${TMPDIR:-/tmp}/agent-loop-${t}-${step}-$$.prompt"
        awk -v w="${dir}" -v b="${br}" -v s="${base}" -v c="${basec}" -v f="${T_FILE}" '
          { gsub(/\{\{WORKTREE\}\}/, w); gsub(/\{\{BRANCH\}\}/, b); gsub(/\{\{BASE\}\}/, s); gsub(/\{\{BASE_COMMIT\}\}/, c); gsub(/\{\{TICKET_FILE\}\}/, f); print }' "${pf}" > "${rp}"
      fi
      # shellcheck disable=SC2086
      if [ -n "${model}" ]; then window_open --feature "${FEATURE}" --step "${step}" --ticket "${t}" --dir "${dir}" --prompt "${rp}" --model "${model}" ${again}
      else window_open --feature "${FEATURE}" --step "${step}" --ticket "${t}" --dir "${dir}" --prompt "${rp}" ${again}; fi ;;
    *) die "未知动作：${act}。可用：open、verify、merge" ;;
  esac
}

# ---------- worktree 的清理 ----------
# 只删「分支已经合入别处、工作区干净、没有窗口还开着」的票 worktree；只删 worktree，保留分支；不强制删除。
wt_has_open_window() {  # 目录 → 任何功能的台账里有没有它还开着的窗口
  for wf in "${REPO}/$(task_dir "${REPO}")"/*/ledger/windows.tsv "${REPO}/$(task_dir "${REPO}")"/.agent-loop/windows.tsv; do
    [ -f "${wf}" ] || continue
    awk -F'\t' -v d="$1" '$9==d && $13=="-" {f=1} END {exit !f}' "${wf}" && return 0
  done
  return 1
}
# 一个 worktree 能不能清理：能就返回 0；不能时把原因写进 WT_WHY
wt_prunable() {  # 目录 分支
  WT_WHY=""
  [ -n "$2" ] || { WT_WHY="没有检出分支"; return 1; }
  case $(basename "$1") in *-integration|*-test) WT_WHY="集成或测试用的 worktree，保留"; return 1 ;; esac
  for keep in "$(getv branch.feature)" "$(getv branch.shared)" "$(profile_item '修复分支名')"; do
    [ -n "${keep}" ] && [ "$2" = "${keep}" ] && { WT_WHY="是 ${keep} 分支，保留"; return 1; }
  done
  wt_has_open_window "$1" && { WT_WHY="有窗口还开着"; return 1; }
  [ -z "$(git -C "$1" status --porcelain 2>/dev/null | head -1)" ] || { WT_WHY="有未提交的修改"; return 1; }
  others=$(git -C "${REPO}" branch --contains "$2" --format='%(refname:short)' 2>/dev/null | grep -vxF "$2" | head -1)
  [ -n "${others}" ] || { WT_WHY="分支还没有合入任何其他分支"; return 1; }
  return 0
}
cmd_worktree() {
  need_profile
  act=${1:-}; [ $# -gt 0 ] && shift
  yes=no; for a in "$@"; do case ${a} in --yes) yes=yes ;; *) die "未知参数：${a}" ;; esac; done
  [ "${act}" = prune ] || die "用法：agent-loop worktree prune [--yes]    列出可以清理的票 worktree（分支已合入、工作区干净、没有窗口开着），确认后删除；只删 worktree，保留分支"
  git -C "${REPO}" worktree list --porcelain | awk '/^worktree / {w = substr($0, 10)} $1 == "branch" {sub(/^refs\/heads\//, "", $2); print w "\t" $2} $1 == "detached" {print w "\t"}' > "${VALS}.wl"
  : > "${VALS}.wc"; skipped=0
  while IFS="${TAB}" read -r w b; do
    [ "${w}" = "${REPO}" ] && continue
    if wt_prunable "${w}" "${b}"; then printf '%s\t%s\n' "${w}" "${b}" >> "${VALS}.wc"
    else skipped=$((skipped+1)); echo "保留  ${w}（${b:-无分支}）：${WT_WHY}"; fi
  done < "${VALS}.wl"
  n=$(grep -c . "${VALS}.wc")
  if [ "${n}" -eq 0 ]; then echo "没有可以清理的 worktree。"; return 0; fi
  echo; echo "可以清理的 worktree（${n} 个；分支已合入、工作区干净、没有窗口开着）："
  while IFS="${TAB}" read -r w b; do printf '  %s  %s  %s\n' "$(du -sh "${w}" 2>/dev/null | cut -f1)" "${w}" "${b}"; done < "${VALS}.wc"
  if [ "${yes}" = no ]; then
    [ -t 0 ] || { echo "加 --yes 才会删除。只删 worktree，保留分支。"; return 0; }
    ask "删除这 ${n} 个 worktree？只删 worktree，保留分支。y / n："
    case ${REPLY} in y|Y) ;; *) echo "已取消，没有删除任何东西。"; return 0 ;; esac
  fi
  ok=0
  while IFS="${TAB}" read -r w b; do
    if git -C "${REPO}" worktree remove "${w}" >/dev/null 2>&1; then ok=$((ok+1)); echo "已删除  ${w}（分支 ${b} 保留）"
    else echo "没删掉  ${w}：git 拒绝了（多半是有没提交或没跟踪的文件），没有强制删除"; fi
  done < "${VALS}.wc"
  echo "删除了 ${ok} 个，保留 ${skipped} 个。要重建某个 worktree：git worktree add <目录> <分支>"
}
