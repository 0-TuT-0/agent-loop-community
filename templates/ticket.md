# 票模板

拆票时按模板写票头。用项目已有的工具生成票时，逐张补齐以下内容。
- 加上 `Run`、`Deliverable`、`Touches`；
- 把依赖改写成精确 ID，写进 `Depends`；
- 原来的依赖说明移到「依赖说明」一节。

总控核对每张票的 `loop-state.sh` 输出，`reason` 里没有 `unknown-dep` 之后，才进入循环。

```markdown
# <ID> <票名>

Status: ready-for-agent
Run: idle
Deliverable: commit
Risk:
Depends: <ID>, <ID>
Touches: <本票会改的目录或文件，逗号分隔>

## 目标

## 验收标准
- [ ] …

## 测试
<定向测试命令和要新增的用例>

## 依赖说明
<为什么依赖这些票、要用到它们的什么（接口、夹具、配置）；外部前置的说明>

## Comments
```

## 填写规则

- `ID`：用票文件名去掉 `.md` 后的部分，或者它开头的编号（例如 `03`）。`Depends` 里只能写票目录中存在的 ID，用逗号分隔；没有依赖就写 `无`。说明文字一律写进「依赖说明」，不写在 `Depends` 行里。
- `Deliverable`：交付代码的写 `commit`；交付报告、基准文件的写 `artifact`；只交审定计划的写 `approved-plan`。
- `Touches`：必须和拆票时约定的公共文件归属表一致。
- 外部前置（例如等用户执行脚本、等人工审批）单独写一行 `External-<ID>: pending blocks=<dispatch|accept|release> <说明>`。
- 发布票另加一行 `Kind: release`。
- `Risk`、`Plan` 由总控在拆票后填写。派工字段（`Role`、`Run-id` 等）由总控在派工时用 `loopctl` 写入，拆票时不要写。
