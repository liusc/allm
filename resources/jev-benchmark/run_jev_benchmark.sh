#!/usr/bin/env bash
# 用 jev-benchmarking 评测本仓的 allm 模型（GPU/Metal 版）。薄封装：只定位产物与模型目录，
# 真正的流程（prefetch → 起服务 → 跑 37 个任务 → 入库 → 评测 → 报告）在 JEV_DIR/scripts/run_allm.sh。
#
#   resources/jev-benchmark/run_jev_benchmark.sh <model-slug> [limit]
#
# 默认：
#   JEV_DIR   = <本仓同级>/dsh-allm/jev-benchmarking
#   ALLM_BIN  = <本仓>/release/Qwen3.8-Flash-Next-Allm/artifacts/allm-metal-aarch64-apple-darwin
#   MODEL_DIR = <本仓>/models/Qwen/<slug>          （可用 MODEL_DIR 覆盖）
#
# 结果落在 jev 仓：results/eval/open_models/<slug>/、docs/allm-eval-<slug>.md。
# 抽样口径：eval split，每任务按 sha256 排序取前 <limit> 例（默认 300），子集嵌套、可复现。
set -euo pipefail

SLUG="${1:?model slug，例如 Qwen3.8-Flash-Next-Allm 或 Qwen3.5-2B}"
LIMIT="${2:-300}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"            # dsh-abot 仓根
JEV_DIR="${JEV_DIR:-$(cd "$ROOT/../dsh-allm/jev-benchmarking" && pwd)}"
ALLM_BIN="${ALLM_BIN:-$ROOT/release/Qwen3.8-Flash-Next-Allm/artifacts/allm-metal-aarch64-apple-darwin}"
MODEL_DIR="${MODEL_DIR:-$ROOT/models/Qwen/$SLUG}"
PYTHON="${PYTHON:-python3}"                                            # 需要装过 datasets

[ -x "$ALLM_BIN" ] || { echo "找不到 GPU 产物：$ALLM_BIN" >&2; exit 1; }
[ -d "$MODEL_DIR" ] || { echo "找不到模型目录：$MODEL_DIR" >&2; exit 1; }
[ -d "$JEV_DIR" ] || { echo "找不到 jev-benchmarking：$JEV_DIR" >&2; exit 1; }
"$PYTHON" -c 'import datasets' 2>/dev/null || { echo "$PYTHON 里没有 datasets（pip install datasets）" >&2; exit 1; }

echo "模型 $SLUG  $MODEL_DIR"
echo "产物 $ALLM_BIN"
echo "评测 $JEV_DIR （limit=$LIMIT，端口 ${ALLM_PORT:-18300}）"

cd "$JEV_DIR"
export ALLM_BIN PYTHON                       # 传下去，run_allm.sh 会分别用作产物路径与解释器
exec "$JEV_DIR/scripts/run_allm.sh" "$SLUG" "$MODEL_DIR" "$LIMIT"
