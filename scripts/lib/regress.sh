# 回归测试的统计：读 <功能目录>/regression/<阶段>-plan.md 和 <阶段>-result.md，生成 summary.md。由 agent-loop 主脚本 source。
# 约定（见 references/regression-test.md）：
#   计划里每个测试项是一行表格：| 编号 | 级别(必测/选测) | ...
#   结果里每条结论是一行表格：  | 编号 | 结论(通过/失败/未测/不测) | ...   同一编号出现多次时以最后一次为准
cmd_regress() {
  need_profile
  feat=""; while [ $# -gt 0 ]; do case $1 in --feature) feat=${2:-}; shift ;; *) die "未知参数：$1" ;; esac; shift; done
  need_feature "${feat}"
  rd="${FD}/regression"
  ls "${rd}"/*-plan.md >/dev/null 2>&1 || die "还没有测试计划：${rd}/<阶段>-plan.md"
  : > "${VALS}.rs"
  for plan in "${rd}"/*-plan.md; do
    st=$(basename "${plan}" -plan.md); res="${rd}/${st}-result.md"; [ -f "${res}" ] || res=/dev/null
    awk -F'|' -v st="${st}" -v fres="${res}" '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      function isid(s) { return s ~ /^[A-Za-z][A-Za-z0-9]*-[0-9]+[A-Za-z0-9.-]*$/ }
      BEGIN {
        while ((getline l < fres) > 0) { n = split(l, a, "|"); if (n < 4) continue; id = trim(a[2]); if (!isid(id)) continue
          c = trim(a[3]); if (c ~ /^通过/) c = "通过"; else if (c ~ /^失败/) c = "失败"; else if (c ~ /^未测/) c = "未测"; else if (c ~ /^不测/) c = "不测"; else continue
          R[id] = c }
        lv[1] = "必测"; lv[2] = "选测" }
      /^\|/ { id = trim($2); if (!isid(id) || (id in SEEN)) next; SEEN[id] = 1
        l = trim($3); if (l !~ /^选测/) l = "必测"; else l = "选测"
        c = (id in R) ? R[id] : "未执行"
        T[l]++; C[l, c]++
        if (c == "失败") fail = fail " " id; if (c == "未测") skip = skip " " id }
      END {
        for (i = 1; i <= 2; i++) { l = lv[i]; if (!T[l]) continue
          printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n", st, l, T[l], C[l, "通过"], C[l, "失败"], C[l, "未测"], C[l, "不测"], C[l, "未执行"] }
        if (fail != "") printf "%s\t失败项\t%s\n", st, fail
        if (skip != "") printf "%s\t未测项\t%s\n", st, skip }' "${plan}" >> "${VALS}.rs"
  done
  {
    echo "# 回归测试统计：${FEATURE}"
    echo
    echo "由 \`agent-loop regress\` 根据各阶段的测试计划和结果生成于 $(now)，请勿手工编辑。未执行 = 计划里有、结果里还没有结论。"
    echo
    echo "| 阶段 | 级别 | 总数 | 通过 | 失败 | 未测 | 不测 | 未执行 |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
    awk -F'\t' '$2=="必测" || $2=="选测" { printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8 }' "${VALS}.rs"
  } > "${rd}/summary.md"
  awk -F'\t' '
    $2=="必测" || $2=="选测" { s = $2 " " $3 " 项，通过 " $4 "、失败 " $5 "、未测 " $6 "、不测 " $7 "、未执行 " $8; L[$1] = (($1 in L) ? L[$1] "；" : "") s; if (!($1 in O)) { O[$1] = 1; st[++n] = $1 } }
    $2=="失败项" { F[$1] = $3 } $2=="未测项" { K[$1] = $3 }
    END { for (i = 1; i <= n; i++) { print st[i] " 回归：" L[st[i]]; if (st[i] in F) print "  失败：" F[st[i]]; if (st[i] in K) print "  未测：" K[st[i]] } }' "${VALS}.rs"
  echo "统计已写入：${rd}/summary.md"
}
