#!/bin/bash
# agent-loop 安装与三层初始化的辅助命令。
# 用法：
#   bootstrap.sh install codex                       把当前 checkout 链接到 Codex 的用户级 skills 目录
#   bootstrap.sh machine                             本机初始化：检查依赖与引擎，生成 $AGENT_LOOP_HOME/machine.md（默认 ~/.agent-loop）；已存在时只报告差异，不覆盖
#   bootstrap.sh init-repo <目录>                     新项目：不是 git 仓库时 git init；没有任何提交时做一次空的初始提交（需用户同意后执行）
#   bootstrap.sh tracker <仓库>                       查找项目的任务跟踪说明或票目录
#   bootstrap.sh conflicts <仓库>                     列出常驻入口及其指向的文档中，疑似定义了其他协作流程的文件（只读）
#   bootstrap.sh discover <仓库>                     只读发现：规范入口、任务目录、构建与测试线索、CI、远端、可用引擎、宿主
#   bootstrap.sh codex-entry [--team] <工作树> <内容文件>   把规范指针写进该工作树生效的 Codex 根入口
#   bootstrap.sh inject [--team] <文件> <内容文件>   在文件中写入（或更新）一段 agent-loop 指针块，重复执行只保留一份。
#                                                    文件已被 git 跟踪时默认拒绝（退出码 7）；--team 表示用户同意团队接入
#   bootstrap.sh exclude <仓库> <路径>...            把本机专用路径加进 .git/info/exclude（所有 worktree 共用），已跟踪的路径跳过并提示
#   bootstrap.sh sync <仓库> <路径>...               把主工作树中的本机专用文件或目录复制到每个 worktree
set -uo pipefail

BEGIN='<!-- agent-loop:begin -->'
END='<!-- agent-loop:end -->'
cmd=${1:-}; shift || true

tracked() { git -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1; }
SKILL_DIR=$(cd -P "$(dirname "$0")/.." && pwd -P) || exit 1
AL_HOME=${AGENT_LOOP_HOME:-$HOME/.agent-loop}
ENGINES="claude codex gemini aider opencode cursor-agent"
ENTRIES="AGENTS.override.md AGENTS.md CLAUDE.md CLAUDE.local.md GEMINI.md .cursorrules .github/copilot-instructions.md"
fail() { echo "$*" >&2; exit 1; }

