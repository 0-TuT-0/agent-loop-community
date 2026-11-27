# agent-loop

一个总控会话调度多个窗口（Claude、Codex 或其他命令行模型），把一个功能从设计讨论推进到分阶段的开发、审计、合并推送和回归测试。总控只调度、核对、合入和记录；写代码、审代码、跑测试都交给窗口。

它由两部分组成：

| | 在哪里用 | 做什么 |
| --- | --- | --- |
| `agent-loop`（终端命令） | 终端 | 初始化项目、改设置、开窗口、记待办、看票台账和用量。不消耗模型调用 |
| `/agent-loop`（skill） | Claude Code 会话 | 让这个会话当总控。Codex 当总控时由 `agent-loop start` 启动 |

## 支持的系统

**目前只支持 macOS**，只在 macOS 上测试过。开窗口靠 `osascript` 控制 iTerm2，这两样只有 macOS 有。

系统和总控是两个互相独立的选择，各由一项设置决定，四种组合都可以：

| | 取值 | 决定什么 | 对应的文件 |
| --- | --- | --- | --- |
| 启动器 | `iterm`（WSL 在第三期加入） | 怎么开窗口、关窗口 | [launchers.conf](launchers.conf) 里一个系统一行 |
| 总控 | `claude`、`codex` | 总控怎么收通知、怎么把话送回窗口 | `references/coordinator-claude.md`、`references/coordinator-codex.md` |

其余规则和命令两边共用同一份。

Windows 计划通过 WSL 支持，排在第三期，当前版本还没有做。待做的两件事：

1. 给开窗口加一个 Windows 的实现：用 Windows Terminal 的 `wt.exe new-tab` 在新标签页里启动命令，作为一个新的启动器在 `launchers.conf` 里加一行（开窗、关窗、存活检查三个脚本、名称、怎么判断可用都写在这一行），已有的文件不用改。
2. 在 WSL 下把 `agent-loop` 命令和各脚本跑一遍，核对路径、符号链接。macOS 与 Linux 的命令差异已经集中在 `scripts/lib/compat.sh`。

原生 Windows（PowerShell、cmd）和 Linux 不在计划内。

总控可以是 Claude Code 或 Codex 命令行；被派工的窗口可以是 Claude、Codex 或其他命令行模型。Codex 当总控的部分已经实现，还没有在项目上完整跑过。

## 安装（每台电脑一次）

```bash
git clone https://github.com/0-TuT-0/agent-loop-community.git "$HOME/.claude/skills/agent-loop"
"$HOME/.claude/skills/agent-loop/scripts/install.sh"
```

第二行把 `agent-loop` 命令链接到 `~/.local/bin/`，并给 Codex 注册这个 skill。

依赖：

| 依赖 | 用途 |
| --- | --- |
| git | worktree、分支、合并 |
| Claude Code | 总控，以及 Claude 窗口 |
| iTerm2 | 在新标签页里开窗口 |
| mattpocock 的 skill | 流程里用到 `/wayfinder`、`/grilling`、`/to-spec`、`/to-tickets`、`/implement` |
| Codex CLI | 用 Codex 窗口或 Codex 总控时需要 |

运行 `agent-loop check` 查看缺什么。

## 快速开始（每个项目一次）

1. **跑 mattpocock 的初始化**，票的位置选本地 markdown。Claude Code 里输入 `/setup-matt-pocock-skills`，或 Codex 里输入 `$setup-matt-pocock-skills`，任选其一。
2. **在项目目录运行 `agent-loop init`**。它逐项问可枚举的设置，每项直接回车接受预填值，确认后写入 `docs/agents/loop-profile.md`，并在 `AGENTS.md` 或 `CLAUDE.md` 里加索引。
3. **在规范维护窗口里补齐其余的项**。上一步结束时会开启这个窗口，它一项一项问你需要判断的内容：测试命令、只读目录、共享模块、高风险的具体含义等。
4. **启动总控**：`agent-loop start <功能名>`。

