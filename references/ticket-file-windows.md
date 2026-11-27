# 票文件通信：非 Claude 窗口、监视、裁决的送回

总控和窗口之间以票文件为准：窗口把状态写在票头 `Status:`、把回报和待裁决写在 `## Comments`、在产物末尾写完成标记，总控靠监视发现变化。非 Claude 的窗口（Codex 等）只有这一条通道；Claude 窗口另外可以发消息提前通知，但仍以文件为准。

Codex 是非 Claude 窗口的参考实现；其他命令行模型只要能在指定目录读写文件、运行命令，就按同样的方式接入，在 `models.conf` 里给它加一行启动命令即可。

## 启动

在本票 worktree 中用开窗命令启动（[ledger.md](ledger.md)「开窗和关窗」）：

```
agent-loop window open --step <环节> --ticket <阶段>-<NN> --dir <worktree> --prompt <提示文件>
```

命令按环节取参数文件里的模型，拼出启动命令并登记。Codex 的启动命令形如：

```
codex -c check_for_update_on_startup=false -m <模型> -c model_reasoning_effort="<强度>" -s <沙箱模式> "<初始提示>"
```

- `check_for_update_on_startup=false` 只在这一次启动上关掉版本更新检查：更新提示会挡住新窗口，过了之后初始提示还会丢。它不改用户的全局设置。
- 模型和推理强度在命令里显式写出，不依赖 `~/.codex/config.toml` 的默认值。一个模型的默认强度可能和全局配置不同。
- 沙箱模式以参数文件为准。用 `danger-full-access` 时，审批策略保持 Codex 默认值，不加 `-a never` 和 `--dangerously-bypass-approvals-and-sandbox`。
- 沙箱外运行没有沙箱兜底，边界全靠初始提示约束，所以每次都按 [../templates/ticket-file-prompt.md](../templates/ticket-file-prompt.md) 写全，并写明「你在沙箱外运行，用户已授权直接访问网络和本机文件」。

## 提请裁决

窗口遇到归属冲突、spec 或票的缺口、内容相互矛盾、需要改接口契约时：

1. 在票的 `## Comments` 末尾追加：
   ```markdown
   ### 待裁决 <n>（<窗口>，<YYYY-MM-DD HH:mm>）
   - 问题：
   - 可选方案：
   - 推荐方案及理由：
   - 影响的文件或票：
   ```
2. 把票头改成 `Status: needs-decision`。
3. 停下，在窗口中等待；等待期间，有争议的部分保持不动。
4. 收到继续的指示后，读取 Comments 中对应的 `### 裁决 <n>`，照裁决继续，并把票头改回 `Status: claimed`。

## 监视

总控要盯住两类东西，Claude 窗口的票也在内（防止它的消息没发出来）：

- 所有进行中的票的票头 `Status:` 行；
- 在等待的完成标记：spec 末尾的「spec 已审定」、`tickets-common.md` 末尾的「拆票完成」、审计报告末尾的「审计完成」、前提清单末尾的「前提清单已写完」、测试文档末尾的「已完成」、回归结果末尾的「第 N 轮已完成」、合并报告末尾的「合并完成」或「合并停止」；
- 可选窗口留给总控的事：问题记录 `regression/issues-log.md` 和参数文件里的标记 `【待总控处理】`（[optional-windows.md](optional-windows.md)「给总控留事」）；
- 开了窗却没开始的窗口（下面「窗口有没有开始、还在不在」）。

票头变成 `needs-decision`、`done`、`plan-approved`，或者出现完成标记时，总控被唤醒。窗口写 Comments 不会触发。检测只有一份（`agent-loop watch`），两种总控的区别只在怎么被唤醒：Claude 总控见 [coordinator-claude.md](coordinator-claude.md)，Codex 总控见 [coordinator-codex.md](coordinator-codex.md)。

**被唤醒后**：

