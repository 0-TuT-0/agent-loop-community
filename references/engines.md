# 引擎适配

**引擎**是运行 worker 的命令行程序（例如 `claude`、`codex`），负责启动会话、读写文件、运行命令、管理沙箱和权限。**模型**是引擎里实际思考的大模型，同一个引擎通常能选多个模型。**宿主**是总控所在的工具。

worker 引擎是可替换的：任何能在终端里运行、能读写文件和运行命令的编码 agent 都可以接入。每个引擎在**引擎适配表**里占一行。引擎是电脑的属性，所以适配表放在本机配置 `machine.md` 里，项目参数只写不同的部分。总控只按这张表派工，流程里不写死任何引擎。

## 引擎适配表的字段

| 字段 | 说明 |
| --- | --- |
| 名称 | 在票头 `Engine:` 和路由表中使用的名字 |
| 启动命令模板 | 可含 `{model}`、`{effort}` 占位符。总控按路由表替换完所有占位符（没有推理强度时，把对应参数整个去掉），再交给 `launch.sh`。还有没替换的占位符时，`launch.sh` 会拒绝启动 |
| 提示传入方式 | `arg`：作为最后一个参数传入；`stdin`：从标准输入传入；`file`：命令模板里用 `{prompt_file}` 占位，由 `launch.sh --prompt-mode file` 替换成提示文件路径 |
| 运行方式 | `tab`：在终端新标签页交互运行，用户能看到、能插话；`background`：后台无交互运行，输出写入日志文件 |
| 能力等级 | L1、L2、L3，见下文 |
| 送回方式 | `message`（引擎自带的会话间消息）、`queue`（引擎提供的命令行入队）或 `restart`（退出重启） |
| 会话 ID 查找 | 怎样找到这个 worker 的会话 ID（`queue` 方式需要） |
| 权限参数 | 沙箱、审批相关的参数和取值；沙箱被关闭时要在这里写明 |
| 可用模型 | 允许使用的模型和推理强度 |
| 咨询命令 | 只读、非交互的单次调用命令，供其他 worker 直接调用；不允许时留空 |

| 实测记录 | 接入时实测的结果和日期：提示传入、送回是否送达、能否读到规范入口 |

接入新引擎时，先用它的 `--help` 核实每个参数，再按 `bootstrap.md` 第 3 步，用一张低风险票试跑一次。适配表里只填实测结果，不填推测。

## 能力等级

| 等级 | 能力 | 达不到时怎么办 |
| --- | --- | --- |
| **L1（必需）** | 在指定目录读写文件，运行命令（git、测试），按提示工作到结束 | 不能当 worker |
| **L2（可选）** | 中途停下后，能接收新消息继续工作 | 用退出重启 |
| **L3（可选）** | 能主动通知总控 | 不需要：总控靠监视票文件 |

## 宿主能力（总控所在的工具）

在 `machine.md` 中按实际宿主和版本记录。项目特有的覆盖写入 profile。

| 能力 | 取值 | 影响 |
| --- | --- | --- |
| 宿主唤醒 | `auto`：监视脚本退出后自动唤醒总控；`manual`：需要用户回到总控窗口 | `manual` 时，总控每次启动都要告诉用户这一点；无人值守只能做到「用户回来后接着跑」 |
| 交互开窗 | `tab`（例如 iTerm2）/ 无 | 没有时，交互角色只能请用户手动开终端，总控给出启动命令 |
| 后台运行 | 可以 / 不可以 | 不可以时，L1 引擎只能交互运行 |

## 角色需要的能力

路由时，先按角色需要的能力筛选引擎，再按 `routing.md` 的默认分工选模型。没有满足能力的引擎时，交给用户决定。

| 角色 | 需要的能力 |
| --- | --- |
| `plan` | 交互运行（用户在窗口里审定计划） |
| `implement` | L1；高风险票建议 L2，便于裁决后接续 |
| `report` | L1，可以后台运行 |
| `release` | 交互运行（遇到停止条件时，用户在窗口里决定） |
| `test` | 交互运行（写入步骤和放开安全参数都要用户确认） |

## 派工

