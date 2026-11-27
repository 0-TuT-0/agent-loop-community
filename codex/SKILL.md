---
name: agent-loop-codex
description: 总控工作流的 Codex 入口：由 Codex 担任总控，调度多个窗口把功能从设计讨论推进到开发、审计、合并和回归测试。由 agent-loop start 在「总控」设为 codex 时启动。
---

# 总控工作流（Codex 入口）

你是**总控**，由 Codex 担任。总控的职责、流程和护栏写在上一级目录的 [../SKILL.md](../SKILL.md) 里，那份文件对你同样适用，只有三处按本文件来：

| `../SKILL.md` 里的内容 | 你怎么做 |
| --- | --- |
| 「启动」一节 | 用本文件的「启动」 |
| 凡是写「见 `references/coordinator-claude.md`」的地方 | 读 [../references/coordinator-codex.md](../references/coordinator-codex.md) |
| `references/session-identity.md` | 那是 Claude 会话的登记方式；你的登记方式在 `coordinator-codex.md`「身份登记」 |

规则文件都在 `../references/`，模板在 `../templates/`，路径相对上一级目录。

## 启动

1. 读主工作树里的参数文件 `docs/agents/loop-profile.md`（主工作树是 `git worktree list` 的第一项）。文件不存在时，告诉用户先在终端运行 `agent-loop init`，然后停下。「设置」表里「总控」的取值不是 `codex` 时，告诉用户当前参数文件要的是 Claude 总控，然后停下。
2. 参数文件里还有标着「待完善」的项时，列出这些项并停下。
3. 读参数文件「项目规范」列出的每份文档。项目规范与本 skill 冲突时，以项目规范为准。
4. 读 [../SKILL.md](../SKILL.md) 的「入口」「生命周期」「总控的固定动作」「护栏」，以及 [../references/coordinator-codex.md](../references/coordinator-codex.md)。
5. 确定本次管的是哪个功能：规则与 `../SKILL.md`「启动」第 5 步相同。
6. 登记身份并重启常驻监视（启动、恢复、接手都重启，不是「不在才启动」）：照 `coordinator-codex.md`「身份登记」做。
7. 读这个功能的开发计划的开发约定和最近的进展记录，把全部票的现状看一遍，判断每个阶段走到了哪一步。开发计划还不存在时，按 `../SKILL.md`「入口」选择从哪里开始。
8. 输出当前进展，末尾附开窗清单和待办清单的一行统计。

完成标准：用户知道你在管哪个功能；开发计划顶部有你的登记行；已经运行过 `agent-loop watch restart` 并且 `agent-loop watch status` 报告监视在运行；用户看到了开窗清单。
