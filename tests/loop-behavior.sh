#!/bin/bash
# agent-loop 协议关键路径的行为测试：用假 worker 和临时 git 仓库，不调用任何模型、不碰真实项目。
# 用法：tests/loop-behavior.sh            全部场景
# 退出码：0 全部通过；1 有失败。宿主真实唤醒、各 CLI 的消息送达不在这里测，接入时按 bootstrap 第 3 步实测。
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
S=$HERE/scripts
L=$S/loopctl
W=$(mktemp -d "${TMPDIR:-/tmp}/agent-loop-test.XXXXXX")
export TMPDIR=$W/
# 临时仓库使用固定的测试身份，也独立于本机的签名和提交通知等 Git 设置。
export GIT_AUTHOR_NAME="Agent Loop Test" GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
edit_in(){ local f=$1; shift; sed "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }   # 可移植的就地替换（不依赖 macOS 的 sed -i ''）
ticket(){ # ticket <路径> <ID> <Run> [其他头字段行...]
  local f=$1 id=$2 run=$3; shift 3
  { echo "# $id"; echo "Status: ready-for-agent"; echo "Run: $run"; for l in "$@"; do echo "$l"; done; echo; echo "## Comments"; } > "$f"
}
state(){ "$S/loop-state.sh" "$1" | awk -F'\t' -v id="$2" -v col="$3" 'NR==1{for(i=1;i<=NF;i++)h[$i]=i; next} $1==id{print $h[col]}'; }

echo "== 1. 正常接票：认领 → 完成 → 验收 → 集成 → 依赖解除"
D=$W/s1; mkdir -p $D/t $D/run; git init -q $D/repo; git -C $D/repo commit -q --allow-empty -m base; git -C $D/repo branch -q stage
ticket $D/t/01-a.md 01-a idle "Deliverable: commit"
ticket $D/t/02-b.md 02-b idle "Depends: 01-a"
G=$($L -r $D/run -o C acquire)
check "01 可派工、02 被依赖阻塞" '[ "$(state $D/t 01-a dispatchable)" = yes ] && [ "$(state $D/t 02-b reason)" = "dep:01-a=idle" ]'
$L -r $D/run -o C -g $G claim $D/t/01-a.md 01-a-r1 >/dev/null
git -C $D/repo checkout -q -b t01 stage; git -C $D/repo commit -q --allow-empty -m work; SHA=$(git -C $D/repo rev-parse HEAD)
edit_in $D/t/01-a.md 's/^Run: dispatched/Run: done/'
E=$("$S/watch.sh" -i 1 -t 5 -s $D/run/seen $D/t/01-a.md)
check "监视报告 done" '[ "$(echo "$E" | cut -f1)" = done ]'
check "verify-commit：回报 SHA 等于 HEAD" '$L verify-commit $D/repo t01 $SHA >/dev/null'
$L -r $D/run -o C -g $G intent 01-a-r1.merge merge "t01->stage" >/dev/null
git -C $D/repo checkout -q stage; git -C $D/repo merge -q --no-ff t01 -m "merge t01"; M=$(git -C $D/repo rev-parse HEAD)
$L -r $D/run -o C -g $G result 01-a-r1.merge $M >/dev/null
$L -r $D/run -o C -g $G set $D/t/01-a.md Accepted $M >/dev/null; $L -r $D/run -o C -g $G transition $D/t/01-a.md done accepted >/dev/null
check "依赖验收后 02 可派工" '[ "$(state $D/t 02-b dispatchable)" = yes ]'

echo "== 2. 重复事件：同一待裁决只报一次，新裁决仍会报"
D=$W/s2; mkdir -p $D/t $D/run
ticket $D/t/07.md 07 needs-decision "Run-id: 07-r1"; echo "### 待裁决 1（07-r1）" >> $D/t/07.md
K=$("$S/watch.sh" -i 1 -t 3 -s $D/run/seen $D/t/07.md | cut -f3); "$S/watch.sh" -s $D/run/seen --ack "$K"
n=0; for i in 1 2 3; do "$S/watch.sh" -i 1 -t 1 -s $D/run/seen $D/t/07.md | grep -q needs-decision && n=$((n+1)); done
check "登记后重挂三次都不再报" '[ $n -eq 0 ]'
echo "### 待裁决 2（07-r1）" >> $D/t/07.md
check "新的待裁决会报" '"$S/watch.sh" -i 1 -t 3 -s $D/run/seen $D/t/07.md | grep -q "needs-decision|2"'

echo "== 3. 双总控：租约内第二个总控取不到；接管后旧总控不能写"
D=$W/s3; mkdir -p $D/t; ticket $D/t/01.md 01 idle
GA=$($L -r $D/run -o A acquire)
$L -r $D/run -o B acquire >/dev/null 2>&1; rc=$?
check "租约内 B 取所有权失败（退出码 3）" '[ $rc -eq 3 ]'
GB=$(LOOP_LEASE=0 $L -r $D/run -o B acquire)
$L -r $D/run -o A -g $GA claim $D/t/01.md 01-r1 >/dev/null 2>&1; rc=$?
check "被接管的 A 认领失败（退出码 3）" '[ $rc -eq 3 ] && [ "$(state $D/t 01 run)" = idle ]'
check "新总控 B 可以认领" '$L -r $D/run -o B -g $GB claim $D/t/01.md 01-r1 >/dev/null'
$L -r $D/run -o B -g $GB claim $D/t/01.md 01-r2 >/dev/null 2>&1; rc=$?
check "同一张票不能被认领两次（退出码 5）" '[ $rc -eq 5 ]'

echo "== 4. 等用户答复时，独立票继续、依赖票暂停"
D=$W/s4; mkdir -p $D/t
ticket $D/t/01.md 01 needs-decision; ticket $D/t/02.md 02 idle; ticket $D/t/03.md 03 idle "Depends: 01"
check "02 可派工" '[ "$(state $D/t 02 dispatchable)" = yes ]'
check "03 因 01 未验收被阻塞" '[ "$(state $D/t 03 reason)" = "dep:01=needs-decision" ]'

echo "== 5. 崩溃恢复：已启动未记回执不重复启动；已合入未记验收不重复合入"
D=$W/s5; mkdir -p $D/t $D/wt $D/run; echo go > $D/p.md
printf '#!/bin/bash\nsleep 4\n' > $D/slow.sh; chmod +x $D/slow.sh
G=$($L -r $D/run -o C acquire)
$L -r $D/run -o C -g $G intent 05-r1.launch launch worker >/dev/null
"$S/launch.sh" --dir $D/wt --prompt $D/p.md --pid $D/run/05-r1/worker.pid --mode background -- $D/slow.sh >/dev/null
check "恢复时能列出未记结果的启动意图" '$L -r $D/run pending | grep -q 05-r1.launch'
"$S/launch.sh" --dir $D/wt --prompt $D/p.md --pid $D/run/05-r1/worker.pid --mode background -- $D/slow.sh >/dev/null 2>&1; rc=$?
check "worker 仍在运行时拒绝重复启动（退出码 6）" '[ $rc -eq 6 ]'
git init -q $D/repo; git -C $D/repo commit -q --allow-empty -m base; git -C $D/repo branch -q stage
git -C $D/repo checkout -q -b t05; git -C $D/repo commit -q --allow-empty -m w; git -C $D/repo checkout -q stage
$L -r $D/run -o C -g $G intent 05-r1.merge merge "t05->stage" >/dev/null
git -C $D/repo merge -q --no-ff t05 -m "merge t05"   # 合入后「崩溃」，没有记结果
MS=$($L merged-check $D/repo stage t05)
check "merged-check 找到已有的合入提交，不需要再合" '[ "$MS" = "$(git -C $D/repo rev-parse stage)" ]'
check "反方向（stage 不在 t05 中）merged-check 返回 1" '! $L merged-check $D/repo t05 stage >/dev/null 2>&1'

echo "== 6. 无提交交付：产物完成标记绑定 Run-id"
D=$W/s6; mkdir -p $D/run
printf '# 基准\n正文提到 LOOP-DONE 06-r2 和 审计完成\n\nLOOP-DONE 06-r1\n' > $D/base.md
check "上一次运行的标记、正文字样都不算完成" '[ "$("$S/watch.sh" -i 1 -t 1 -s $D/run/seen "$D/base.md::06-r2")" = TIMEOUT ]'
printf '\nLOOP-DONE 06-r2\n' >> $D/base.md
check "本次运行的末行标记算完成" '"$S/watch.sh" -i 1 -t 2 -s $D/run/seen "$D/base.md::06-r2" | grep -q artifact-done'

echo "== 7. 过期证据：测了 A 又提交 B，用 A 验收被拒"
D=$W/s7; git init -q $D/repo; git -C $D/repo commit -q --allow-empty -m a; A=$(git -C $D/repo rev-parse HEAD)
git -C $D/repo commit -q --allow-empty -m b; BR=$(git -C $D/repo rev-parse --abbrev-ref HEAD)
check "回报 A、HEAD 为 B 时 verify-commit 失败" '! $L verify-commit $D/repo $BR $A >/dev/null'

echo "== 8. 提示传入方式：arg / stdin / file"
D=$W/s8; mkdir -p $D/wt; printf '含"引号"和$变量\n' > $D/p.md
printf '#!/bin/bash\nif [ "${1:-}" = "--from" ]; then echo "file:$(cat "$2")"; elif [ -n "${1:-}" ]; then echo "arg:$1"; else echo "stdin:$(cat)"; fi\n' > $D/cli.sh; chmod +x $D/cli.sh
"$S/launch.sh" --dir $D/wt --prompt $D/p.md --pid $D/run/a/worker.pid --mode background --prompt-mode arg -- $D/cli.sh >/dev/null
"$S/launch.sh" --dir $D/wt --prompt $D/p.md --pid $D/run/s/worker.pid --mode background --prompt-mode stdin -- $D/cli.sh >/dev/null
"$S/launch.sh" --dir $D/wt --prompt $D/p.md --pid $D/run/f/worker.pid --mode background --prompt-mode file -- $D/cli.sh --from '{prompt_file}' >/dev/null
sleep 1
check "arg 方式原样收到提示" 'grep -qF "arg:含\"引号\"和\$变量" $D/run/a/worker.log'
check "stdin 方式原样收到提示" 'grep -qF "stdin:含\"引号\"和\$变量" $D/run/s/worker.log'
check "file 方式只收到一个提示来源" 'grep -qF "file:含\"引号\"和\$变量" $D/run/f/worker.log'
"$S/launch.sh" --dir $D/wt --prompt $D/p.md --pid $D/run/x/worker.pid --mode background --prompt-mode file -- $D/cli.sh >/dev/null 2>&1; rc=$?
check "file 方式缺少占位符时拒绝启动" '[ $rc -ne 0 ]'
check "pid 和日志不在 worktree 里" '[ -z "$(ls -A $D/wt)" ]'

echo "== 9. 旧票映射与依赖解析"
D=$W/s9; mkdir -p $D/t
printf '# 01\nStatus: merged\n' > $D/t/01-old.md
printf '# 02\nStatus: ready-for-agent\nBlocked by: 01\nExternal-X1: pending blocks=dispatch 执行 a.sql\n' > $D/t/02-x.md
printf '# 03\nStatus: needs-info\nDepends: zz\n' > $D/t/03-y.md
check "旧票 Status: merged 映射为 accepted" '[ "$(state $D/t 01-old run)" = accepted ]'
check "外部前置阻塞派工" '[ "$(state $D/t 02-x reason)" = "external:X1" ]'
check "分诊状态和未知依赖都写进原因" '[ "$(state $D/t 03-y reason)" = "triage:needs-info;unknown-dep:zz" ]'

echo "== 10. 接入：已跟踪入口不改、指针幂等、本机排除、worktree 同步"
D=$W/s10; git init -q $D/repo; printf '# Team\nkeep\n' > $D/repo/AGENTS.md; git -C $D/repo add AGENTS.md; git -C $D/repo commit -qm i
git -C $D/repo worktree add -q $D/wt -b w; echo "读 docs/agents/loop-profile.md" > $D/ptr.md; mkdir -p $D/repo/docs/agents; echo p > $D/repo/docs/agents/loop-profile.md
"$S/bootstrap.sh" inject $D/repo/AGENTS.md $D/ptr.md >/dev/null 2>&1; rc=$?
check "默认本机接入时，已跟踪的 AGENTS.md 不改（退出码 7）" '[ $rc -eq 7 ] && [ -z "$(git -C $D/repo status --porcelain AGENTS.md)" ]'
"$S/bootstrap.sh" inject $D/repo/CLAUDE.local.md $D/ptr.md >/dev/null; "$S/bootstrap.sh" inject $D/repo/CLAUDE.local.md $D/ptr.md >/dev/null
check "重复接入两次，指针块只有一份" '[ "$(grep -c "agent-loop:begin" $D/repo/CLAUDE.local.md)" -eq 1 ]'
"$S/bootstrap.sh" exclude $D/repo CLAUDE.local.md docs/agents >/dev/null; "$S/bootstrap.sh" exclude $D/repo CLAUDE.local.md docs/agents >/dev/null
check "本机专用文件不出现在 git status 里，排除项不重复" '[ -z "$(git -C $D/repo status --porcelain)" ] && [ "$(grep -c "^/docs/agents/" $D/repo/.git/info/exclude)" -eq 1 ]'
"$S/bootstrap.sh" sync $D/repo CLAUDE.local.md docs/agents >/dev/null
check "新 worktree 拿到本机专用规范" '[ -f $D/wt/docs/agents/loop-profile.md ] && grep -q agent-loop:begin $D/wt/CLAUDE.local.md'

echo "== 11. 审计部分获批与发布关口"
D=$W/s11; mkdir -p $D/t
ticket $D/t/20-audit.md 20-audit accepted "Deliverable: artifact" "External-A1: met blocks=release 已修复（21）" "External-A4: pending blocks=release 等用户决定"
ticket $D/t/21-fix-a1.md 21-fix-a1 idle "Depends: 20-audit"
ticket $D/t/05-feat.md 05-feat accepted "External-R1: pending blocks=release 等待发布审批"
ticket $D/t/30-release.md 30-release idle "Kind: release" "Depends: 21-fix-a1"
check "已获批的 A1 修复票可以派工（A4 待定不影响）" '[ "$(state $D/t 21-fix-a1 dispatchable)" = yes ]'
check "开发票已验收，R1 只阻塞发布" '[ "$(state $D/t 05-feat run)" = accepted ]'
R=$(state $D/t 30-release reason)
check "发布票列出缺的依赖和每个未决关口" 'echo "$R" | grep -q "dep:21-fix-a1=idle" && echo "$R" | grep -q "release-gate:A4@20-audit" && echo "$R" | grep -q "release-gate:R1@05-feat" && ! echo "$R" | grep -q "A1@"'
edit_in $D/t/21-fix-a1.md 's/^Run: idle/Run: accepted/'; edit_in $D/t/20-audit.md 's/External-A4: pending/External-A4: met/'; edit_in $D/t/05-feat.md 's/External-R1: pending/External-R1: met/'
check "全部处置后发布票可以派工" '[ "$(state $D/t 30-release dispatchable)" = yes ]'

echo "== 12. 在途 worktree：只有用到新提交的票才快进"
D=$W/s12; git init -q $D/repo; git -C $D/repo commit -q --allow-empty -m base; git -C $D/repo branch -q stage
git -C $D/repo worktree add -q $D/wtB -b tB stage; git -C $D/repo worktree add -q $D/wtC -b tC stage
OLD=$(git -C $D/wtB rev-parse HEAD)
git -C $D/repo checkout -q -b tA stage; echo a > $D/repo/a.txt; git -C $D/repo add a.txt; git -C $D/repo commit -qm A; git -C $D/repo checkout -q stage; git -C $D/repo merge -q --no-ff tA -m "merge A"
git -C $D/wtB merge -q --ff-only stage
check "依赖 A 的 B（干净、无本票提交）快进到新基点" '[ "$(git -C $D/wtB rev-parse HEAD)" = "$(git -C $D/repo rev-parse stage)" ] && [ "$OLD" != "$(git -C $D/wtB rev-parse HEAD)" ]'
check "不相关的 C 维持原基点" '[ "$(git -C $D/wtC rev-parse HEAD)" = "$OLD" ]'

echo "== 13. 带注释的自由文本依赖"
D=$W/s13; mkdir -p $D/t
ticket $D/t/02-base.md 02-base accepted; ticket $D/t/03-input.md 03-input accepted; ticket $D/t/04-output.md 04-output accepted
ticket $D/t/05-a.md 05-a idle "Blocked by: 03（解析输入）、04（渲染输出）"
ticket $D/t/06-b.md 06-b idle "Blocked by: 无（可立即开始；字段名\`x\`已定）"
ticket $D/t/07-c.md 07-c idle "Blocked by: 02–04 已全部合入"
ticket $D/t/08-d.md 08-d idle "Blocked by: 03（x）、UNLISTED 待确认"
check "括号注释被忽略，03、04 都已验收则可派工" '[ "$(state $D/t 05-a dispatchable)" = yes ]'
check "以「无」开头视为没有依赖" '[ "$(state $D/t 06-b dispatchable)" = yes ]'
check "02–04 范围展开，说明文字被跳过" '[ "$(state $D/t 07-c dispatchable)" = yes ]'
check "对不上任何票的 ASCII 词照样报 unknown-dep" '[ "$(state $D/t 08-d reason)" = "unknown-dep:UNLISTED" ]'

echo "== 14. 状态写错位置：Run 未到终态，Status 却是 done"
D=$W/s14; mkdir -p $D/t $D/run
printf '# 09\nStatus: done\nRun: claimed\nRun-id: 09-r1\n' > $D/t/09.md
check "报告 status-mismatch" '"$S/watch.sh" -i 1 -t 3 -s $D/run/seen $D/t/09.md | grep -q "status-mismatch.*09-r1|status-mismatch|done"'

echo "== 15. 新项目：非 git 目录、空仓库"
D=$W/s15; mkdir -p $D/plain
"$S/bootstrap.sh" init-repo $D/plain >/dev/null
check "非 git 目录 init-repo 后有初始提交" 'git -C $D/plain rev-parse -q --verify HEAD >/dev/null'
git init -q $D/empty
check "空仓库 discover 不报错，并提示没有提交" '"$S/bootstrap.sh" discover $D/empty 2>&1 | grep -q "还没有任何提交" && ! "$S/bootstrap.sh" discover $D/empty 2>&1 | grep -q fatal'
git -C "$D/empty" remote add sample-origin "$D/private-remote-location"
OUT=$("$S/bootstrap.sh" discover "$D/empty")
check "discover 显示远端名称，省略远端地址" 'echo "$OUT" | grep -qF "sample-origin" && ! echo "$OUT" | grep -qF "private-remote-location"'
"$S/bootstrap.sh" init-repo $D/empty >/dev/null
check "空仓库 init-repo 后能建 worktree" 'git -C $D/empty worktree add -q $D/wt -b t1 && [ -d $D/wt ]'
H1=$(git -C $D/empty rev-parse HEAD); "$S/bootstrap.sh" init-repo $D/empty >/dev/null
check "已有提交时 init-repo 不做改动" '[ "$(git -C $D/empty rev-parse HEAD)" = "$H1" ]'

echo "== 16. 本机初始化：生成一次，不覆盖"
D=$W/s16; export AGENT_LOOP_HOME=$D/home
"$S/bootstrap.sh" machine >/dev/null
check "生成 machine.md 和运行目录根" '[ -f $D/home/machine.md ] && [ -d $D/home/runs ] && grep -q "引擎适配表" $D/home/machine.md'
echo "# 用户填写的内容" >> $D/home/machine.md; "$S/bootstrap.sh" machine >/dev/null
check "再次运行不覆盖已有配置" 'grep -q "用户填写的内容" $D/home/machine.md'
unset AGENT_LOOP_HOME

echo "== 17. 协作流程冲突识别与启动占位符"
D=$W/s17; git init -q $D/repo; mkdir -p $D/repo/docs
printf '# 入口\n读 docs/flow.md 和 docs/db.md\n' > $D/repo/AGENTS.md
printf '总控开窗后，窗口回报总控，SendMessage，Status: done，自动接续，派工，认领，worktree\n' > $D/repo/docs/flow.md
printf '数据库脚本由用户执行\n' > $D/repo/docs/db.md
OUT=$("$S/bootstrap.sh" conflicts $D/repo)
check "协作流程文档被标为候选，业务规范不被误标" 'echo "$OUT" | grep -q "docs/flow.md.*协作流程候选" && echo "$OUT" | grep -q "docs/db.md.*业务规范"'
mkdir -p $D/wt; echo p > $D/p.md
"$S/launch.sh" --dir $D/wt --prompt $D/p.md --pid $D/run/x/worker.pid --mode background -- echo -m '{model}' >/dev/null 2>&1; rc=$?
check "启动命令里有未替换的 {model} 时拒绝启动" '[ $rc -ne 0 ]'

echo "== 18. Codex 用户安装：单一来源、可重复执行、保留已有入口"
D=$W/s18
checkout="$D/skill checkout"
test_home="$D/new user"
mkdir -p "$checkout" "$test_home"
cp "$HERE/SKILL.md" "$checkout/"
cp -R "$HERE/scripts" "$HERE/references" "$HERE/templates" "$checkout/"
install_for() { env HOME="$1" "$checkout/scripts/bootstrap.sh" install codex; }
installed="$test_home/.agents/skills/agent-loop"
check "从含空格的路径安装两次，Codex 使用同一份 skill 和脚本" \
  'install_for "$test_home" >/dev/null && install_for "$test_home" >/dev/null &&
   [ "$installed/SKILL.md" -ef "$checkout/SKILL.md" ] &&
   [ "$installed/scripts/bootstrap.sh" -ef "$checkout/scripts/bootstrap.sh" ]'
other_home="$D/existing"
existing="$other_home/.agents/skills/agent-loop"
mkdir -p "$existing"; echo keep > "$existing/user-file"
check "保留其他同名 skill 目录并报告冲突" \
  '! install_for "$other_home" >/dev/null 2>&1 && [ -d "$existing" ] &&
   [ "$(cat "$existing/user-file")" = keep ] && [ "$(ls -A "$existing")" = user-file ]'
link_home="$D/dangling"
dangling="$link_home/.agents/skills/agent-loop"
mkdir -p "$(dirname "$dangling")"; ln -s missing-checkout "$dangling"
check "保留悬空链接并报告冲突" \
  '! install_for "$link_home" >/dev/null 2>&1 && [ "$(readlink "$dangling")" = missing-checkout ]'
mkdir -p "$D/bin"
printf '#!/bin/sh\n[ "$1" = --version ] && echo "fixture-cli 1.0"\n' > "$D/bin/codex"
chmod +x "$D/bin/codex"
check "本机初始化记录可用 CLI 的实际版本" \
  'env HOME="$test_home" PATH="$D/bin:$PATH" AGENT_LOOP_HOME="$D/machine" "$S/bootstrap.sh" machine >/dev/null &&
   grep -qF "codex：fixture-cli 1.0" "$D/machine/machine.md"'
git init -q "$D/tracker"
"$S/bootstrap.sh" tracker "$D/tracker" >/dev/null; rc=$?
check "无跟踪说明和票目录时给出未配置状态" '[ "$rc" -eq 2 ]'
mkdir -p "$D/tracker/tickets"
check "按通用票目录发现任务来源" '"$S/bootstrap.sh" tracker "$D/tracker" | grep -qF "tickets/"'
printf '## Task tracking\nRead the project tracker.\n' > "$D/tracker/AGENTS.md"
check "优先识别项目入口中的跟踪说明" '"$S/bootstrap.sh" tracker "$D/tracker" | grep -qF "AGENTS.md"'

echo "== 19. Codex 项目入口：保留团队规范和各 worktree 的本机内容"
D=$W/s19
repo="$D/team repo"
wt="$D/linked worktree"
mkdir -p "$D"
ptr="$D/pointer.md"
echo "read docs/agents/loop-profile.md" > "$ptr"
entry_for() { env HOME="$test_home" "$S/bootstrap.sh" codex-entry "$1" "$ptr"; }
git init -q "$D/empty"
check "空项目的本机规范可通过 AGENTS.md 读取，git status 保持干净" \
  'entry_for "$D/empty" >/dev/null && grep -qxF "read docs/agents/loop-profile.md" "$D/empty/AGENTS.md" &&
   [ -z "$(git -C "$D/empty" status --porcelain)" ]'
git init -q "$D/blank"
echo "existing base" > "$D/blank/AGENTS.md"
printf '  \n' > "$D/blank/AGENTS.override.md"
check "空白 override 仍是 Codex 读取的入口，注入后保留对原规范的指针" \
  'entry_for "$D/blank" >/dev/null &&
   grep -qxF "read docs/agents/loop-profile.md" "$D/blank/AGENTS.override.md" &&
   grep -qF "AGENTS.md" "$D/blank/AGENTS.override.md" &&
   [ "$(cat "$D/blank/AGENTS.md")" = "existing base" ]'
git init -q "$repo"
echo "team instructions" > "$repo/AGENTS.md"
git -C "$repo" add AGENTS.md; git -C "$repo" commit -qm "team rules"
git -C "$repo" worktree add -q "$wt" -b feature
override=AGENTS.override.md
echo "worktree-specific instructions" > "$wt/$override"
check "已跟踪的 AGENTS.md 原样保留，新 override 同时指向团队规范与项目指针" \
  'entry_for "$repo" >/dev/null && entry_for "$repo" >/dev/null &&
   grep -qF "AGENTS.md" "$repo/$override" &&
   grep -qxF "read docs/agents/loop-profile.md" "$repo/$override" &&
   [ -z "$(git -C "$repo" status --porcelain)" ]'
entry_for "$wt" >/dev/null
echo "read updated-project-profile.md" > "$ptr"
check "重复接入 linked worktree 会更新指针一次，保留原有 override 的规则与优先级" \
  'entry_for "$wt" >/dev/null && entry_for "$wt" >/dev/null &&
   grep -qxF "worktree-specific instructions" "$wt/$override" &&
   ! grep -qF "AGENTS.md" "$wt/$override" &&
   ! grep -qF "read docs/agents/loop-profile.md" "$wt/$override" &&
   [ "$(grep -cxF "read updated-project-profile.md" "$wt/$override")" = 1 ] &&
   [ -z "$(git -C "$wt" status --porcelain)" ]'
check "两个 worktree 的本机指针互不覆盖" \
  'grep -qxF "read docs/agents/loop-profile.md" "$repo/$override" &&
   ! grep -qF "updated-project-profile.md" "$repo/$override" &&
   ! grep -qF "worktree-specific instructions" "$repo/$override"'
git -C "$wt" add -f "$override"; git -C "$wt" commit -qm "track feature override"
echo "another update" > "$ptr"
check "本机接入拒绝写已跟踪的 override，团队文件保持干净" \
  '! entry_for "$wt" >/dev/null 2>&1 && [ -z "$(git -C "$wt" status --porcelain)" ]'

echo
echo "通过 ${PASS}，失败 ${FAIL}（临时目录：${W}）"
[ $FAIL -eq 0 ] && rm -rf "$W"
[ $FAIL -eq 0 ]