之后的日常是：在总控窗口里审定 spec 和计划、回答裁决、对审计结论表态、同意合并。开发中想到的点子用 `agent-loop todo "……"` 记下来，不用打断总控。

## 终端命令

所有命令都在项目目录里运行；在任何 worktree 里运行，改的都是主工作树里的那一份参数文件。

| 命令 | 功能 |
| --- | --- |
| `agent-loop` | 显示菜单，从中选择下面的功能 |
| `agent-loop init` | 初始化项目：逐项设置，生成参数文件，加索引，把本机专用文件加进 git 的本机排除。已有参数文件时以现值为预填，只改你想改的项 |
| `agent-loop init --defaults` | 全部用默认值初始化，不提问 |
| `agent-loop init --no-open` | 初始化结束时不询问是否开启规范维护窗口 |
| `agent-loop show` | 查看当前所有设置，以及还有几项待完善 |
| `agent-loop set` | 列出所有设置项，选一项修改 |
| `agent-loop set <项>` | 交互修改一项。项可以写名称（`开发模型`）或键（`model.dev`） |
| `agent-loop set <项> <值>` | 直接赋值。写 `-` 清空。例：`agent-loop set 开发模型 claude-opus` |
| `agent-loop set AI文件不提交 关闭 --personal` | 关闭这条护栏只允许个人项目：交互时会要求确认，直接赋值时要加 `--personal` |
| `agent-loop start <功能名>` | 新建或接续一个功能，在新标签页里启动总控。这个功能已有登记的总控会话时恢复它；总控正在运行时不重复开启 |
| `agent-loop start` | 不指定功能名，由总控按规则确定接着做哪个功能 |
| `agent-loop start <功能名> --new` | 不恢复登记的总控会话，开一个全新的会话接手。状态都在文件里，新会话读一遍就能继续；旧会话太长或出了问题时用。先关掉旧的总控窗口 |
| `agent-loop open 规范维护` | 开启规范维护窗口；已登记的会话还在时恢复它，正在运行时不重复开启 |
| `agent-loop open 错误对接` | 开启错误对接窗口，规则同上 |
| `agent-loop start … --print`、`agent-loop open … --print` | 只打印启动命令，不开窗口 |
| `agent-loop check` | 检查环境依赖，以及 Codex 总控的常驻监视是否在运行 |
| `agent-loop --help` | 显示用法 |

**待办清单**（你和总控都会用）

| 命令 | 功能 |
| --- | --- |
| `agent-loop todo "<内容>"` | 记一条「想法」：现在不做、以后做不做还没定 |
| `agent-loop todo "<内容>" --must` | 记一条「遗留」：现在不做、以后必须做 |
| `… --due <合并前\|功能结束前\|上生产前>` | 给条目加建议时限。只是提醒，没有约束力 |
| `… --by <谁>` | 记录人，默认是「用户」；总控替你记时写 `--by 用户`，自己记时写 `--by 总控` |
| `agent-loop todo` | 查看未处理的条目 |
| `agent-loop todo --all` | 连已关闭的一起看 |
| `agent-loop todo --count` | 只输出一行统计，例如「待办：遗留 3 条（1 条建议合并前处理）、想法 5 条」 |
| `agent-loop todo --due-now <时限>` | 列出建议在这个时限前处理的遗留 |
| `agent-loop todo close <编号> --to <去向> [说明]` | 给一条定去向：`spec`（并入下一阶段 spec）、`ticket`（开成票）、`feature`（另开功能）、`done`（已完成）、`drop`（不做）、`keep`（继续留着）。遗留条目要 `drop` 时必须写原因 |
| `agent-loop todo due <编号> <时限>` | 改建议时限，`-` 清空 |

**票台账与用量**

