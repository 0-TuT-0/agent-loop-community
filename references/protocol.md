# 票文件协议

总控和 worker 之间唯一可靠的通道是票文件：每张票一个 markdown 文件，放在参数文件指定的票目录里。worker 不论跑在哪个引擎上，都只通过两种方式和总控通信：改票头的运行字段，以及在 `## Comments` 末尾追加块。

## 票头

票标题下面是一组 `字段: 值` 行，每个字段只出现一次。加粗写法 `**字段:** 值` 同样能识别。

```markdown
# <ID> <票名>

Status: ready-for-agent
Run: idle
Deliverable: commit
Risk: low
Depends: 01, 03
External-X1: pending blocks=dispatch 等待用户确认示例测试夹具已准备
Touches: <本票会改的目录或文件，用逗号分隔>
Plan:
Role:
Run-id:
Engine:
Model:
Branch:
Worktree:
Worker:
Started:
Deadline:
Accepted:

## 目标
## 验收标准
## 测试
## Comments
```

### 两个状态字段

- **`Status`（分诊状态）**：归项目的任务跟踪约定，例如 `ready-for-agent`、`needs-triage`、`ready-for-human`。总控只读这个字段，不改。参数文件列出「可派工的分诊状态」，只有处在这些状态的票才进入循环。没有 `Status` 字段的票，视为可派工。
- **`Run`（运行状态）**：归本协议，取值和转换见下面的状态转换表。旧票没有 `Run` 字段时视为 `idle`。旧版协议把运行状态写在 `Status` 里，取值是 `claimed`、`done`、`merged` 等；接入时，总控按「旧票映射」一节把它们转到 `Run`。

### 字段说明

| 字段 | 谁写 | 含义 |
| --- | --- | --- |
| `Kind` | 拆票时写 | 只有发布票写 `release`。发布票会被同一票目录里任何一张票上、`pending` 且 `blocks=release` 的外部前置阻塞（发布关口） |
| `Deliverable` | 拆票时写 | 最终交付类型：`commit`（代码提交）、`artifact`（约定产物，比如报告、基准文件，没有提交）、`approved-plan`（只交审定计划） |
| `Risk` | 拆票后由总控写 | `high`、`medium` 或 `low`，用于路由 |
| `Depends` | 拆票时写 | 依赖的票 ID，用逗号分隔，必须精确对应票目录里存在的票；没有依赖写「无」。旧票里的 `Blocked by` 按同样规则解析 |
| `External-<ID>` | 拆票时或总控写 | 外部前置，一条占一行：`pending` 或 `met`，`blocks=` 后写被阻塞的动作（`dispatch` 派工、`accept` 验收、`release` 发布），后面跟说明。同一个外部前置被多张票引用时，用同一个 ID |
| `Touches` | 拆票时写 | 本票的改动范围，必须和公共文件归属表一致 |
| `Plan` | 拆票时写 `required`；你审定后由总控改成 `<计划路径>@<sha256 前 12 位>` | 只有高风险票有这个字段 |
| `Role` | 总控派工时写 | 本次运行的角色，见 `worker-contract.md`：`implement`、`plan`、`report`、`release`、`test` |
| `Run-id` | 总控派工时写 | `<ID>-r<序号>`，每派一次工序号加一；同一张票的每次运行都有唯一编号 |
| `Engine`、`Model` | 总控派工时写 | 引擎适配表里的名称，以及具体模型 |
| `Branch`、`Worktree` | 总控派工时写 | 票分支名，以及 worktree 的绝对路径 |
| `Worker` | 总控派工时写 | pid 文件路径，放在运行目录 `<运行目录>/<Run-id>/worker.pid`；有引擎会话 ID 时一并写上 |
| `Started`、`Deadline` | 总控派工时写 | ISO 时间，例如 `2000-01-01T09:30` |
| `Accepted` | 总控验收时写 | 验收证据：`commit` 写集成后的 SHA，`artifact` 写产物路径加 sha256 前 12 位，`approved-plan` 写计划路径加 sha256 前 12 位 |

## 状态转换表

后面的「谁改」「暂停范围」「自动重试」都以这张表为准。表格之外的情况，暂停本票并交给你。

