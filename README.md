# agent-loop

一个总控会话按票把工作派给多个编码 Agent。每张票记录依赖、负责的文件、当前运行和完成证据。worker 通过票文件提问或交付，用户可以在需要决定业务语义、调整接口或授权发布时介入。

## 安装

Claude Code 和 Codex 可以共用一份 checkout。在终端运行：

```bash
git clone https://github.com/0-TuT-0/agent-loop-community.git "$HOME/.claude/skills/agent-loop"
"$HOME/.claude/skills/agent-loop/scripts/bootstrap.sh" install codex
```

只用 Codex 时，也可以直接安装到它的用户技能目录：

```bash
git clone https://github.com/0-TuT-0/agent-loop-community.git "$HOME/.agents/skills/agent-loop"
```

从任意位置维护 checkout 的用户，也可以在仓库根目录执行 `./scripts/bootstrap.sh install codex`。该命令会创建链接，并保留已经存在的其他同名目录。

## 从一张票开始

1. 在目标项目打开新会话。Codex 输入 `$agent-loop 只做本机和项目初始化`，Claude Code 输入 `/agent-loop 只做本机和项目初始化`。
2. 在项目配置中写明票目录、引擎、角色分工、验证命令，以及允许交付到哪个本地分支。机器能力与项目配置分开保存。详见[初始化指南](references/bootstrap.md)和[角色分工](references/routing.md)。
3. 按[票模板](templates/ticket.md)准备一张低风险票，向总控指定票目录和集成目标。总控认领并派工。worker 在票中回报提交或产物，总控按[验收规则](references/verification.md)检查。

等待由本机 shell 监视器承担。只有经过实测，宿主才能标为支持跨轮自动唤醒。其他宿主需要用户回到总控会话接续。首次启用真实项目时，先用本地测试票确认裁决送回、返工和中断恢复适合所选引擎。[宿主能力](references/engines.md) · [恢复流程](references/recovery.md)

## 离线验证

需要 Bash、Git、Perl 和常见 Unix 命令。后台 worker 可通过 CLI 启动；自动打开 iTerm2 标签页是 macOS 的可选功能。在仓库根目录运行：

```bash
./tests/loop-behavior.sh
```

用例在临时 Git 仓库里运行模拟 worker，覆盖认领、依赖、监视、产物验收以及安装入口。真实模型、宿主唤醒和消息送达需在使用机器上分别验证。
