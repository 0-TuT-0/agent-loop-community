#!/bin/bash
# agent-loop 命令的离线测试：在临时仓库里跑，不开窗口，不碰真实项目。
# 用法：tests/cli.sh    退出码 0 = 全部通过
set -uo pipefail
A="$(cd -P "$(dirname "$0")/.." && pwd -P)/scripts/agent-loop"
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-loop-test.XXXXXX"); T=$(cd -P "${T}" && pwd -P)
trap 'rm -rf "${T}"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); echo "失败：$1"; }
check() { if eval "$2"; then ok; else no "$1"; fi; }
val() { /bin/bash "${A}" show | awk -F'|' -v k="$1" 'BEGIN{k="`" k "`"} { key=$3; gsub(/ /,"",key); if (key==k) { v=$4; gsub(/^ +| +$/,"",v); print v } }'; }

R="${T}/repo"; mkdir -p "${R}"; cd "${R}"
git init -q; git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
git branch -m main; git branch shared-env
P=docs/agents/loop-profile.md

/bin/bash "${A}" init --defaults >/dev/null 2>&1; check "没有 mattpocock 初始化时退出码 3" '[ $? -eq 3 ]'
check "此时不生成参数文件" '[ ! -e ${P} ]'
mkdir -p docs/agents; echo "# Issue tracker: Local Markdown" > docs/agents/issue-tracker.md

/bin/bash "${A}" init --defaults >/dev/null 2>&1; check "默认初始化成功" '[ $? -eq 0 ] && [ -f ${P} ]'
check "默认开发模型" '[ "$(val model.dev)" = codex-sol-medium ]'
check "默认高风险计划模型" '[ "$(val model.plan)" = claude-fable ]'
check "计划模型的说明带计划模式" 'grep -F "model.plan" ${P} | grep -qF -- "--permission-mode plan"'
check "默认审计模型" '[ "$(val model.audit)" = codex-astra-high ]'
check "默认合并模型" '[ "$(val model.merge)" = claude-opus ]'
check "feature 分支取当前分支" '[ "$(val branch.feature)" = main ]'
check "自动接续默认是自动" '[ "$(val flow.auto-continue)" = 自动 ]'
check "自动关窗默认关闭" '[ "$(val window.auto-close)" = 关闭 ]'
check "功能命名默认建议后确认" '[ "$(val feature.naming)" = 建议后确认 ]'
check "任务目录加进本机排除" 'grep -qxF "/.scratch/" .git/info/exclude'
check "可选窗口默认关闭" '[ "$(val window.maintainer)" = 关闭 ] && [ "$(val window.error-intake)" = 关闭 ]'
check "AI文件不提交默认启用" '[ "$(val guard.ai-files-local)" = 启用 ]'
check "待完善项 18 个" '[ "$(grep -cF 【待完善】 ${P})" -eq 18 ]'
check "参数文件里没有本机用户目录" '! grep -qF "${HOME}" ${P}'
check "索引只有一份" '[ "$(grep -c "^### Agent loop" AGENTS.md)" -eq 1 ]'
check "索引里没有本机用户目录" '! grep -qF "${HOME}" AGENTS.md'
check "CLAUDE.md 指向 AGENTS.md" 'grep -qx "@AGENTS.md" CLAUDE.md'
check "本机排除已加入" 'grep -qxF "/docs/agents/" .git/info/exclude'
/bin/bash "${A}" init --defaults >/dev/null 2>&1
check "重复初始化后索引仍只有一份" '[ "$(grep -c "^### Agent loop" AGENTS.md)" -eq 1 ]'

/bin/bash "${A}" set 开发模型 claude-opus >/dev/null 2>&1
check "按名称改设置，只改到这一项" '[ "$(val model.dev)" = claude-opus ] && [ "$(val coordinator)" = claude ] && [ "$(val model.spec)" = claude-fable ]'
/bin/bash "${A}" set model.dev codex-sol-medium >/dev/null 2>&1; check "按键改设置" '[ "$(val model.dev)" = codex-sol-medium ]'
/bin/bash "${A}" set 开发模型 nope >/dev/null 2>&1; check "无效模型被拒绝" '[ $? -ne 0 ] && [ "$(val model.dev)" = codex-sol-medium ]'
/bin/bash "${A}" set 总控 codex >/dev/null 2>&1; check "总控可以设为 Codex" '[ "$(val coordinator)" = codex ]'
/bin/bash "${A}" set 总控 claude >/dev/null 2>&1; check "总控改回 Claude" '[ "$(val coordinator)" = claude ]'
check "默认启动器是 iterm" '[ "$(val launcher)" = iterm ]'
check "公共代码里没有写死任何启动器" '! grep -n -i "iterm" "${A}" "$(dirname "${A}")"/lib/*.sh | grep -v "launcher|启动器|choice|iterm|" | grep -q .'
/bin/bash "${A}" set 启动器 nope >/dev/null 2>&1; check "清单里没有的启动器被拒绝" '[ $? -ne 0 ] && [ "$(val launcher)" = iterm ]'
/bin/bash "${A}" set 开发模型 "custom:mycli --flag" >/dev/null 2>&1; check "自定义启动命令" 'grep -F "model.dev" ${P} | grep -qF "mycli --flag"'
/bin/bash "${A}" set 开发模型 codex-sol-medium >/dev/null 2>&1
/bin/bash "${A}" set 自动接续 需确认 >/dev/null 2>&1; check "自动接续改为需确认" '[ "$(val flow.auto-continue)" = 需确认 ]'
/bin/bash "${A}" set 自动接续 随便 >/dev/null 2>&1; check "自动接续的无效取值被拒绝" '[ $? -ne 0 ] && [ "$(val flow.auto-continue)" = 需确认 ]'
/bin/bash "${A}" set 共享环境分支 shared-env >/dev/null 2>&1; check "设置共享环境分支" '[ "$(val branch.shared)" = shared-env ]'
/bin/bash "${A}" set 共享环境分支 - >/dev/null 2>&1; check "清空一项" '[ -z "$(val branch.shared)" ]'
/bin/bash "${A}" set Codex沙箱 workspace-write >/dev/null 2>&1
check "沙箱取值写进启动命令" 'grep -F "model.dev" ${P} | grep -qF -- "-s workspace-write"'
check "变更记录有记录" 'grep -qF "开发模型 由「codex-sol-medium」改为「claude-opus」" ${P}'