| 命令 | 功能 |
| --- | --- |
| `agent-loop ledger` | 完整的票台账：每张票的风险、每一步的模型、开窗和完成时间、裁决、返工、计划修改、审计问题、用量；其他窗口的用量；按模型汇总；会话 ID |
| `agent-loop ledger <阶段>` | 只看一个阶段 |
| `agent-loop ledger --summary`、`agent-loop usage [<阶段>]` | 只看按模型汇总：票数、返工、裁决、审计问题、用量 |
| `agent-loop ledger done <票>` | 记这张票的完成时间并取一次用量。总控在票合入后运行 |
| `agent-loop ledger rework <票>` | 记一次返工：票回报完成后被退回重做 |
| `agent-loop ledger plan-revise <票>` | 记一次计划修改：高风险票的计划被你要求改 |
| `agent-loop ledger audit <票或阶段> <严重程度>=<数量> …` | 记审计问题，例如 `agent-loop ledger audit p1-03 阻塞=1 应修=2` |
| `agent-loop ledger source <修复票> <来源票>` | 注明修复票修的是哪张票的问题 |
| `agent-loop ledger snapshot` | 重新取所有窗口的用量并存下 |
| `agent-loop ledger undo` | 撤销最后一条记录 |

用量直接从 Claude 和 Codex 的会话记录里汇总，分输入（含写入缓存的部分）、输出、缓存读取三个数。规范维护窗口和错误对接窗口属于整个项目，各自单独计算，在表的最后按窗口名各列一行，不计入功能的合计。

**窗口**（总控用；你一般不需要手动运行）

| 命令 | 功能 |
| --- | --- |
| `agent-loop ticket open <票> --prompt <提示文件> [--step plan\|dev\|fix] [--fix]` | 一张票开工：建 worktree 和票分支、复制本机专用文件、在票头补上分支和 worktree、按环节取模型、开窗并登记。`--fix` 表示修复分支上的票。提示里的 `{{WORKTREE}}` 等占位由命令替换 |
| `agent-loop ticket verify <票>` | 核对一张完成的票：一次列出票头、票分支的提交、改动的文件、工作区是否干净、完成回报 |
| `agent-loop ticket merge <票>` | 把票分支以 `--no-ff` 合入阶段分支或修复分支，登记完成时间和关窗；有冲突时撤销合入并列出冲突的文件。「自动清理worktree」启用时顺带删掉这张票的 worktree |
| `agent-loop worktree prune [--yes]` | 列出可以清理的票 worktree 和大小（分支已合入、工作区干净、没有窗口开着），确认后删除。只删 worktree，保留分支；集成 worktree 不动。你也可以自己运行它来清理积压 |
| `agent-loop window open --step <环节> --dir <目录> --prompt <提示文件> [--ticket <票>] [--stage <阶段>] [--model <编号>] [--again] [--print]` | 开一个工作窗口：按环节取模型、拼启动命令、开窗，并登记到票台账。同一张票的同一环节已有窗口开着时拒绝，`--again` 强制再开 |
| `agent-loop window close <窗口编号\|票号> [--record-only]` | 关窗并登记；`--record-only` 只登记，窗口留给你关 |
| `agent-loop window list` | 列出还开着的窗口。顺带确认每个窗口的标签页还在，不在的登记为关闭并标出来 |
| `agent-loop window hello <窗口编号>` | 窗口启动后签到。开窗命令会在初始提示最前面要求窗口运行它；三分钟没签到，监视通知总控 |
| `agent-loop window register --step <环节> --session <会话ID>` | 补登记一个不是用 `window open` 开的窗口 |
| `agent-loop send <窗口编号\|票号> "<消息>" [--expect <裁决编号>] [--redo <文件>]` | 给一个窗口送消息：Codex 窗口用 `codex queue`，Claude 窗口用一次性的小模型转发。送之前确认对方的标签页还在，不在就失败；一张票开着两个以上的窗口时按票号送会被拒绝，改用窗口编号。给票头已经是 `done` 的开发窗口送消息时自动登记返工。`--expect` 登记「等待接收」；`--redo` 用于让窗口返工一份已经写过完成标记的文件，改完后监视会再通知一次 |

