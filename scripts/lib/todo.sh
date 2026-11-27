# 待办清单：<功能目录>/todo.md，由本命令维护。由 agent-loop 主脚本 source。
# 两类：遗留（现在不做、以后必须做）和想法（现在不做、以后做不做没定）。
# 表格列：编号 | 类别 | 状态 | 建议时限 | 记录时间 | 记录人 | 内容 | 去向
T_OPEN='未处理'
T_CLOSED='已关闭'

todo_load() {  # → ${VALS}.td，制表符分隔
  : > "${VALS}.td"
  [ -f "${FD}/todo.md" ] || return 0
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^\| T-[0-9]+ / { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", trim($2), trim($3), trim($4), trim($5), trim($6), trim($7), trim($8), trim($9) }' "${FD}/todo.md" > "${VALS}.td"
}
todo_save() {
  {
    echo "# 待办清单：${FEATURE}"
    echo
    echo "由 \`agent-loop todo\` 维护，请勿手工编辑。只收不卡当前任何一张票的事；卡着某张票的事在开窗清单里。"
    echo "遗留 = 现在不做、以后必须做；想法 = 现在不做、以后做不做还没定。建议时限只是提醒，是否执行由用户决定。"
    echo
    echo "| 编号 | 类别 | 状态 | 建议时限 | 记录时间 | 记录人 | 内容 | 去向 |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
    awk -F'\t' '{ printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8 }' "${VALS}.td"
  } > "${FD}/todo.md"
}
# 表格里不能有竖线和换行
todo_clean() { printf '%s' "$1" | tr '\n\t' '  ' | sed 's/|/／/g'; }
todo_due_ok() { case $1 in 合并前|功能结束前|上生产前|-) return 0 ;; *) return 1 ;; esac; }
todo_set() {  # 编号 列 值
  awk -F'\t' -v OFS='\t' -v i="$1" -v c="$2" -v v="$3" '$1==i {$c=v} {print}' "${VALS}.td" > "${VALS}.tn" && mv "${VALS}.tn" "${VALS}.td"
}
todo_get() { awk -F'\t' -v i="$1" -v c="$2" '$1==i {print $c; exit}' "${VALS}.td"; }
todo_count_line() {
  awk -F'\t' -v o="${T_OPEN}" '
    $3==o && $2=="遗留" { m++; if ($4!="-") { if (!($4 in D)) ds[++nd]=$4; D[$4]++ } }
    $3==o && $2=="想法" { i++ }
    END {
      if (!m && !i) exit
      s = "待办："
      if (m) { s = s "遗留 " m " 条"; if (nd) { s = s "（"; for (k = 1; k <= nd; k++) s = s (k > 1 ? "、" : "") D[ds[k]] " 条建议" ds[k] "处理"; s = s "）" } }
      if (i) s = s (m ? "、" : "") "想法 " i " 条"
      print s }' "${VALS}.td"
}
todo_print() {  # all | open | <时限>
  awk -F'\t' -v mode="$1" -v o="${T_OPEN}" '
    { if (mode == "open" && $3 != o) next
      if (mode != "open" && mode != "all" && !($3 == o && $2 == "遗留" && $4 == mode)) next
      printf "%s 〔%s〕%s %s  （%s，%s）%s\n", $1, $2, ($4 == "-" ? "" : "〔建议" $4 "处理〕"), $7, $6, $5, ($8 == "-" ? "" : "  → " $8); n++ }
    END { if (!n) print "（没有）" }' "${VALS}.td"
}

cmd_todo() {
  need_profile
  feat=""; must=no; due=-; by=用户; text=""; act=add; id=""; to=""; mode=open; note=""
  [ $# -eq 0 ] && act=list
  while [ $# -gt 0 ]; do
    case $1 in
      --feature) feat=${2:-}; shift ;;
      --must) must=yes ;;
      --due) due=${2:-}; shift ;;
      --by) by=${2:-}; shift ;;
      --all) act=list; mode=all ;;
      --count) act=count ;;
      --due-now) act=list; mode=${2:-}; shift ;;
      --to) to=${2:-}; shift ;;
      close|due) if [ -z "${text}" ] && [ "${act}" = add ] && [ -z "${id}" ]; then act=$1; id=${2:-}; shift; else text=$1; fi ;;
      -*) die "未知参数：$1" ;;
      *) if [ "${act}" = close ] || [ "${act}" = due ]; then note=$1; else text=$1; fi ;;
    esac
    shift
  done
  [ "${act}" = add ] && [ -z "${text}" ] && act=list
  need_feature "${feat}"; todo_load
  case ${act} in
    list)
      if [ "${mode}" = open ] || [ "${mode}" = all ]; then todo_count_line; else todo_due_ok "${mode}" || die "时限只能是：合并前、功能结束前、上生产前"; fi
      todo_print "${mode}" ;;
    count) todo_count_line ;;
    add)
      todo_due_ok "${due}" || die "时限只能是：合并前、功能结束前、上生产前"
      n=$(awk -F'\t' '{ x = substr($1, 3) + 0; if (x > m) m = x } END { print m + 1 }' "${VALS}.td")
      id=$(printf 'T-%03d' "${n}"); kind=想法; [ "${must}" = yes ] && kind=遗留
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t-\n' "${id}" "${kind}" "${T_OPEN}" "${due}" "$(now)" "$(todo_clean "${by}")" "$(todo_clean "${text}")" >> "${VALS}.td"
      todo_save; echo "已记入 ${id}〔${kind}〕：${FD}/todo.md" ;;
    due)
      [ -n "${id}" ] && [ -n "${note}" ] || die "用法：agent-loop todo due <编号> <合并前|功能结束前|上生产前|->"
      [ -n "$(todo_get "${id}" 1)" ] || die "没有这一条：${id}"
      todo_due_ok "${note}" || die "时限只能是：合并前、功能结束前、上生产前，或 - 清空"
      todo_set "${id}" 4 "${note}"; todo_save; echo "${id} 的建议时限改为：${note}" ;;
    close)
      [ -n "${id}" ] && [ -n "${to}" ] || die "用法：agent-loop todo close <编号> --to <spec|ticket|feature|done|drop|keep> [说明]"
      kind=$(todo_get "${id}" 2); [ -n "${kind}" ] || die "没有这一条：${id}"
      case ${to} in
        spec) d="并入 spec" ;; ticket) d="开成票" ;; feature) d="另开功能" ;; done) d="已完成" ;; keep) d="继续留着" ;;
        drop) d="不做"; [ "${kind}" = 遗留 ] && [ -z "${note}" ] && die "遗留条目要关闭而不做时，必须写明用户说的原因：agent-loop todo close ${id} --to drop \"<原因>\"" ;;
        *) die "去向只能是：spec（并入下一阶段 spec）、ticket（开成票）、feature（另开功能）、done（已完成）、drop（不做）、keep（继续留着）" ;;
      esac
      todo_set "${id}" 8 "${d}${note:+：$(todo_clean "${note}")}（$(now)）"
      [ "${to}" = keep ] || todo_set "${id}" 3 "${T_CLOSED}"
      todo_save; echo "${id}：${d}" ;;
  esac
}
