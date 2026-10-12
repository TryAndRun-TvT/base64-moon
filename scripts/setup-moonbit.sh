#!/usr/bin/env bash
# 安装 MoonBit 工具链并校验可用性（云原生开发环境初始化用；.cnb.yml 的 vscode 阶段调用）。
#
# 用法: bash scripts/setup-moonbit.sh
#
# 【版本可复现性】
#   官方 CLI 服务**只提供 `latest` / `nightly` 两个通道**——按具体版本号下载会 404。
#   因此**无法**用环境变量钉死具体版本。本脚本据此采用：
#   「装通道（默认 `latest`）+ **装后断言实际版本 == 期望版本**」，
#   把「静默漂移」变成「显式提示 / 可选失败」：
#     - 期望版本 = `MOON_EXPECTED_VERSION`（默认见下），**升级时刻意更新它**；
#     - 断言失败**默认仅告警**；需要强复现的场合设 `MOON_STRICT_VERSION=1` ⇒ 版本不符即非零退出；
#     - dev 通道：设 `MOONBIT_INSTALL_DEV=1`（官方安装脚本自身支持）。
set -euo pipefail

echo "Setting up MoonBit toolchain in cloud dev environment..."
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version

# 版本变更记录（升位时在此追加一行；口径见 docs/03-过程/moonbit-版本适配记录.md）：
#   0.1.20260920 → 0.1.20261012（Issue #29）：新 fmt 把 `Int` 归一为 `Int32`、命名参数声明
#   `x?` 归一为 `x~`（`.mbti` 接口快照逐字节不变 ⇒ 零 API 影响）；新增 `--warn-list +a`
#   可暴露且**默认关闭**的告警（unnecessary_view_op / missing_invariant / missing_reasoning 等）。
MOON_EXPECTED_VERSION="${MOON_EXPECTED_VERSION:-0.1.20261012}"
actual="$(moon version | head -1 | awk '{print $2}')"

if [[ "$actual" == "$MOON_EXPECTED_VERSION" ]]; then
  echo ">>> ✅ 工具链版本与期望一致：moon $actual"
else
  echo ">>> ⚠️ 工具链版本漂移：实际 moon $actual ≠ 期望 $MOON_EXPECTED_VERSION" >&2
  echo "    处置：先跑 bash scripts/toolchain-probe.sh 查看新增/潜伏告警（--warn-list +a），" >&2
  echo "          再决定是否更新 MOON_EXPECTED_VERSION（本仓未钉版）。" >&2
  if [[ "${MOON_STRICT_VERSION:-0}" == "1" ]]; then
    echo ">>> MOON_STRICT_VERSION=1 ⇒ 版本漂移视为失败。" >&2
    exit 1
  fi
fi