| # | 从 | 事件 | 到 | 谁改 | 总控的动作 | 暂停范围 |
| --- | --- | --- | --- | --- | --- | --- |
| T1 | `idle` | 依赖都已 `accepted`，且没有阻塞派工的外部前置 | `dispatched` | 总控 | 写派工字段，新 `Run-id`；启动 worker | — |
| T2 | `dispatched` | worker 开工 | `claimed`（`plan` 角色进入 `planning`） | worker | — | — |
| T3 | `claimed` / `planning` | 需要裁决 | `needs-decision` | worker | 按「裁决」处理 | 本票，以及依赖本票的票 |
| T4 | `needs-decision` | 裁决已写好、已送出 | `needs-decision`（裁决块注明「已送出」） | 总控 | 送回 worker（`engines.md`「送回」） | 同上 |
| T5 | `needs-decision` | worker 读到裁决 | `claimed`，并写 `Ack: 裁决 <n>` | worker | — | — |
| T6 | `planning` | 你审定计划，计划文件写好 | `plan-review` | worker | 核对计划文件和版本，改写 `Plan`；若 `Deliverable` 是 `approved-plan`，转 T9，否则回到 `idle` 等开发派工 | — |
| T7 | `claimed` | 交付完成 | `done` | worker | 按 `verification.md` 验收 | — |
| T8 | `done` | 验收不通过 | `claimed`（返工） | 总控 | 写 `### 核对`，送回 worker | 本票 |
| T9 | `done` / `plan-review` | 验收通过 | `accepted` | 总控 | 写 `Accepted` 证据；`commit` 型先集成，再写集成后的 SHA | — |
| T10 | 任何非终态 | worker 进程退出，但不是 `done` 或 `plan-review` | `idle` | 总控 | 先看现场（`recovery.md`「异常」）；同一张票第一次异常，自动重派一次，从已有提交和 Comments 继续 | 本票 |
| T11 | `claimed` / `planning` | 超过 `Deadline` | 不变 | 总控 | 查看进度：延长期限并记录，或者按 T10 处理 | — |
| T12 | 任何非终态 | 同一张票第二次异常；或者返工后再次验收不通过 | `paused` | 总控 | 交给你决定：升级重派、拆票、放弃 | 本票，以及依赖本票的票 |
| T13 | `paused` | 你决定升级或重派 | `idle` | 总控 | 按 `routing.md`「升级」换路由，在 Comments 写原因 | — |
| T14 | 任何非终态 | 你决定放弃 | `abandoned` | 总控 | 依赖本票的票一并交给你处理 | 依赖本票的票 |
| T15 | 任何状态 | 你撤销或收紧了一项授权，且影响本票 | 冻结（不改 `Run`，Comments 写 `### 冻结`） | 总控 | 停止受影响的后续动作；worker 仍持有旧权限时，等它停止或完成交接，见 `worker-contract.md`「生效规则」 | 受影响的动作 |

- 终态：`accepted`、`abandoned`。
- 只有被列出的票会暂停。等你答复时，其他独立的票继续循环。
- **全局冻结**只用于一种情况：疑似权限配置错误，可能影响所有在途 worker，比如沙箱参数错了。这时停止全部派工，交给你决定。

## 旧票映射

| 旧版 `Status` 的值 | 映射到 |
| --- | --- |
| `ready`、`ready-for-agent` | `Run: idle`，`Status` 保持原样或者改成项目的可派工值 |
| `claimed`、`planning`、`needs-decision`、`plan-review`、`done` | 同名的 `Run` 值；`Status` 改成项目的可派工值 |
| `merged` | `Run: accepted`，`Accepted` 写当时合入的 SHA |
| `abandoned` | `Run: abandoned` |

映射前，先把整张票原样备份到运行目录；映射后在 Comments 写一个 `### 迁移` 块。

## Comments 中的块

所有人都只往 `## Comments` 末尾追加块，不改已有的块。每个块用三级标题开头，标题里带上 `Run-id`。

**待裁决**（worker 写，`<n>` 在本票内递增）
```markdown
### 待裁决 <n>（<Run-id>，<引擎>，<YYYY-MM-DD HH:mm>）
- 问题：
- 可选方案：
- 推荐方案及理由：
- 影响的文件或票：
- 已完成的部分：<提交 SHA，或者「未提交」>
```

**裁决**（总控写）
```markdown
### 裁决 <n>（总控 代次 <g>，<YYYY-MM-DD HH:mm>）
- 结论：
- 依据：<总控职责内 / 用户决定（原话要点、时间）>
- 对其他票的影响：
- 送出：<message / queue / restart，时间；未送出写「待送」>
```

**完成回报**（worker 写；不同角色的必填项见 `worker-contract.md`）
```markdown
### 完成回报（<Run-id>，<引擎>，<YYYY-MM-DD HH:mm>）
- 交付：<commit：分支和 HEAD SHA；artifact：产物路径和 sha256 前 12 位；approved-plan：计划路径和 sha256 前 12 位>
- 改动文件：
- 测试：<命令；被测 SHA；结果；与基准的逐条比对结论>
- 跨边界样例来源：<没有写「无」>
- 需要用户执行的脚本或操作：<没有写「无」>
- 与票、spec 或计划的偏差：
- 未解决的待明确事项：
- 下一张票需要知道的前提：
```

**咨询**（worker 直接调用其他引擎做只读咨询后写，见 `engines.md`「直接调用」）
```markdown
### 咨询（<Run-id>，<被调用的引擎/模型>，<时间>）
- 问了什么：
- 结论摘要：
- 采纳情况：
```

**核对**、**异常**、**冻结**、**迁移**（总控写）：写明检查了什么、结果如何、接下来怎么处理。

## 报告类产物的完成标记

`report` 角色交付的文件（审计报告、测试流程、基准文件等），以**最后一个非空行**作为完成标记，格式固定：

```
LOOP-DONE <Run-id>
```

正文里出现「审计完成」之类的文字不算完成；上一次运行留下的标记，因为 `Run-id` 对不上，也不算完成。

## 裁决

worker 提请裁决的情形：归属冲突；spec 或票有缺口；内容互相矛盾；需要改接口契约或数据模型；改动超出 `Touches`。

总控被唤醒后：
1. **判断归属**：
   - **总控职责内**：文件归属、票之间的分工、按已审定的 spec 和计划就能确定的事项。
   - **属于用户**：业务取舍、改 spec、改接口契约、改数据模型、改验收标准，以及任何不可撤销的外部操作。属于用户的，问你，然后照常挂上监视，其他票继续跑。
2. **写裁决**（T4）：裁决影响其他票时，在那些票的 Comments 里也写上。
3. **送回 worker**：按 `engines.md`「送回」执行，并在裁决块的「送出」一项里注明方式和时间。worker 把票头改回 `claimed`、写上 `Ack: 裁决 <n>`，才算读到了（T5）。只把消息放进队列，不算 worker 已读。
