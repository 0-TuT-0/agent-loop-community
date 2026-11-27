#!/bin/bash
# 安装：让终端认识 agent-loop 命令，并让 Codex 看到这个 skill。重复运行无害。
set -uo pipefail
SKILL_DIR=$(cd -P "$(dirname "$0")/.." && pwd -P) || exit 1

link() {  # 目标 链接位置 说明
  mkdir -p "$(dirname "$2")" || exit 1
  if [ "$2" -ef "$1" ]; then echo "已就位：$3（$2）"; return 0; fi
  if [ -e "$2" ] || [ -L "$2" ]; then echo "$2 已存在并指向别处，请核对后手动处理。" >&2; return 1; fi
  ln -s "$1" "$2" && echo "已链接：$3（$2 → $1）"
}

chmod +x "${SKILL_DIR}"/scripts/agent-loop "${SKILL_DIR}"/scripts/*.sh
link "${SKILL_DIR}/scripts/agent-loop" "${HOME}/.local/bin/agent-loop" "终端命令 agent-loop"
link "${SKILL_DIR}" "${HOME}/.agents/skills/agent-loop" "Codex 的 skill 入口"
case ":${PATH}:" in *":${HOME}/.local/bin:"*) ;; *) echo "注意：${HOME}/.local/bin 不在 PATH 里，请把它加进 shell 配置。" ;; esac
