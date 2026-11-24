# 本机配置（agent-loop）

<!-- 由 `scripts/bootstrap.sh machine` 生成在 $AGENT_LOOP_HOME/machine.md（默认 ~/.agent-loop/machine.md）。
     记录这台电脑的属性，所有项目共用。项目参数只写与这里不同的地方。只填实测结果。 -->

## 基本

- 生成时间：
- 运行目录根位置：`~/.agent-loop/runs`（每个功能一个子目录 `<项目>/<功能>`，都在仓库之外）
- 依赖检查：git <版本>；bash <版本>；perl <有/无>；osascript <有/无>；iTerm2 <有/无>

## 宿主能力（总控所在的工具）

每个实际使用的宿主单独填一行。首次使用或升级时，按 `references/bootstrap.md` 验证后台完成通知能回到该会话。

| 宿主及版本 | 唤醒（auto / manual） | 交互开窗（tab / 无） | 后台运行 | 实测日期和方法 |
| --- | --- | --- | --- | --- |
| | | | | |

## 引擎适配表

| 名称 | 版本 | 启动命令模板 | 提示 | 运行 | 等级 | 送回 | 会话 ID 查找 | 权限参数 | 可用模型 / 推理强度 | 咨询命令 | 实测记录 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |  |  |  |

启动命令模板可以用的占位符：
- `{model}`：模型；
- `{effort}`：推理强度，没有就把对应参数整个去掉；
- `{prompt_file}`：只在 `file` 方式下使用。

总控先按路由表替换完所有占位符，再交给 `launch.sh`。还留着没替换的占位符时，`launch.sh` 会拒绝启动。

后台模式示例（stdin）：`codex exec -m {model} -c model_reasoning_effort="{effort}" -s workspace-write -`。按本票的写入范围配置 worktree、票和产物位置。

## 插件与外部 skill

- 按宿主列出本次启用的讨论、spec 和拆票 skill，以及实际调用方式。

## 权限放行建议（用户同意后写入 Claude Code 设置）

- `Bash(<skill 目录>/scripts/loopctl:*)`、`Bash(<skill 目录>/scripts/watch.sh:*)`、`Bash(<skill 目录>/scripts/loop-state.sh:*)`