printf '\n## 后加的一节\n\n内容\n' >> ${P}
/bin/bash "${A}" set 窗口上限 5 >/dev/null 2>&1
check "变更记录写在自己那一节里，不写到后加的一节后面" '[ "$(tail -1 ${P})" = 内容 ] && awk "/^## 变更记录/{s=1;next} /^## /{s=0} s" ${P} | grep -qF "窗口上限 由「空」改为「5」"'
check "新记录排在这一节已有记录之后" '[ "$(awk "/^## 变更记录/{s=1;next} /^## /{s=0} s && /^- /" ${P} | tail -1 | grep -c 窗口上限)" -eq 1 ]'
/bin/bash "${A}" set 窗口上限 - >/dev/null 2>&1
echo n | /bin/bash "${A}" set AI文件不提交 关闭 >/dev/null 2>&1; check "不确认是个人项目时保持启用" '[ "$(val guard.ai-files-local)" = 启用 ]'
/bin/bash "${A}" set AI文件不提交 关闭 --personal >/dev/null 2>&1; check "个人项目可以关闭" '[ "$(val guard.ai-files-local)" = 关闭 ]'
/bin/bash "${A}" set AI文件不提交 启用 >/dev/null 2>&1; check "重新启用不需要确认" '[ "$(val guard.ai-files-local)" = 启用 ]'

git worktree add -q "${T}/wt" -b wt-branch >/dev/null 2>&1
( cd "${T}/wt" && /bin/bash "${A}" set 窗口上限 2 >/dev/null 2>&1 )
check "在 worktree 里改设置，写到主工作树" '[ "$(val window.limit)" = 2 ] && [ ! -e "${T}/wt/${P}" ]'

/bin/bash "${A}" open 错误对接 --print >/dev/null 2>&1; check "未启用的窗口拒绝开启" '[ $? -ne 0 ]'
/bin/bash "${A}" set 错误对接窗口 启用 >/dev/null 2>&1
out=$(/bin/bash "${A}" open 错误对接 --print 2>&1); check "启用后给出启动命令" 'echo "${out}" | grep -qF "claude --model claude-fable-5-2"'
out=$(/bin/bash "${A}" open 规范维护 --print 2>&1); check "有待完善项时规范维护窗口可直接开" 'echo "${out}" | grep -qF "claude --model claude-fable-5-2"'

out=$(/bin/bash "${A}" start demo --print 2>&1); check "还有待完善项时不启动总控" '[ $? -ne 0 ] && echo "${out}" | grep -qF "待完善"'
sed -i.bak 's/【待完善】/无/g' ${P} && rm -f ${P}.bak
/bin/bash "${A}" set 功能命名 总控确定 >/dev/null 2>&1; check "功能命名改为总控确定" '[ "$(val feature.naming)" = 总控确定 ]'
/bin/bash "${A}" set 自动关窗 启用 >/dev/null 2>&1; check "自动关窗改为启用" '[ "$(val window.auto-close)" = 启用 ]'
out=$(/bin/bash "${A}" start demo --print 2>&1); check "新功能给出启动命令" 'echo "${out}" | grep -qF "claude --model claude-fable-5-2" && echo "${out}" | grep -qF "/agent-loop demo"'
check "只打印时不建目录" '[ ! -d .scratch/demo ]'
/bin/bash "${A}" start "bad name" --print >/dev/null 2>&1; check "不合法的功能名被拒绝" '[ $? -ne 0 ]'
mkdir -p .scratch/demo; printf -- '- 总控会话：x（sessionId：00000000-0000-0000-0000-000000000000，更新于 2026-01-01 00:00）\n' > .scratch/demo/dev-plan.md
out=$(/bin/bash "${A}" start demo --print 2>&1); check "登记的会话找不到记录时开新的" 'echo "${out}" | grep -qF "/agent-loop demo"'

# ---------- 第二期：开窗登记、票台账、用量、待办、监视、回归统计 ----------
export AGENT_LOOP_NO_LAUNCH=1                      # 不真的开窗口
FH="${T}/home"; mkdir -p "${FH}/.claude/projects/x" "${FH}/.codex/sessions/2026/01/01"
export CODEX_HOME="${FH}/.codex"
al() { HOME="${FH}" /bin/bash "${A}" "$@"; }       # 会话记录从假的用户目录里读
echo '{}' > "${FH}/.claude/projects/x/00000000-0000-0000-0000-000000000000.jsonl"
out=$(al start demo --print 2>&1); check "Claude 总控：登记的会话有记录时恢复它" 'echo "${out}" | grep -qF -- "--resume 00000000-0000-0000-0000-000000000000"'
out=$(al start demo --new --print 2>&1); check "Claude 总控：--new 不恢复登记的会话" '! echo "${out}" | grep -qF -- "--resume" && echo "${out}" | grep -qF "/agent-loop demo"'
rm -f "${FH}/.claude/projects/x/00000000-0000-0000-0000-000000000000.jsonl"
F=.scratch/demo; mkdir -p ${F}/p1/issues
printf '# 01 甲\n\nStatus: claimed\nRisk: 高（改动共享模块）\n\n## Comments\n\n### 待裁决 1\n\n### 裁决 1\n内容\n' > ${F}/p1/issues/01-a.md
printf '# 02 乙\n\nStatus: claimed\nRisk: 低\n' > ${F}/p1/issues/02-b.md

out=$(al window open --step plan --ticket p1-01 --dir "${R}" --prompt - 2>&1)
check "开窗：计划窗口带计划模式和指定的会话 ID" 'echo "${out}" | grep -qF -- "--permission-mode plan" && echo "${out}" | grep -qF -- "--session-id"'
check "开窗：输出窗口编号" 'echo "${out}" | grep -qx "window: W-001"'
SID1=$(echo "${out}" | sed -n "s/^session: //p")
check "开窗：登记了一行，阶段取自票号" '[ "$(cut -f4,5,6,7 ${F}/ledger/windows.tsv)" = "p1	p1-01	plan	claude-fable" ]'
al window open --step plan --ticket p1-01 --dir "${R}" --prompt - >/dev/null 2>&1; check "同一张票同一环节重复开窗被拒绝" '[ $? -ne 0 ] && [ "$(grep -c . ${F}/ledger/windows.tsv)" -eq 1 ]'
al window close p1-01 >/dev/null 2>&1; check "按票号关窗" '[ "$(cut -f13 ${F}/ledger/windows.tsv)" != - ]'
out=$(al window open --step dev --ticket p1-01 --dir "${R}" --prompt - 2>&1); check "开发窗口用开发模型" 'echo "${out}" | grep -qF "codex -c check_for_update_on_startup=false -m gpt-6.2-sol" && [ "$(sed -n 2p ${F}/ledger/windows.tsv | cut -f8,10)" = "codex	-" ]'
al window open --step dev --ticket p1-02 --dir "${R}" --prompt - --model nope >/dev/null 2>&1; check "清单里没有的模型被拒绝" '[ $? -ne 0 ]'
al window open --step spec --stage p1 --dir "${R}" --prompt - >/dev/null 2>&1; check "不属于票的窗口也登记" '[ "$(sed -n 3p ${F}/ledger/windows.tsv | cut -f4,5,6)" = "p1	-	spec" ]'
al window register --step coordinator --session 11111111-1111-1111-1111-111111111111 >/dev/null 2>&1; check "登记已在运行的总控" '[ "$(sed -n 4p ${F}/ledger/windows.tsv | cut -f6,10)" = "coordinator	11111111-1111-1111-1111-111111111111" ]'