case $cmd in
  install)
    [ "$#" -eq 1 ] && [ "$1" = codex ] || fail "用法：bootstrap.sh install codex"
    dest="$HOME/.agents/skills/agent-loop"
    mkdir -p "$(dirname "$dest")" || exit 1
    # 用 symlink(2) 操作确切的目标；目标已是目录时也不会向其中写入。
    if [ ! "$dest" -ef "$SKILL_DIR" ]; then
      if ! perl -MErrno=EEXIST -e 'symlink($ARGV[0], $ARGV[1]) or $! == EEXIST or die "$ARGV[1]: $!\n"' "$SKILL_DIR" "$dest"; then exit 1; fi
      [ "$dest" -ef "$SKILL_DIR" ] || fail "Codex skill 位置已有其他文件、目录或链接，请核对：$dest"
    fi
    echo "Codex skill 已就位：$dest → $SKILL_DIR"
    ;;
  discover)
    repo=$(git -C "${1:?仓库}" rev-parse --show-toplevel 2>/dev/null) || { echo "不是 git 仓库：$1" >&2; exit 1; }
    echo "## 仓库"; echo "根目录：$repo"
    echo "远端名称：$(git -C "$repo" remote | paste -sd, -)"
    if git -C "$repo" rev-parse -q --verify HEAD >/dev/null; then echo "当前分支：$(git -C "$repo" rev-parse --abbrev-ref HEAD)"; else echo "当前分支：<还没有任何提交，worktree 无法建立；先运行 init-repo>"; fi
    echo "worktree：$(git -C "$repo" worktree list | wc -l | tr -d ' ') 个"
    echo; echo "## 规范入口（tracked=随 git 共享，local=未跟踪，ignored=被忽略）"
    for f in $ENTRIES; do
      [ -e "$repo/$f" ] || continue
      if tracked "$repo" "$f"; then s=tracked; elif git -C "$repo" check-ignore -q "$f"; then s=ignored; else s=local; fi
      grep -qF "$BEGIN" "$repo/$f" && m="（已有 agent-loop 指针）" || m=""
      echo "- ${f}：${s}${m}"
    done
    for d in docs/agents docs/adr .claude .agents .codex; do [ -d "$repo/$d" ] && echo "- 目录 $d/"; done
    echo; echo "## 任务目录与票"
    for d in issues tickets docs/issues; do [ -d "$repo/$d" ] && echo "- $d/（$(find "$repo/$d" -name '*.md' | wc -l | tr -d ' ') 个 md）"; done
    echo; echo "## 构建与测试线索"
    find "$repo" -maxdepth 3 \( -name node_modules -o -name .git -o -name target -o -name dist \) -prune -o \
      \( -name package.json -o -name pom.xml -o -name build.gradle -o -name build.gradle.kts -o -name Makefile \
         -o -name pyproject.toml -o -name go.mod -o -name Cargo.toml \) -print 2>/dev/null | sed "s|$repo/|- |"
    [ -f "$repo/package.json" ] && grep -E '"(test|lint|typecheck|build)"' "$repo/package.json" | sed 's/^ */  scripts: /'
    echo; echo "## CI"
    ls "$repo"/.github/workflows/*.y*ml "$repo"/.gitlab-ci.yml "$repo"/Jenkinsfile 2>/dev/null | sed "s|$repo/|- |"
    echo; echo "## 本机可用的 worker 引擎"
    for e in $ENGINES; do p=$(command -v $e 2>/dev/null) && echo "- ${e}：${p}（$($e --version 2>/dev/null | head -1)）"; done
    echo; echo "## 宿主"
    [ -d /Applications/iTerm.app ] && echo "- iTerm2：已安装（launch.sh --mode tab 可用）" || echo "- iTerm2：未安装（只能用 --mode background，或手动开终端）"
    echo "- 总控唤醒能力需要在宿主中实测（bootstrap.md 第 3 步）"
    ;;
  machine)
    set -e
    mkdir -p "$AL_HOME/runs"
    m="$AL_HOME/machine.md"
    if { [ -L "$m" ] || [ -e "$m" ]; } && [ ! -f "$m" ]; then fail "本机配置路径不是普通文件：$m"; fi
    det=$(mktemp)
    generated=
    trap 'rm -f "$det"; if [ -n "$generated" ]; then rm -f "$generated"; fi' EXIT
    {
      echo "- 依赖：git $(git --version | awk '{print $3}')；bash ${BASH_VERSION}；perl $(command -v perl >/dev/null && echo 有 || echo 无)；osascript $(command -v osascript >/dev/null && echo 有 || echo 无)；iTerm2 $([ -d /Applications/iTerm.app ] && echo 有 || echo 无)"
      for e in $ENGINES; do command -v $e >/dev/null 2>&1 && echo "- 引擎 ${e}：$($e --version 2>/dev/null | head -1)"; done
      echo "- skill 目录：$SKILL_DIR"
    } > "$det"
    command -v perl >/dev/null || echo "缺少 perl：loop-state.sh 的依赖解析需要它" >&2
    if [ -f "$m" ]; then
      echo "本机配置已存在：${m}（不覆盖）。本次检测结果如下，与配置不一致的请总控核对后更新："; cat "$det"
    else
      generated=$(mktemp "$AL_HOME/.machine.XXXXXXXX")
      { sed -n '1,/^## 宿主能力/p' "$SKILL_DIR/templates/machine.md" | sed '$d' | sed "s|^- 生成时间：|- 生成时间：$(date +%Y-%m-%dT%H:%M)|"
        echo "## 本次检测"; cat "$det"; echo
        sed -n '/^## 宿主能力/,$p' "$SKILL_DIR/templates/machine.md"; } > "$generated"
      ln "$generated" "$m"
      echo "已生成本机配置：$m"; cat "$det"
      echo "下一步：按 references/bootstrap.md「本机初始化」实测宿主唤醒，并为每个引擎填写适配表的一行。"
    fi
    ;;
  init-repo)
    d=${1:?目录}; mkdir -p "$d"
    if ! git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1; then git -C "$d" init -q && echo "已 git init：$d"; fi
    if ! git -C "$d" rev-parse -q --verify HEAD >/dev/null; then
      git -C "$d" commit -q --allow-empty -m "chore: initial commit" && echo "已创建空的初始提交（worktree 需要一个基点）"
    else echo "仓库已有提交，不做改动"; fi ;;
  tracker)
    repo=$(git -C "${1:?仓库}" rev-parse --show-toplevel) || exit 1
    for f in docs/agents/issue-tracker.md docs/issue-tracker.md; do
      if [ -f "$repo/$f" ]; then echo "任务跟踪说明：$f"; exit 0; fi
    done
    for f in $ENTRIES; do
      if [ -f "$repo/$f" ] && grep -Eiq '^#{1,6}[[:space:]]+(任务跟踪|task tracking|issue tracking)[[:space:]]*$' "$repo/$f"; then
        echo "任务跟踪说明：$f"; exit 0
      fi
    done
    for d in tickets issues docs/issues; do
      if [ -d "$repo/$d" ]; then echo "票目录：$d/"; exit 0; fi
    done
    echo "未发现任务跟踪说明或票目录。在项目参数里记录本项目使用的任务来源和票目录。"; exit 2
    ;;
  conflicts)
    repo=$(git -C "${1:?仓库}" rev-parse --show-toplevel) || exit 1
    kw='总控|coordinator|开窗|回报总控|SendMessage|Status: done|自动接续|派工|认领|worktree|Monitor'
    docs=$(mktemp)
    for f in $ENTRIES; do
      [ -f "$repo/$f" ] || continue
      echo "$repo/$f" >> "$docs"
      grep -oE '[A-Za-z0-9_./-]+\.md' "$repo/$f" | while read -r ref; do
        for c in "$repo/$ref" "$repo/$(dirname "$f")/$ref"; do [ -f "$c" ] && { echo "$c" >> "$docs"; break; }; done
      done
    done
    echo "文件	命中数	判断	示例"
    sort -u "$docs" | while read -r d; do
      n=$(grep -oE "$kw" "$d" 2>/dev/null | wc -l | tr -d ' ')   # 按出现次数计
      if grep -qF '<!-- agent-loop:begin -->' "$d" && [ "$n" -lt 6 ]; then j="agent-loop 指针"
      elif [ "$n" -ge 6 ]; then j="协作流程候选"
      elif [ "$n" -ge 2 ]; then j="需要人工判断"
      else j="业务规范"; fi
      printf '%s\t%s\t%s\t%s\n' "${d#$repo/}" "$n" "$j" "$(grep -m1 -E "$kw" "$d" 2>/dev/null | cut -c1-60)"
    done
    rm -f "$docs" ;;
  codex-entry)
    set -e
    team=0; if [ "${1:-}" = --team ]; then team=1; shift; fi
    [ "$#" -eq 2 ] || fail "用法：bootstrap.sh codex-entry [--team] <工作树> <指针内容文件>"
    repo=$(git -C "$1" rev-parse --show-toplevel)
    c=$2; [ -f "$c" ] || fail "内容文件不存在：$c"
    base=AGENTS.md; override=AGENTS.override.md; entry=$base
    inherit=0; inherit_line="若同目录有 AGENTS.md，先读取该文件并遵循其中的项目规范。"
    for name in "$override" "$base"; do
      [ ! -L "$repo/$name" ] || fail "规范入口是符号链接，请先核对：$repo/$name"
      if [ -e "$repo/$name" ] && [ ! -f "$repo/$name" ]; then fail "规范入口不是普通文件：$repo/$name"; fi
    done
    if [ -f "$repo/$override" ]; then
      entry=$override
      # Codex 也会选中空的 override；填入首个指针时一并承接同目录团队规则。
      if [ -f "$repo/$base" ] && ! grep -q '[^[:space:]]' "$repo/$override"; then
        inherit=1
      elif awk -v b="$BEGIN" -v e="$END" -v line="$inherit_line" '
        $0==b { inside=1 } $0==e { inside=0 } inside && $0==line { found=1 }
        END { exit !found }' "$repo/$override"; then inherit=1; fi
    elif [ "$team" -eq 0 ] && tracked "$repo" "$base"; then
      entry=$override; inherit=1
    fi
    if [ "$team" -eq 0 ] && tracked "$repo" "$entry"; then
      echo "$repo/$entry 已被 git 跟踪。团队同意修改后可使用 codex-entry --team。" >&2; exit 7
    fi
    if [ "$inherit" -eq 1 ]; then
      wrapped=$(mktemp); trap 'rm -f "$wrapped"' EXIT
      { echo "$inherit_line"; cat "$c"; } > "$wrapped"
      c=$wrapped
    fi
    if [ "$team" -eq 1 ]; then
      "$SKILL_DIR/scripts/bootstrap.sh" inject --team "$repo/$entry" "$c"
    else
      "$SKILL_DIR/scripts/bootstrap.sh" inject "$repo/$entry" "$c"
      "$SKILL_DIR/scripts/bootstrap.sh" exclude "$repo" "$entry"
    fi
    ;;
  inject)
    set -e
    team=0; [ "${1:-}" = --team ] && { team=1; shift; }
    f=${1:?文件} c=${2:?内容文件}
    [ -f "$c" ] || { echo "内容文件不存在：$c" >&2; exit 1; }
    dir=$(cd "$(dirname "$f")" 2>/dev/null && pwd) || { echo "目录不存在：$(dirname "$f")" >&2; exit 1; }
    [ ! -L "$f" ] || fail "规范入口是符号链接，请先核对：$f"
    if [ -e "$f" ] && [ ! -f "$f" ]; then fail "规范入口不是普通文件：$f"; fi
    if git -C "$dir" rev-parse >/dev/null 2>&1 && tracked "$dir" "$(basename "$f")" && [ $team -eq 0 ]; then
      echo "$f 已被 git 跟踪。默认本机接入不修改它；改用本机覆盖文件，或经用户同意后加 --team。" >&2; exit 7
    fi
    tmp=$(mktemp "$dir/.agent-loop-entry.XXXXXXXX"); trap 'rm -f "$tmp"' EXIT
    input=/dev/null
    if [ -f "$f" ]; then input=$f; cp -p "$f" "$tmp"; fi
    awk -v b="$BEGIN" -v e="$END" -v cf="$c" '
      function block(   line, rc) {
        print b
        while ((rc = getline line < cf) > 0) print line
        if (rc < 0) exit 1
        print e
      }
      $0==b { if (seen++) exit 1; block(); inside=1; next }
      $0==e { if (!inside) exit 1; inside=0; next }
      !inside { print }
      END { if (inside) exit 1; if (!seen) { if (NR) print ""; block() } }
    ' "$input" > "$tmp" || fail "未能更新指针块，请核对 $f 中的标记和内容文件"
    mv "$tmp" "$f"; echo "已写入指针块：$f"
    ;;
  exclude)
    set -e
    repo=${1:?仓库}; shift
    ex="$(git -C "$repo" rev-parse --git-common-dir)/info/exclude"
    case $ex in /*) ;; *) ex="$repo/$ex" ;; esac
    mkdir -p "$(dirname "$ex")"; touch "$ex"
    for p in "$@"; do
      rel=${p#/}; rel=${rel%/}
      if tracked "$repo" "$rel"; then echo "跳过（已被 git 跟踪，不能当作本机专用）：$p" >&2; continue; fi
      grep -qxF "/$rel" "$ex" || grep -qxF "/$rel/" "$ex" || { [ -d "$repo/$rel" ] && echo "/$rel/" >> "$ex" || echo "/$rel" >> "$ex"; }
    done
    echo "排除列表：$ex"
    ;;
  sync)
    repo=$(git -C "${1:?仓库}" rev-parse --show-toplevel); shift
    git -C "$repo" worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r wt; do
      [ "$wt" = "$repo" ] && continue
      for p in "$@"; do
        rel=${p%/}
        [ -e "$repo/$rel" ] || continue
        mkdir -p "$wt/$(dirname "$rel")"; rm -rf "${wt:?}/$rel"; cp -R "$repo/$rel" "$wt/$rel"
      done
      echo "已同步：$wt"
    done
    ;;
  *) sed -n '2,/^set /{ /^#/p; }' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