**回归测试与监视**

| 命令 | 功能 |
| --- | --- |
| `agent-loop regress` | 统计各阶段的测试结果，生成 `regression/summary.md`，并列出失败和未测的编号 |
| `agent-loop watch wait [--restart] [--timeout <秒>]` | Claude 总控用：挂成后台任务，功能目录有变化就打印并退出，唤醒总控；处理完重挂。默认没有时限，没有变化就一直等。`--restart` 先停掉这个功能上别的监视 |
| `agent-loop watch restart --thread <总控会话ID>` | Codex 总控用：停掉别的监视，启动指向自己的常驻监视，有变化时给总控发消息 |
| `agent-loop watch stop`、`agent-loop watch status` | 停掉这个功能上的所有监视（两种都算，通知记录保留）；查看常驻监视 |
| `agent-loop watch expect <票> <裁决编号>` | 登记一条裁决「等待接收」，超时未接收时提醒总控 |
| `agent-loop watch redo <文件>` | 让窗口返工一份已经写过完成标记的文件之前登记，改完后监视再通知一次 |

涉及功能目录的命令都可以加 `--feature <功能名>`；任务目录下只有一个功能时自动选它。

改动从总控下一次开窗起生效，已经在运行的窗口不变。`set` 和 `open` 也可以直接对总控说，它会替你执行并把你的原话记进变更记录。

## Skill 指令

| 指令 | 在哪里输入 | 功能 |
| --- | --- | --- |
| `/agent-loop <功能名>` | Claude Code | 让当前会话当这个功能的总控。总控重启或恢复后再输入一次，它会重新加载规则、核对状态、挂上监视 |
| `/agent-loop` | Claude Code | 同上，不指定功能：只有一个未完成的功能就接着做；有多个时问你；需要新建时按「功能命名」设置处理 |

Codex 当总控时没有斜杠指令：把「总控」设为 `codex` 后运行 `agent-loop start <功能名>`，它会启动 Codex 并让它读 [codex/SKILL.md](codex/SKILL.md)。

对总控说的几句常用的话：

| 你说 | 总控做什么 |
| --- | --- |
| 「记一条：……」 | 把你的原话记进待办清单 |
| 「过一遍待办」 | 列出全部未处理的条目，逐条给出建议的去向，由你决定 |
| 「继续」 | 总控恢复或重启后，重新核对状态并接着做 |

流程里用到的其他 skill，由对应的窗口调用，不需要你手动输入：

| 指令 | 谁调用 | 功能 |
| --- | --- | --- |
| `/setup-matt-pocock-skills` | 你，每个项目一次 | 建立票目录等约定，是 `agent-loop init` 的前置条件 |
| `/wayfinder` | 总控和模块窗口 | 讨论阶段：画地图，按票讨论 |
| `/grilling` | 模块窗口 | 讨论阶段：和你逐项确认设计决定 |
| `/to-spec` | 总控或 spec 窗口 | 把讨论结果汇总成 spec |
| `/to-tickets` | spec 或拆票窗口 | 把审定的 spec 拆成开发票 |
| `/implement` | Claude 开发窗口 | 照票和计划实现，测试先行 |

## 设置项

用 `agent-loop set <项> <值>` 修改。「项」一栏是名称，括号里是键，两种写法都可以。

**模型**（取值是 [models.conf](models.conf) 里的编号，或者 `custom:<启动命令>`）