# 假的会话记录：Claude 同一条回复出现两次只算一次；Codex 取最后一条累计值
{
  echo '{"type":"assistant","message":{"id":"msg_A","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5,"iterations":[{"input_tokens":10}]}}}'
  echo '{"type":"assistant","message":{"id":"msg_A","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5}}}'
  echo '{"type":"user","message":{"content":"x"}}'
  echo '{"type":"assistant","message":{"id":"msg_B","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"output_tokens":20}}}'
} > "${FH}/.claude/projects/x/${SID1}.jsonl"
CS=aaaaaaaa-0000-0000-0000-000000000001
{
  echo '{"type":"session_meta","payload":{"session_id":"'${CS}'","cwd":"'${R}'"}}'
  echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":300,"output_tokens":40}}}}'
  echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":600,"output_tokens":70}}}}'
} > "${FH}/.codex/sessions/2026/01/01/rollout-2099-01-01T00-00-00-${CS}.jsonl"

al ledger done p1-01 >/dev/null 2>&1
check "完成时对上 Codex 会话" '[ "$(sed -n 2p ${F}/ledger/windows.tsv | cut -f10)" = "${CS}" ]'
check "Claude 用量按回复去重" '[ "$(grep "^W-001" ${F}/ledger/usage.tsv | cut -f3,4,5)" = "111	3000	25" ]'
check "Codex 用量取最后一条，输入不含缓存" '[ "$(grep "^W-002" ${F}/ledger/usage.tsv | cut -f3,4,5)" = "300	600	70" ]'
al ledger rework p1-01 >/dev/null; al ledger plan-revise p1-01 >/dev/null
al ledger audit p1-01 阻塞=1 应修=2 >/dev/null; al ledger audit p1 应修=1 >/dev/null
al ledger audit p1-01 阻塞 >/dev/null 2>&1; check "审计问题数量写错被拒绝" '[ $? -ne 0 ]'
al ledger source p1-02 p1-01 >/dev/null
out=$(al ledger 2>&1)
row=$(echo "${out}" | grep "^| p1-01 ")
check "台账：风险、执行链、裁决、返工、计划修改" 'echo "${row}" | grep -qF "| 高 | plan Claude Fable 5.2 → dev Codex gpt-6.2-sol（medium） |" && echo "${row}" | grep -qF "| 1 | 1 | 1 | 阻塞 1、应修 2 |"'
check "台账：用量是这张票各窗口之和" 'echo "${row}" | grep -qF "| 411 | 95 | 3.6k |"'
check "台账：归不到单张票的审计问题记在阶段名下" 'echo "${out}" | grep -q "^| p1（归不到单张票） .*应修 1"'
check "台账：修复票注明来源票" 'echo "${out}" | grep "^| p1-02 " | grep -qF "| p1-01 |"'
check "台账：生成给人看的文件" 'grep -qF "| p1-01 |" ${F}/ledger.md'
out=$(al usage p1 2>&1)
check "汇总：标题行和按模型的行" 'echo "${out}" | grep -qF "p1 票统计：2 张票（高风险 1）" && echo "${out}" | grep -q "^| Codex gpt-6.2-sol（medium） | 1 | 1 | 1 | 3 | 300 | 70 | 600 |"'
check "汇总：其他窗口单列" 'echo "${out}" | grep -q "^| 其他窗口：spec"'
al window open --step audit --ticket p1-01 --dir "${R}" --prompt - >/dev/null 2>&1
check "汇总：票算在开发模型上，后开的审计窗口不改变归属" 'al usage p1 | grep -q "^| Codex gpt-6.2-sol（medium） | 1 | 1 | 1 | 3 |"'
al window close p1-01 >/dev/null 2>&1; check "按票号关窗：关的是还开着的里面最近开的（审计窗口），开发窗口还开着" '[ "$(awk -F"\t" "\$5==\"p1-01\" && \$6==\"audit\" {print \$13}" ${F}/ledger/windows.tsv)" != - ] && [ "$(awk -F"\t" "\$5==\"p1-01\" && \$6==\"dev\" {print \$13}" ${F}/ledger/windows.tsv)" = - ]'
al ledger undo >/dev/null; check "撤销最后一条记录" '! grep -q "source" ${F}/ledger/events.tsv'

# 可选窗口：项目级的记录，按窗口名单独显示
al set 规范维护窗口 启用 >/dev/null 2>&1
out=$(al open 规范维护 2>&1); MS=$(echo "${out}" | sed -n 's/.*--session-id \([0-9a-f-]*\).*/\1/p' | head -1)
al open 错误对接 >/dev/null 2>&1
check "可选窗口：登记在项目级的记录里，不进功能的台账" '[ "$(cut -f6 .scratch/.agent-loop/windows.tsv | tr "\n" " ")" = "maintainer error-intake " ] && ! grep -q "maintainer" ${F}/ledger/windows.tsv'
echo '{"type":"assistant","message":{"id":"msg_M","usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":50,"output_tokens":3}}}' > "${FH}/.claude/projects/x/${MS}.jsonl"
out=$(al usage 2>&1)
check "可选窗口：按窗口名各列一行" 'echo "${out}" | grep -q "^| 规范维护窗口 | Claude Fable 5.2 | 1 | 7 | 3 | 50 |" && echo "${out}" | grep -q "^| 错误对接窗口 | Claude Fable 5.2 | 1 | - | - | - |"'
check "可选窗口：不计入功能的合计" 'echo "${out}" | grep -q "^| 合计 | 1 | | | | 411 | 95 | 3.6k |"'

# 待办清单
al todo "把图标换成彩色的 | 试试" >/dev/null; al todo "上线前确认入站地址" --must --due 上生产前 --by 总控 >/dev/null; al todo "清理临时 Key" --must >/dev/null
check "待办：默认记成想法，竖线被替换" 'grep -q "^| T-001 | 想法 | 未处理 | - | .* | 用户 | 把图标换成彩色的 ／ 试试 | - |$" ${F}/todo.md'
check "待办：--must 记成遗留并带建议时限" 'grep -q "^| T-002 | 遗留 | 未处理 | 上生产前 | .* | 总控 | 上线前确认入站地址 | - |$" ${F}/todo.md'
check "待办：一行统计" '[ "$(al todo --count)" = "待办：遗留 2 条（1 条建议上生产前处理）、想法 1 条" ]'
al todo "x" --must --due 明天 >/dev/null 2>&1; check "待办：时限只能从固定的几个里选" '[ $? -ne 0 ]'
al todo close T-003 --to drop >/dev/null 2>&1; check "待办：遗留不做时必须写原因" '[ $? -ne 0 ] && grep -q "^| T-003 | 遗留 | 未处理" ${F}/todo.md'
al todo close T-003 --to drop "用户说不再需要" >/dev/null; check "待办：写了原因可以关闭" 'grep -q "^| T-003 | 遗留 | 已关闭 .*不做：用户说不再需要" ${F}/todo.md'
al todo close T-001 --to keep >/dev/null; check "待办：继续留着不关闭" 'grep -q "^| T-001 | 想法 | 未处理 .*继续留着" ${F}/todo.md'
al todo close T-001 --to spec "并入 p2" >/dev/null; al todo due T-002 合并前 >/dev/null
check "待办：改时限" '[ "$(al todo --count)" = "待办：遗留 1 条（1 条建议合并前处理）" ]'
check "待办：按时限列出" 'al todo --due-now 合并前 | grep -qF "T-002"'
check "待办：默认只列未处理的" '! al todo | grep -qF "T-003" && al todo --all | grep -qF "T-003"'