- `done`：照 `dev-phase.md`「6. 自动接续」处理。
- `plan-approved`：开这张票的开发窗口。
- `needs-decision`：总控职责内的事项（文件归属、票之间的分工、按已审定的 spec 和计划可以确定的事），总控直接在 Comments 写 `### 裁决 <n>`。涉及业务取舍、改 spec 或改接口契约的，先问用户，再把用户的决定写成裁决。然后送回窗口（下一节）。
- 完成标记：照对应规则接续（`stage-audit.md`、`regression-test.md` 或 `merge-window.md`）。合并报告出现「合并完成」时核对远端，把要点记进进展记录；出现「合并停止」时读报告，把停下的原因交给用户。
- `【待总控处理】`：读那几条，按内容处理（开修复票、通知在途的窗口），然后把每条的标记改成 `【总控已处理 <时间>：<结果>】`。条目转达的是用户的需求而你没有亲耳听到时，先向用户核实。

## 窗口有没有开始、还在不在

两种总控都一样，都由命令和监视负责，总控不去读窗口的屏幕，也不自己挂检查去看它启动了没有。

- **签到**：开窗命令在初始提示最前面加一行，要窗口启动后先运行 `agent-loop window hello <窗口编号>`。开窗三分钟还没签到，监视通知你一次：「W-016（audit，票 p1-13）开窗已 3 分钟还没有开始」。Claude 的计划窗口不能执行命令，改认它的会话记录。
- **收到「没有开始」**：运行 `agent-loop window list`。标签页不在的，命令把它登记为关闭，你重开（`--again`）。标签页还在的，多半停在启动时的提示上（例如 Codex 的版本更新提示，过了之后初始提示会丢）：告诉用户去那个窗口看一眼，过了提示之后对它说通知里给的那句「读 <提示文件> 并照做」。
- **送消息之前命令先确认对方还在**：`agent-loop send` 发现标签页已经关闭、或者窗口已经登记关窗时，命令失败并说明，消息不会送出。这件事还要继续时重开窗口。`agent-loop window list` 和 `agent-loop check` 也会把标签页已经不在的窗口登记为关闭并列出来。
- **按票号送消息**：一张票只开着一个窗口时可以用票号；开着两个以上（例如开发窗口和审计窗口）时命令拒绝并列出窗口，改用窗口编号。给票窗口送消息优先用窗口编号。
- **票的返工**：票头已经是 `done` 的票要返工时，窗口可能在监视两次检查之间就改完，票头看上去一直是 `done`。所以要登记返工：给这张票的开发窗口用 `agent-loop send` 送消息时命令自动登记；用别的方式送的，先运行 `agent-loop watch redo <票>`。登记之后票的内容变了、票头又是 `done`，监视再通知一次。

## 送回窗口

总控把裁决写进票的 Comments，然后提醒窗口去读。提醒的方式按窗口的引擎分：

| 窗口 | 怎么提醒 |
| --- | --- |
| Codex 窗口 | `agent-loop send <票> "裁决 <n> 已写入票的 Comments，请读取后继续" --expect <n>`（内部执行 `codex queue`）。对方正在执行一轮操作时，消息排到这一轮结束后处理 |
| Claude 窗口 | Claude 总控用 `SendMessage`；Codex 总控用同一条 `agent-loop send`，它会借一次性的小模型转发。见各自的总控规则 |

**是否收到，一律以票头从 `needs-decision` 改回 `claimed` 为准。**命令返回成功只说明消息已送出。

**超时**：送出后把这张票标成「等待接收」，几分钟后票头仍是 `needs-decision` 时，总控会被提醒「未被接收」：

1. 重送一次；
2. 再次超时，告诉用户，请用户在那个窗口说「继续」。

「等待接收」怎么标，见各自的总控规则。没有送达命令的模型，直接请用户在那个窗口说「继续」。

## 回报

窗口完成后，把回报写进票的 `## Comments`（内容和 `dev-phase.md` 第 5 节的回报一致，没做完的事单列一节「遗留事项」），再把票头改成 `Status: done`。总控通过监视发现，用户不用转告。