| 项 | 默认 | 用在哪个环节 |
| --- | --- | --- |
| spec模型（`model.spec`） | `claude-fable` | 写阶段 spec |
| 拆票模型（`model.tickets`） | `claude-fable` | 把 spec 拆成票 |
| 高风险计划模型（`model.plan`） | `claude-fable` | 高风险票的计划，Claude 模型用计划模式 |
| 开发模型（`model.dev`） | `codex-sol-medium` | 所有开发票和修复票 |
| 收尾模型（`model.closing`） | `codex-sol-medium` | 收尾票：全套回归 |
| 审计模型（`model.audit`） | `codex-astra-high` | 阶段审计、单票审计 |
| 合并模型（`model.merge`） | `claude-opus` | 合并窗口 |
| 测试流程模型（`model.testdoc`） | `codex-sol-medium` | 写回归测试文档；回归的执行窗口也用它 |

预置的模型编号：`claude-fable`（Claude Fable 5.2）、`claude-opus`（Claude Opus 5.5）、`codex-sol-medium`（Codex gpt-6.2-sol，medium）、`codex-astra-high`（Codex gpt-6.2-astra，high）。规范维护窗口和错误对接窗口的模型跟着总控走，不单独设置。

**流程**

| 项 | 取值 | 默认 | 说明 |
| --- | --- | --- | --- |
| 总控（`coordinator`） | `claude`、`codex` | `claude` | 总控用谁。Claude 总控用 Claude Fable 5.2，Codex 总控用 Codex gpt-6.2-astra（high） |
| 启动器（`launcher`） | `iterm` | `iterm` | 怎么开窗口。清单在 `launchers.conf` |
| 自动接续（`flow.auto-continue`） | `自动`、`需确认` | `自动` | 一张票做完后，总控是自己核对、合入、开下一张，还是核对后等你确认。它只管票完成之后的这一步：你直接提出的需求写成票后，开它的第一个窗口不用再确认 |
| 功能命名（`feature.naming`） | `建议后确认`、`总控确定` | `建议后确认` | 需要新建功能目录而你没给名字时，由谁定名 |
| 测试方式（`test.mode`） | `unified`、`per-stage` | `unified` | 统一回归，或每阶段本地测试 |
| 讨论阶段（`stage.discussion`） | `启用`、`关闭` | `启用` | 多窗口讨论；目标明确时可以关掉 |
| 收尾票（`stage.closing`） | `启用`、`关闭` | `启用` | 每阶段跑一次全套回归 |
| 阶段审计（`stage.audit`） | `启用`、`关闭` | `启用` | 阶段结束时审整体改动 |
| 合并窗口（`stage.merge`） | `启用`、`关闭` | `启用` | 同步、合并、推送 |
| 回归测试（`stage.regression`） | `启用`、`关闭` | `启用` | 发布后的功能测试 |

**窗口**

| 项 | 取值 | 默认 | 说明 |
| --- | --- | --- | --- |
| 错误对接窗口（`window.error-intake`） | `启用`、`关闭` | `关闭` | 是否使用这个可选窗口 |
| 规范维护窗口（`window.maintainer`） | `启用`、`关闭` | `关闭` | 是否使用这个可选窗口；关闭时由总控兼任改规则 |
| 自动关窗（`window.auto-close`） | `启用`、`关闭` | `关闭` | 总控验收某个窗口的结果后是否自己关掉它 |
| 窗口上限（`window.limit`） | 数字，或留空 | 留空 | 同时开着的窗口数；留空表示不限 |
| 自动清理worktree（`worktree.auto-clean`） | `启用`、`关闭` | `启用` | 票合入后是否删掉它的 worktree。工作区干净才删，只删 worktree、保留分支 |

**护栏**

| 项 | 默认 | 说明 |
| --- | --- | --- |
| 会话不连库（`guard.no-db`） | `启用` | 窗口只交付脚本，数据库和共享环境由你操作 |
| AI文件不提交（`guard.ai-files-local`） | `启用` | `AGENTS.md`、`CLAUDE.md`、`docs/agents/`、任务目录只留在本机。只有个人项目才允许关闭 |
| 新行为放开关后（`guard.feature-flags`） | `启用` | 每阶段可独立上线，新行为默认放在开关后面 |
| Codex沙箱（`codex.sandbox`） | `danger-full-access` | Codex 窗口的沙箱模式。另两种取值下 Codex 写不了主工作树里的票文件，也无法在 worktree 里提交 |