1. **认领**：`loopctl -r <运行目录> -o <总控标识> -g <代次> claim <票> <Run-id>`。只有 `Run` 为 `idle` 时才会成功，并原子地改为 `dispatched`。失败说明这张票已经被派工，不要重试。
2. **建工作区**：worktree 已经存在（比如重派、接续）时复用；不存在时执行 `git worktree add <worktree 根目录>/<阶段>-<NN> -b <票分支> <阶段分支>`。按 [项目接入](bootstrap.md) 同步 profile 列出的本机文件，并在目标 worktree 注入所需的 Codex 入口。
3. **填写票头**：用 `loopctl … set` 逐项写入 `Role`、`Engine`、`Model`、`Branch`、`Worktree`、`Worker`、`Started`、`Deadline`。`Worker` 填 pid 文件路径 `<运行目录>/<Run-id>/worker.pid`。pid 和日志都放在运行目录，不放进 worktree，所以不会影响「工作区干净」的检查。
4. **写提示**：先按 `worker-contract.md`「生效规则」算出本票生效规则，存为 `<运行目录>/<Run-id>/rules.md`；再按 `templates/worker-prompt.md` 写出提示，存为 `<运行目录>/<Run-id>/prompt.md`。
5. **启动**：先 `loopctl … intent <Run-id>.launch launch <引擎>`，启动后 `loopctl … result <Run-id>.launch <pid>`：

   ```
   scripts/launch.sh --dir <worktree> --prompt <运行目录>/<Run-id>/prompt.md --pid <运行目录>/<Run-id>/worker.pid \
     --mode <tab|background> --prompt-mode <arg|stdin|file> -- <启动命令…>
   ```
   脚本会把 worker 进程的 pid 写入 pid 文件，监视脚本据此判断 worker 是否还在运行。pid 文件对应的进程还在运行时，脚本会拒绝启动（退出码 6），所以恢复时重复执行也是安全的。
6. **加入监视**：把 `<票>@<pid文件>` 加进监视参数，重新挂上监视。

## 送回

总控写好裁决后：
- **message**：通过本机实测可用的会话消息接口，请 worker 读取票上的裁决。

不论用哪种方式，都要在裁决块的「送出」一项里写明方式和时间。worker 改回 `claimed` 并写上 `Ack` 之后，才算读到了裁决。
- **queue**：用本机引擎适配表中已验证的入队命令，将票路径和裁决编号送至该 worker 的会话。对方正在执行一轮操作时，消息可能要等这一轮结束才会出现。消息送不到时，改用 restart。
- **restart（退出重启）**：
  1. 确认原 worker 已经退出：pid 不存在，或者已经请用户关闭它的标签页。
  2. 用新的 `Run-id` 重新派工（状态转换表 T1），复用原 worktree。提示里写明「本次是接续：先读 Comments 的全部记录和已有提交，从裁决 <n> 处继续」。
  3. 新 worker 开工后，把 `Run` 改为 `claimed`，并在票头写 `Ack: 裁决 <n>`。

L1 的引擎只能用 restart；需要裁决时，worker 写好待裁决就退出。

## 直接调用（worker 之间）

worker 之间不直接派活，所有派工都经过总控。参数文件允许时，worker 可以用别的引擎的**咨询命令**做一次只读的审查或咨询，例如让另一个模型看自己的 diff。规则：

- 只用参数文件列出的咨询命令，以只读权限运行，并设好时限。
- 结论写进票的 `### 咨询` 块；是否采纳由当前 worker 自己判断，并在完成回报中说明。
- 咨询结果和其他材料一样，不能扩大当前 worker 的权限边界。

## 示例行（接入前逐项核实）

| 名称 | 启动命令模板 | 提示 | 运行 | 等级 | 送回 | 咨询命令 |
| --- | --- | --- | --- | --- | --- | --- |
| claude | `claude --model {model}` | arg | tab | L1+L2+L3 | message | `claude -p --model {model}`（需配置只读权限） |
| codex | `codex -m {model} -s workspace-write`（交互）；`codex exec -m {model} -s workspace-write -`（后台） | arg / stdin，依运行方式选择 | tab / background | L1；L2 需验证送达 | 交互时按实测使用 queue；退出后 restart | `codex exec -m {model} -s read-only --skip-git-repo-check` |
| 其他 CLI | 例如 `<cli> --model {model}` | arg/stdin | background | L1 | restart | 视工具而定 |

Codex 接入时从目标 worktree 验证可写范围包含本票的票文件和指定产物。若这些文件在树外，按当前 CLI 帮助和用户授权配置所需目录，再测回报是否到达。