# 常驻监视（通知命令换成写文件）
NF="${T}/notify.log"; printf '#!/bin/bash\necho "$1" >> %s\n' "${NF}" > "${T}/notify.sh"; chmod +x "${T}/notify.sh"
export AGENT_LOOP_NOTIFY_CMD="${T}/notify.sh"
WATCH_BASELINE=1 al watch once >/dev/null; check "监视：记现状时不发通知" '[ ! -s "${NF}" ]'
sed -i.bak 's/^Status: claimed/Status: done/' ${F}/p1/issues/02-b.md; rm -f ${F}/p1/issues/*.bak
al watch once >/dev/null; check "监视：票头变为 done 时通知" 'grep -qF "p1/issues/02-b.md 的票头变为 done" "${NF}"'
al watch once >/dev/null; check "监视：同一状态只通知一次" '[ "$(grep -c . "${NF}")" -eq 1 ]'
printf 'spec\n\nspec 已审定\n' > ${F}/p1/spec.md
al watch once >/dev/null; check "监视：完成标记" 'grep -qF "p1/spec.md 出现完成标记「spec 已审定」" "${NF}"'
mkdir -p ${F}/merges; printf '合并报告\n\n合并完成\n' > ${F}/merges/merge-01.md
al watch once >/dev/null; check "监视：合并报告的完成标记" 'grep -qF "merges/merge-01.md 出现完成标记「合并完成」" "${NF}"'
sed -i.bak 's/^Status: claimed/Status: needs-decision/' ${F}/p1/issues/01-a.md; rm -f ${F}/p1/issues/*.bak
al watch once >/dev/null; al watch expect p1-01 1 >/dev/null
AGENT_LOOP_EXPECT_SECS=0 al watch once >/dev/null; check "监视：裁决送出后超时未接收" 'grep -qF "裁决 1 未被接收" "${NF}"'
check "监视：超时通知后不再重复登记" '[ ! -s ${F}/ledger/expect.tsv ]'
mkdir -p ${F}/regression; printf '### E-01\n现象\n【待总控处理】请开修复票\n' > ${F}/regression/issues-log.md
al watch once >/dev/null; check "监视：可选窗口留的事" 'grep -qF "regression/issues-log.md 里有 1 条标着「待总控处理」" "${NF}"'
n1=$(grep -c . "${NF}"); al watch once >/dev/null; check "监视：同一批留言不重复通知" '[ "$(grep -c . "${NF}")" -eq "${n1}" ]'
sed -i.bak 's/【待总控处理】/【总控已处理 2026-01-01 00:00：已开票】/' ${F}/regression/issues-log.md; rm -f ${F}/regression/*.bak
printf '### E-02\n【待总控处理】\n' >> ${F}/regression/issues-log.md; al watch once >/dev/null
PENDN=$(grep -c . "${NF}"); { printf '说明：前面插入的内容\n\n'; cat ${F}/regression/issues-log.md; } > "${T}/il"; cp "${T}/il" ${F}/regression/issues-log.md; al watch once >/dev/null
check "监视：处理掉旧的之后，新的留言照样通知" '[ "$(grep -c "待总控处理" "${NF}")" -eq 2 ]'
check "监视：留言前面插入别的内容，位置变了也不重复通知" '[ "$(grep -c . "${NF}")" -eq "${PENDN}" ]'
printf '## 第 1 轮\n\n| P1-001 | 通过 | e |\n\n第 1 轮已完成\n' > ${F}/regression/p1-result.md; al watch once >/dev/null; al watch once >/dev/null
check "监视：回归一轮做完只通知一次" '[ "$(grep -c "第 1 轮已完成" "${NF}")" -eq 1 ] && ! grep -q "p1-result.md 出现完成标记「已完成」" "${NF}"'
printf '\n## 第 2 轮\n\n第 2 轮已完成\n' >> ${F}/regression/p1-result.md; al watch once >/dev/null
check "监视：回归的下一轮做完再通知一次" 'grep -q "第 2 轮已完成" "${NF}"'
rm -f ${F}/regression/p1-result.md
echo x > "${T}/rp.md"; out=$(al window open --step regress --stage p1 --dir "${R}" --prompt "${T}/rp.md" --print 2>&1); check "回归执行窗口用测试流程模型" 'echo "${out}" | grep -q "codex"'
# 状态文件丢了：不能把所有旧事件逐条重发
cp ${F}/ledger/watch.state "${T}/state.bak"; : > ${F}/ledger/watch.state; for i in 11 12 13 14 15 16 17 18 19 20 21 22; do printf '# %s\n\nStatus: done\n' ${i} > ${F}/p1/issues/${i}-x.md; done
n0=$(grep -c . "${NF}"); al watch once >/dev/null; n1=$(grep -c . "${NF}")
check "监视：一轮里变化很多时最多逐条发 8 条，其余合成一条提醒" '[ $((n1 - n0)) -eq 9 ] && tail -1 "${NF}" | grep -q "没有逐条通知"'
al watch once >/dev/null; check "监视：没发的那些也记了状态，下一轮不再补发" '[ "$(grep -c . "${NF}")" -eq "${n1}" ]'
rm -f ${F}/p1/issues/1[1-9]-x.md ${F}/p1/issues/2[0-2]-x.md
# 发送失败：这一轮不再尝试，状态不更新，下一轮重试
printf '# 30\n\nStatus: done\n' > ${F}/p1/issues/30-x.md; printf '# 31\n\nStatus: done\n' > ${F}/p1/issues/31-x.md
printf '#!/bin/bash\necho x >> %s\nexit 1\n' "${T}/fail.count" > "${T}/fail.sh"; chmod +x "${T}/fail.sh"
AGENT_LOOP_NOTIFY_CMD="${T}/fail.sh" al watch once >/dev/null; check "监视：发送失败后这一轮只试一次" '[ "$(grep -c . "${T}/fail.count")" -eq 1 ]'
n2=$(grep -c . "${NF}"); al watch once >/dev/null; check "监视：失败的通知下一轮补发" '[ $(( $(grep -c . "${NF}") - n2 )) -eq 2 ]'
rm -f ${F}/p1/issues/30-x.md ${F}/p1/issues/31-x.md
# 一个功能只能有一个监视进程
( HOME="${FH}" /bin/bash "${A}" watch run --feature demo --interval 1 >/dev/null 2>&1 & ); sleep 2
( HOME="${FH}" /bin/bash "${A}" watch run --feature demo --interval 1 >/dev/null 2>&1 & ); sleep 2
check "监视：第二个监视进程自己退出" '[ "$(ps -axo command= | grep -c "[a]gent-loop watch run --feature demo")" -eq 1 ]'
al watch stop >/dev/null 2>&1; sleep 2; check "监视：停止时一个不留" '[ "$(ps -axo command= | grep -c "[a]gent-loop watch run --feature demo")" -eq 0 ] && [ ! -e ${F}/ledger/watch.lock ]'
al watch status >/dev/null 2>&1; check "监视：没有在运行时如实报告" '[ $? -ne 0 ]'
# Claude 总控的等待：同一套检测，有变化就打印并退出
out=$(al watch wait --interval 1 --timeout 2 2>&1); rc=$?; check "等待：给了时限、到点没有变化时报 TIMEOUT，不算失败" '[ "${out}" = TIMEOUT ] && [ ${rc} -eq 0 ]'
printf '# 40\n\nStatus: done\n' > ${F}/p1/issues/40-x.md
out=$(AGENT_LOOP_NOTIFY_CMD=/usr/bin/false al watch wait --interval 1 --timeout 5 2>&1); rc=$?
check "等待：有变化时打印通知并退出，不走发消息那一路" '[ ${rc} -eq 0 ] && echo "${out}" | grep -q "40-x.md 的票头变为 done"'
out=$(al watch wait --interval 1 --timeout 2 2>&1); check "等待：重挂之后同一件事不再报" '[ "${out}" = TIMEOUT ]'
mkdir -p ${F}/p1/reviews; printf 'x\n\n审计完成\n' > ${F}/p1/reviews/40-audit.md; al watch wait --interval 1 --timeout 5 >/dev/null 2>&1
al watch redo p1/reviews/40-audit.md >/dev/null 2>&1; out=$(al watch wait --interval 1 --timeout 2 2>&1)
check "等待：登记返工后文件没变不报" '[ "${out}" = TIMEOUT ]'
printf 'y\n\n审计完成\n' > ${F}/p1/reviews/40-audit.md; out=$(al watch wait --interval 1 --timeout 5 2>&1)
check "等待：返工改完再报一次" 'echo "${out}" | grep -q "40-audit.md 出现完成标记"'
( HOME="${FH}" /bin/bash "${A}" watch wait --feature demo --interval 1 --timeout 6 >/dev/null 2>&1 & ); sleep 2
out=$(al watch wait --interval 1 --timeout 2 2>&1); check "等待：已经有一个在等时不再挂第二个" 'echo "${out}" | grep -q "不用再挂"'
sleep 6; check "等待：结束后不留锁" '[ ! -e ${F}/ledger/watch.wait.lock ]'
rm -f ${F}/p1/issues/40-x.md ${F}/p1/reviews/40-audit.md
# 接手：一律重启监视
( HOME="${FH}" /bin/bash "${A}" watch wait --feature demo --interval 30 --timeout 60 >/dev/null 2>&1 & ); sleep 2
printf '# 41\n\nStatus: done\n' > ${F}/p1/issues/41-x.md
out=$(al watch wait --restart --interval 1 --timeout 5 2>&1); check "接手（Claude）：--restart 停掉上一个等待，自己收到通知" 'echo "${out}" | grep -q "41-x.md 的票头变为 done"'
sleep 1; check "接手（Claude）：上一个等待已经不在" '[ "$(ps -axo command= | grep -c "[a]gent-loop watch wait --feature demo")" -eq 0 ]'
( HOME="${FH}" /bin/bash "${A}" watch run --feature demo --interval 1 >/dev/null 2>&1 & ); sleep 2
out=$(al watch wait --interval 1 --timeout 2 2>&1); check "有常驻监视时普通的等待拒绝启动" 'echo "${out}" | grep -q "wait --restart"'
out=$(al watch wait --restart --interval 1 --timeout 2 2>&1); check "接手（Claude 接 Codex）：--restart 停掉常驻监视" '[ "${out}" = TIMEOUT ] && [ "$(ps -axo command= | grep -c "[a]gent-loop watch run --feature demo")" -eq 0 ]'
( HOME="${FH}" /bin/bash "${A}" watch wait --feature demo --interval 30 --timeout 60 >/dev/null 2>&1 & ); sleep 2
out=$(al watch restart --interval 1 2>&1); sleep 2
check "接手（Codex 接 Claude）：restart 停掉等待并启动常驻监视" '[ "$(ps -axo command= | grep -c "[a]gent-loop watch wait --feature demo")" -eq 0 ] && [ "$(ps -axo command= | grep -c "[a]gent-loop watch run --feature demo")" -eq 1 ]'
n0=$(grep -c . "${NF}"); al watch restart --interval 1 >/dev/null 2>&1; sleep 3; check "重启后不重报已经通知过的事" '[ "$(grep -c . "${NF}")" -eq "${n0}" ] && [ "$(ps -axo command= | grep -c "[a]gent-loop watch run --feature demo")" -eq 1 ]'
al watch stop >/dev/null 2>&1; sleep 1; rm -f ${F}/p1/issues/41-x.md
check "旧的监视脚本已经并入 agent-loop watch" '[ ! -e "$(dirname "${A}")/watch-status.sh" ] && [ ! -e "$(dirname "${A}")/lib/watch-codex.sh" ]'

# 新开的 Codex 总控：后台对上会话 ID 后自己成为监视进程
al window open --step coordinator --model codex-astra-high --dir "${T}/wt" --prompt - >/dev/null 2>&1
CW=$(tail -1 ${F}/ledger/windows.tsv | cut -f1); CS2=aaaaaaaa-0000-0000-0000-000000000002
echo '{"type":"session_meta","payload":{"session_id":"'${CS2}'","cwd":"'${T}/wt'"}}' > "${FH}/.codex/sessions/2026/01/01/rollout-2099-01-01T00-00-01-${CS2}.jsonl"
( HOME="${FH}" AGENT_LOOP_ADOPT_WAIT=1 /bin/bash "${A}" watch adopt "${CW}" --interval 1 >/dev/null 2>&1 & )
i=0; while [ ${i} -lt 10 ] && [ ! -s ${F}/ledger/coordinator ]; do sleep 1; i=$((i+1)); done; sleep 1
check "Codex 总控：自动对上会话并登记" '[ "$(cat ${F}/ledger/coordinator 2>/dev/null)" = "codex|${CS2}" ]'
al watch status >/dev/null 2>&1; check "Codex 总控：监视随之启动" '[ $? -eq 0 ]'
al watch stop >/dev/null 2>&1; al watch status >/dev/null 2>&1; check "监视可以停止" '[ $? -ne 0 ]'

# 送消息（送出命令换成写文件）
printf '#!/bin/bash\necho "$1 $2 $3" >> %s\n' "${T}/send.log" > "${T}/send.sh"; chmod +x "${T}/send.sh"
AGENT_LOOP_SEND_CMD="${T}/send.sh" al send p1-01 "裁决 1 已写入" --expect 1 >/dev/null 2>&1
check "送消息：票号对到最近开的窗口和它的会话" 'grep -qF "codex ${CS} 裁决 1 已写入" "${T}/send.log"'
check "送消息：登记等待接收" 'grep -qF "01-a.md" ${F}/ledger/expect.tsv'
out=$(AGENT_LOOP_SEND_CMD="${T}/send.sh" al send p1-01 "请读取" 2>&1)
check "送消息：没有裁决的送出不说以票头为准；Claude 总控不加提示" '! echo "${out}" | grep -q claimed && ! echo "${out}" | grep -q "结束本轮"'
al set 总控 codex >/dev/null 2>&1; out=$(AGENT_LOOP_SEND_CMD="${T}/send.sh" al send p1-01 "请读取" 2>&1); al set 总控 claude >/dev/null 2>&1
check "送消息：Codex 总控得到结束本轮的提示；给开发窗口送消息不提 --redo" 'echo "${out}" | grep -q "结束本轮" && ! echo "${out}" | grep -qF -- "--redo"'
# 返工：同一个完成标记，改完再通知一次
printf 'x\n\n已完成\n' > ${F}/regression/p9-plan.md; al watch once >/dev/null; rn=$(grep -c "p9-plan.md" "${NF}")
out=$(AGENT_LOOP_SEND_CMD="${T}/send.sh" al send p1-01 "请修订统计行" --redo regression/p9-plan.md 2>&1); al watch once >/dev/null
check "返工：送出后文件没变，不通知" '[ "$(grep -c "p9-plan.md" "${NF}")" -eq "${rn}" ] && tail -1 "${T}/send.log" | grep -q "先删掉 p9-plan.md 末尾的完成标记"'
printf 'y\n' > ${F}/regression/p9-plan.md; al watch once >/dev/null; check "返工：标记删掉、还在改的时候不通知" '[ "$(grep -c "p9-plan.md" "${NF}")" -eq "${rn}" ]'
printf 'y\n\n已完成\n' > ${F}/regression/p9-plan.md; al watch once >/dev/null; al watch once >/dev/null; check "返工：改完写回标记，再通知一次且只一次" '[ "$(grep -c "p9-plan.md" "${NF}")" -eq $((rn + 1)) ]'
rm -f ${F}/regression/p9-plan.md

# ---------- 窗口还在不在、签到、送错窗口、等待不设时限、票的返工、总控用量分行 ----------
setc() { awk -F'\t' -v OFS='\t' -v w="$1" -v c="$2" -v v="$3" '$1==w {$c=v} {print}' ${F}/ledger/windows.tsv > "${T}/w.tmp" && cp "${T}/w.tmp" ${F}/ledger/windows.tsv; }
getc() { awk -F'\t' -v w="$1" -v c="$2" '$1==w {print $c}' ${F}/ledger/windows.tsv; }
sent() { grep -c . "${T}/send.log"; }
SEND="${T}/send.sh"; printf '#!/bin/bash\n[ "$1" = GONE ] && exit 1\nexit 0\n' > "${T}/alive.sh"; chmod +x "${T}/alive.sh"
printf '# 50\n\nStatus: claimed\n' > ${F}/p1/issues/50-x.md; al watch once >/dev/null
printf '提示正文\n' > "${T}/p50.prompt"
out=$(al window open --step dev --ticket p1-50 --dir "${R}" --prompt "${T}/p50.prompt" 2>&1); W50=$(echo "${out}" | sed -n 's/^window: //p')
check "签到：初始提示最前面加了签到命令，原文保留" 'head -1 ${F}/ledger/prompts/${W50}.prompt | grep -qF "agent-loop window hello ${W50} --feature demo" && grep -qF "提示正文" ${F}/ledger/prompts/${W50}.prompt'
check "签到：手动开的窗口不盯" '[ "$(getc ${W50} 14)" = 不适用 ]'
printf '/some-command\n' > "${T}/p51.prompt"
out=$(al window open --step audit --ticket p1-50 --dir "${R}" --prompt "${T}/p51.prompt" 2>&1); W51=$(echo "${out}" | sed -n 's/^window: //p')
check "签到：斜杠命令开头的提示不改" '[ ! -e ${F}/ledger/prompts/${W51}.prompt ]'
# 当成真的开出来了的窗口：有标签页标识、有会话、还没签到、开了很久
for w in ${W50} ${W51}; do setc ${w} 14 -; setc ${w} 3 1; setc ${w} 11 "TAB-${w}"; setc ${w} 10 "sid-${w}"; done
al window hello ${W51} >/dev/null 2>&1; check "签到：记下签到时间" '[ "$(getc ${W51} 14)" != - ]'
al watch once >/dev/null; al watch once >/dev/null
check "签到：到点没签到的窗口通知一次，带提示文件" '[ "$(grep -c "${W50}（dev，票 p1-50）开窗已" "${NF}")" -eq 1 ] && grep "${W50}（dev" "${NF}" | grep -qF "prompts/${W50}.prompt"'
check "签到：签过到的窗口不通知" '! grep -q "${W51}（audit" "${NF}"'
al window hello ${W50} >/dev/null 2>&1
# 一张票开着两个窗口：按票号送不猜
n0=$(sent); out=$(AGENT_LOOP_SEND_CMD="${SEND}" al send p1-50 "补充说明" 2>&1); rc=$?
check "送消息：一张票有两个开着的窗口时按票号送被拒绝，列出窗口" '[ ${rc} -ne 0 ] && [ "$(sent)" -eq "${n0}" ] && echo "${out}" | grep -qF "${W50} dev" && echo "${out}" | grep -qF "${W51} audit"'
out=$(AGENT_LOOP_SEND_CMD="${SEND}" al send ${W50} "补充说明" 2>&1)
check "送消息：改用窗口编号送出；票没完成时不登记返工" '[ "$(sent)" -eq $((n0 + 1)) ] && ! echo "${out}" | grep -q "返工"'
# --redo 的提醒只在用得上时出现
mkdir -p ${F}/p1/reviews; printf 'x\n\n审计完成\n' > ${F}/p1/reviews/50-audit.md; al watch once >/dev/null
out=$(AGENT_LOOP_SEND_CMD="${SEND}" al send ${W51} "补一段" 2>&1); check "送消息：窗口的产物已有完成标记而没登记返工时提醒 --redo" 'echo "${out}" | grep -qF -- "--redo"'
out=$(AGENT_LOOP_SEND_CMD="${SEND}" al send ${W51} "补一段" --redo p1/reviews/50-audit.md 2>&1); check "送消息：登记了返工就不再提醒" '! echo "${out}" | grep -q "注意："'
# 标签页已经不在
setc ${W51} 11 GONE; n0=$(sent)
out=$(AGENT_LOOP_ALIVE_CMD="${T}/alive.sh" AGENT_LOOP_SEND_CMD="${SEND}" al send ${W51} "还在吗" 2>&1); rc=$?
check "送消息：标签页已经关闭时失败，不送出，登记为关闭" '[ ${rc} -ne 0 ] && [ "$(sent)" -eq "${n0}" ] && echo "${out}" | grep -q "标签页已经关闭" && getc ${W51} 13 | grep -q "已消失"'
out=$(AGENT_LOOP_SEND_CMD="${SEND}" al send ${W51} "还在吗" 2>&1); rc=$?
check "送消息：已经登记关窗的窗口不送" '[ ${rc} -ne 0 ] && [ "$(sent)" -eq "${n0}" ] && echo "${out}" | grep -q "已经登记关窗"'
out=$(AGENT_LOOP_SEND_CMD="${SEND}" al send p1-50 "只剩一个窗口" 2>&1); check "送消息：只剩一个开着的窗口时又可以按票号送" '[ "$(sent)" -eq $((n0 + 1)) ]'
al window open --step spec --stage p2 --dir "${R}" --prompt - >/dev/null 2>&1; W52=$(tail -1 ${F}/ledger/windows.tsv | cut -f1); setc ${W52} 11 GONE
out=$(AGENT_LOOP_ALIVE_CMD="${T}/alive.sh" al window list 2>&1)
check "列窗口：标签页不在的窗口标出来并登记为关闭，其余照常" 'echo "${out}" | grep -qF "[已消失] ${W52}" && ! echo "${out}" | grep -q "^  ${W52} " && echo "${out}" | grep -q "^  ${W50} "'
al window open --step spec --stage p2 --dir "${R}" --prompt - >/dev/null 2>&1; W53=$(tail -1 ${F}/ledger/windows.tsv | cut -f1); setc ${W53} 11 GONE
out=$(AGENT_LOOP_ALIVE_CMD="${T}/alive.sh" al check 2>&1); check "环境检查：也标出标签页不在的窗口" 'echo "${out}" | grep -qF "[已消失] ${W53}"'
# 票的返工：票头已经是 done 时送消息自动登记，内容变了再通知一次
printf '# 50\n\nStatus: done\n' > ${F}/p1/issues/50-x.md; al watch once >/dev/null; d0=$(grep -c "50-x.md 的票头变为 done" "${NF}")
out=$(AGENT_LOOP_SEND_CMD="${SEND}" al send ${W50} "请返工" 2>&1); al watch once >/dev/null
check "票的返工：给票头是 done 的开发窗口送消息时自动登记，票没变不通知" 'echo "${out}" | grep -q "已登记返工" && [ "$(grep -c "50-x.md 的票头变为 done" "${NF}")" -eq "${d0}" ]'
printf '# 50\n\nStatus: done\n\n返工记录\n' > ${F}/p1/issues/50-x.md; al watch once >/dev/null; al watch once >/dev/null
check "票的返工：两次检查之间改完（票头一直是 done）也通知一次，且只一次" '[ "$(grep -c "50-x.md 的票头变为 done" "${NF}")" -eq $((d0 + 1)) ] && grep -q "50-x.md 的票头变为 done（返工后）" "${NF}"'
out=$(al watch redo p1-50 2>&1); check "票的返工：watch redo 也认票号" 'echo "${out}" | grep -q "票头又是 done"'
# 等待默认没有时限
( HOME="${FH}" /bin/bash "${A}" watch wait --feature demo --interval 1 >/dev/null 2>&1 & ); sleep 4
check "等待：不给时限时一直等" '[ "$(ps -axo command= | grep -c "[a]gent-loop watch wait --feature demo")" -ge 1 ]'
al watch stop >/dev/null 2>&1
# 用量：总控换过会话时每个会话一行
out=$(al ledger --summary 2>&1)
check "用量：每个总控会话单列一行，另有合计" '[ "$(echo "${out}" | grep -c "^| 其他窗口：coordinator W-")" -ge 2 ] && echo "${out}" | grep -q "^| 其他窗口：coordinator 合计（"'
for w in ${W50} ${W52} ${W53}; do al window close ${w} --record-only >/dev/null 2>&1; done
rm -f ${F}/p1/issues/50-x.md ${F}/p1/reviews/50-audit.md

# 回归统计
mkdir -p ${F}/regression
printf '| 编号 | 级别 | 前提 | 步骤 |\n| --- | --- | --- | --- |\n| P1-001 | 必测 | A | x |\n| P1-002 | 必测 | A | x |\n| P1-003 | 必测 | U2 | x |\n| P1-004 | 选测 | A | x |\n' > ${F}/regression/p1-plan.md
printf '## 第 1 轮\n\n| 编号 | 结论 | 证据 |\n| --- | --- | --- |\n| P1-001 | 失败 | e |\n| P1-002 | 通过 | e |\n| P1-003 | 未测：缺 U2 | - |\n\n## 第 2 轮\n\n| P1-001 | 通过 | e |\n' > ${F}/regression/p1-result.md
out=$(al regress 2>&1)
check "回归：以最后一轮结论为准，没有结论的算未执行" 'echo "${out}" | grep -qF "p1 回归：必测 3 项，通过 2、失败 0、未测 1、不测 0、未执行 0；选测 1 项，通过 0、失败 0、未测 0、不测 0、未执行 1"'
check "回归：列出未测项并生成统计文件" 'echo "${out}" | grep -q "未测： P1-003" && grep -qF "| p1 | 必测 | 3 | 2 | 0 | 1 | 0 | 0 |" ${F}/regression/summary.md'

# 一张票的三个动作：开工、核对、合入
sed -i.bak -e 's|^- 分支前缀.*|- 分支前缀（说明）：`t/`|' -e 's|^- 修复分支名.*|- 修复分支名（说明）：`t/fix`|' -e 's|^- 本机专用文件.*|- 本机专用文件（说明）：`AGENTS.md`、`docs/agents/`|' ${P}; rm -f ${P}.bak
git branch t/p1 main; WR="${T}/repo-worktrees"
printf '# 03 丙\n\nStatus: claimed\nRisk: 低\n' > ${F}/p1/issues/03-c.md
printf '目录 {{WORKTREE}} 分支 {{BRANCH}} 基于 {{BASE}}\n' > "${T}/p.prompt"
out=$(al ticket open p1-03 --prompt "${T}/p.prompt" 2>&1)
check "开工：建好 worktree 和票分支" '[ -d "${WR}/p1-03" ] && [ "$(git -C "${WR}/p1-03" rev-parse --abbrev-ref HEAD)" = t/p1-03 ]'
check "开工：复制本机专用文件，参数文件不留在 worktree 里" '[ -f "${WR}/p1-03/AGENTS.md" ] && [ -f "${WR}/p1-03/docs/agents/issue-tracker.md" ] && [ ! -e "${WR}/p1-03/${P}" ]'
check "开工：票头补上分支和 worktree" 'grep -q "^Branch: t/p1-03" ${F}/p1/issues/03-c.md && grep -q "^Worktree: ${WR}/p1-03" ${F}/p1/issues/03-c.md'
check "开工：登记开发窗口，提示里的占位被替换" '[ "$(tail -1 ${F}/ledger/windows.tsv | cut -f5,6)" = "p1-03	dev" ] && grep -qF "分支 t/p1-03 基于 t/p1" "$(echo "${out}" | sed -n "s/.*\$(cat \([^)]*\)).*/\1/p")"'
al set 窗口上限 3 >/dev/null 2>&1; out=$(al window open --step audit --stage p1 --dir "${R}" --prompt - 2>&1)
check "开窗：列出参数文件自上次开窗以来的变更" 'echo "${out}" | grep -q "有 1 条变更" && echo "${out}" | grep -q "窗口上限"'
out=$(al ticket verify p1-03 2>&1); check "核对：票没做完时不通过" '[ $? -ne 0 ] && echo "${out}" | grep -q "机械核对：不通过"'
( cd "${WR}/p1-03" && echo x > c.txt && git add c.txt && git -c user.name=t -c user.email=t@example.invalid commit -q -m c )
sed -i.bak 's/^Status: claimed/Status: done/' ${F}/p1/issues/03-c.md; rm -f ${F}/p1/issues/*.bak; printf '\n### 完成记录\n测试 3/3 通过\n' >> ${F}/p1/issues/03-c.md
out=$(al ticket verify p1-03 2>&1); check "核对：列出提交、改动的文件和完成回报" '[ $? -eq 0 ] && echo "${out}" | grep -q "多 1 个提交" && echo "${out}" | grep -q "^  c.txt" && echo "${out}" | grep -q "测试 3/3 通过"'
check "核对：写明测试结论以完成回报为准，总控不重跑" 'echo "${out}" | grep -q "你不重跑测试"'
al ticket merge p1-03 >/dev/null 2>&1; check "合入：没有集成 worktree 时拒绝" '[ $? -ne 0 ]'
git worktree add -q "${WR}/p1-integration" t/p1 >/dev/null 2>&1
out=$(al ticket merge p1-03 2>&1)
check "合入：票分支进了阶段分支，是合并提交" 'git merge-base --is-ancestor t/p1-03 t/p1 && [ "$(git rev-list --count --merges t/p1 ^main)" -eq 1 ]'
check "合入：清理这张票的 worktree，分支保留" '[ ! -d "${WR}/p1-03" ] && git rev-parse -q --verify t/p1-03 >/dev/null && echo "${out}" | grep -q "已清理 worktree"'
check "合入：登记完成时间和关窗" 'grep -q "done	p1-03" ${F}/ledger/events.tsv && [ "$(awk -F"\t" "\$5==\"p1-03\" {print \$13}" ${F}/ledger/windows.tsv)" != - ]'
out=$(al ticket merge p1-03 2>&1); check "合入：已经合入的票不重复合入" '[ $? -ne 0 ]'
printf '# 04 丁\n\nStatus: done\nRisk: 低\n' > ${F}/p1/issues/04-d.md
al ticket open p1-04 --prompt - >/dev/null 2>&1; ( cd "${WR}/p1-04" && echo y > c.txt && git add c.txt && git -c user.name=t -c user.email=t@example.invalid commit -q -m d )
( cd "${WR}/p1-integration" && echo z > c.txt && git add c.txt && git -c user.name=t -c user.email=t@example.invalid commit -q -m z )
h=$(git rev-parse t/p1); out=$(al ticket merge p1-04 2>&1)
check "合入：有冲突时撤销合入，阶段分支保持原样" '[ $? -eq 2 ] && echo "${out}" | grep -q "c.txt" && [ "$(git rev-parse t/p1)" = "${h}" ] && [ -z "$(git -C "${WR}/p1-integration" status --porcelain)" ]'
printf '# 05 戊\n\nStatus: claimed\nRisk: 低\n' > ${F}/p1/issues/05-e.md; git branch t/fix main
al ticket open p1-05 --fix --prompt - >/dev/null 2>&1; check "开工：修复分支上的票从修复分支开出" '[ "$(git -C "${WR}/fix-05" rev-parse --abbrev-ref HEAD)" = t/fix-05 ]'

# 清理积压的 worktree
git worktree add -q "${WR}/old" -b t/old main >/dev/null 2>&1; ( cd "${WR}/old" && echo o > o.txt && git add o.txt && git -c user.name=t -c user.email=t@example.invalid commit -q -m o )
git -c user.name=t -c user.email=t@example.invalid merge -q --no-ff -m "merge old" t/old >/dev/null 2>&1
git worktree add -q "${WR}/dirty" -b t/dirty main >/dev/null 2>&1; echo u > "${WR}/dirty/untracked.txt"
out=$(al worktree prune 2>&1); check "清理：不加 --yes 时只列出，不删除" '[ -d "${WR}/old" ] && echo "${out}" | grep -q "${WR}/old"'
out=$(al worktree prune --yes 2>&1)
check "清理：删掉已合入且干净的，分支保留" '[ ! -d "${WR}/old" ] && git rev-parse -q --verify t/old >/dev/null'
check "清理：有未提交修改的、没合入的、有窗口开着的、集成用的都保留" '[ -d "${WR}/dirty" ] && [ -d "${WR}/p1-04" ] && [ -d "${WR}/fix-05" ] && [ -d "${WR}/p1-integration" ] && [ -d "${T}/wt" ]'
al set 自动清理worktree 关闭 >/dev/null 2>&1; check "自动清理可以关闭" '[ "$(val worktree.auto-clean)" = 关闭 ]'

# 用户维护的文档应当只留本机
echo goal > GOAL.md; echo note > NOTE.md; git add GOAL.md; git -c user.name=t -c user.email=t@example.invalid commit -q -m goal
sed -i.bak 's|^- 用户维护的文档.*|- 用户维护的文档（说明）：`GOAL.md`、`NOTE.md`|' ${P}; rm -f ${P}.bak
out=$(al check 2>&1); check "检查：用户维护的文档在 Git 里时提醒，不在的不提醒" 'echo "${out}" | grep -q "用户维护的文档 GOAL.md 在 Git 里" && ! echo "${out}" | grep -q "NOTE.md"'

# Codex 总控
al set 总控 codex >/dev/null 2>&1
out=$(al start demo --print 2>&1); check "Codex 总控：已登记会话时恢复它" 'echo "${out}" | grep -qF "codex resume ${CS2} -c check_for_update_on_startup=false -m gpt-6.2-astra"'
out=$(al start demo --new --print 2>&1); check "Codex 总控：--new 不恢复登记的会话" 'echo "${out}" | grep -qF "codex -c check_for_update_on_startup=false -m gpt-6.2-astra" && ! echo "${out}" | grep -q "codex resume"'
rm -f ${F}/ledger/coordinator
out=$(al start demo --print 2>&1); check "Codex 总控：没有登记时新开，提示里指向 Codex 入口" 'echo "${out}" | grep -qF "codex -c check_for_update_on_startup=false -m gpt-6.2-astra" && grep -qF "codex/SKILL.md" "$(echo "${out}" | sed -n "s/.*\$(cat \([^)]*\)).*/\1/p")"'
out=$(al open 错误对接 --print 2>&1); check "Codex 总控：可选窗口的模型跟着总控走" 'echo "${out}" | grep -qF "codex -c check_for_update_on_startup=false -m gpt-6.2-astra"'
al set 总控 claude >/dev/null 2>&1

echo "通过 ${pass}，失败 ${fail}"
[ "${fail}" -eq 0 ]