**分支**

| 项 | 默认 | 说明 |
| --- | --- | --- |
| 远端（`branch.remote`） | 仓库的第一个远端 | 合并窗口推送到哪里 |
| feature分支（`branch.feature`） | 初始化时的当前分支 | 阶段分支从它开出，合并窗口第 1 轮推送它 |
| 共享环境分支（`branch.shared`） | 留空 | 推送后部署到共享环境的分支；有的话合并窗口多做第 2 轮 |

其余需要判断的内容（分支前缀、只读目录、高风险的具体含义、测试命令、数据库脚本位置、项目规范清单等）不在这张表里，由规范维护窗口在对话里写进参数文件。

## 窗口

| 窗口 | 谁开 | 做什么 |
| --- | --- | --- |
| 总控 | 你：`agent-loop start <功能名>` | 调度、核对、合入、裁决分工、记录进展。不写代码、不审代码 |
| 模块讨论 | 你，照总控给的开窗清单 | 认领一张讨论票，和你确认设计决定 |
| spec、拆票 | 总控 | 写阶段 spec，你审定后拆成票 |
| 计划 | 总控 | 高风险票先出计划，逐项问完待明确事项后交你审定。只读 |
| 开发 | 总控 | 一个窗口做一张票：测试先行，本地提交，回报 |
| 收尾 | 总控 | 跑全套回归，与基准比对 |
| 审计 | 总控 | 只读审查阶段的整体改动，结论分阻塞、应修、建议，由你逐条决定 |
| 合并 | 总控，在你同意之后 | 同步远端、合并、验证、推送。只有它推送 |
| 测试文档 | 总控 | 分两步写回归测试文档：先写前提清单交你表态，再按表态写测试项 |
| 规范维护（可选） | 你：`agent-loop open 规范维护` | 改参数文件和项目规范。初始化时由它补齐待完善项 |
| 错误对接（可选） | 你：`agent-loop open 错误对接` | 你贴报错，它只读定位、编号记录，经你同意后通知总控开票 |

## 流程

```
讨论：多窗口 grilling → 地图收敛 → 开发计划分阶段
每个阶段：spec → 你审定 → 拆票 → 开发 ─┬─ 高风险票：计划窗口 → 你审定 → 开发窗口
                                       └─ 中低风险票：一个窗口完成
        → 收尾票 → 阶段审计 → 你逐条决定 → 修复票（代码完成）
        → 合并窗口（feature 分支 → 共享环境分支）─┬─▶ 回归测试（不阻塞）
                                                  └─▶ 你过一遍待办清单 → 下一阶段
发布之后：问题、小优化、新需求都走修复分支，攒几张一起合并
```

关掉的环节直接跳过。全部可选环节都关掉时，流程是「spec → 拆票 → 开发 → 合入」。

需求和问题的入口只有三个：你直接对总控说、错误对接窗口、回归测试的结果。其他窗口收到无关的需求时只提醒你去找总控。

### 三份记录

| | 回答什么 | 什么时候看到 |
| --- | --- | --- |
| 开窗清单 | 现在该做什么：可以开的窗口、进行中的、等你做的事 | 总控的每次回复 |
| 待办清单 | 哪些事现在不做、以后要回来处理（遗留和想法） | 每次回复里一行统计；每个阶段开始前和功能结束时列出全部，请你逐条表态 |
| 票台账 | 事后回看：哪个模型返工多、审计问题多、各环节花了多少 token | 平时不出现；阶段结束和功能结束时总控附一段按模型汇总；随时可以用 `agent-loop ledger` 看完整的表 |

卡着某张票的事只在开窗清单里；不卡任何一张票的事进待办清单。待办清单的建议时限只是提醒，到点没处理不会拦着流程。

### 回归测试

1. **前提清单**：编写窗口先列出测试需要的账号、数据、脚本和写操作，每条注明影响多少测试项。你对每条表态：已具备、可以准备、准备不了。
2. **测试项**：一个场景一项，标「必测」或「选测」。依赖「准备不了」的前提的项标为不测。
3. **执行**：你说开始回归时，总控开一个执行窗口，你在那个窗口里操作和回答，默认只测必测。总控自己不执行测试。结论只有通过、失败、未测、不测四种。
4. **收口**：失败的开修复票，未测的进待办清单。没有失败项时总控只汇报一行状态，不需要你另外表态。修复后只复测对应的项。

## 文件

| 文件 | 位置 | 内容 |
| --- | --- | --- |
| 参数文件 | `docs/agents/loop-profile.md`（主工作树） | 这个项目的全部设置。只有这一份，所有窗口按主工作树的路径读 |
| 索引 | `AGENTS.md` 或 `CLAUDE.md` 里的 `### Agent loop` 小节 | 告诉手动打开的窗口去哪里读参数和规则 |
| 功能目录 | `<任务目录>/<功能>/`，任务目录默认 `.scratch/` | 一个功能的全部文档 |

```
.scratch/<功能>/
  dev-plan.md              开发计划：总原则、阶段表、开发约定、跨阶段前提、进展记录
  map.md                   讨论阶段的地图
  todo.md                  待办清单，由 agent-loop todo 维护
  ledger.md                票台账，由 agent-loop ledger 生成；数据在 ledger/
  regression/              回归测试文档（每个阶段一份前提清单、计划、结果，另有统计）、错误对接窗口的问题记录
  <阶段>/                  例如 p1/
    spec.md
    tickets-common.md      各票的公共约定和文件归属
    issues/  plans/  reviews/
```

一个功能是一个能整体验收的目标，通常是一个大的功能模块，对应一份开发计划、一个总控、一条修复分支。

## 仓库里有什么

| 路径 | 内容 |
| --- | --- |
| [SKILL.md](SKILL.md) | 总控工作流的入口（Claude 总控） |
| [codex/SKILL.md](codex/SKILL.md) | Codex 总控的入口 |
| `references/` | 各环节的规则：讨论、开发计划、开发阶段、票文件通信、审计、合并、回归测试、发布之后、可选窗口、数据库与共享环境、开窗清单、计划格式、票台账、待办清单；`coordinator-claude.md`、`coordinator-codex.md`、`session-identity.md` 是按总控引擎分开的部分 |
| `templates/` | 参数文件模板、各类窗口的初始提示模板 |
| [models.conf](models.conf) | 模型清单：编号、引擎、显示名、启动命令。可以加行 |
| [launchers.conf](launchers.conf) | 启动器清单：一个系统一行，写明它的开窗、关窗、存活检查三个脚本、名称和怎么判断可用。公共代码不认识任何具体的系统 |
| `scripts/agent-loop`、`scripts/lib/` | 终端命令。`lib/compat.sh` 集中了 macOS 与 Linux 的命令差异 |
| `scripts/install.sh` | 安装 |
| `scripts/open-tab.sh`、`scripts/close-tab.sh`、`scripts/alive-tab.sh` | iTerm2 启动器：开标签页、关标签页、查标签页还在不在。由 `agent-loop window` 和 `agent-loop send` 调用 |
| `tests/cli.sh` | 终端命令的离线测试 |

## 后续计划

- **第二期**（已实现，待在项目上实跑验证）：票台账与用量统计；待办清单；回归测试的前提清单和收口；Codex 当总控；系统与总控的隔离。
- **第三期**：Windows 通过 WSL 支持。
- **第四期**：Codex 总控下的讨论阶段。现在常驻监视不盯讨论阶段的地图，模块窗口讨论完一张票后需要你对 Codex 总控说一声；也可以讨论阶段用 Claude 总控、开发阶段再换成 Codex。
