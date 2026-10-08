# jev-benchmark：allm 的公开基准自测

用 [jev-benchmarking](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking)（本地路径 `<本仓同级>/dsh-allm/jev-benchmarking`）的 **37 个公开数据集**在 allm 自己的运行时（Metal GPU 版产物）上跑一遍，
产出可复现的质量数字。它服务的是**发布**：`release/Qwen3.8-Flash-Next-Allm/BENCHMARKS.md` 的
**§6.6 自测质量**就是这份评测的产物（§6.5 是引用上游，两者口径不同、不可互相比较）。

与 `resources/systemone-zh/`（中文小回归集）的分工：

| | `systemone-zh` | `jev-benchmark`（本目录） |
| --- | --- | --- |
| 语料 | 8 条手工样本 + 18 例位置平衡集（中文） | 37 个公开数据集，每任务抽样（默认 300 例，可改） |
| 目标 | 快：核对「还能不能正确产出结构化答案」 | 全面：给出跨任务的质量画像与档位代价 |
| 耗时 | 秒级 | 小时级（每小时 3–4 千请求；实测延迟中位数 1.05 s、p95 10.2 s） |
| 数字去向 | `BENCHMARKS.md` §6.3 | `BENCHMARKS.md` §6.6 |

两者互补，互不替代：`systemone-zh` 是发版前的冒烟闸，本目录是发布材料的数字来源。

## 一键跑

```bash
# 首发容器（IQ1_M）：37 任务 × 每任务 300 例
libs/lib-allm/resources/jev-benchmark/run_jev_benchmark.sh Qwen3.8-Flash-Next-Allm 300

# 对照组（同运行时的另一档位）
libs/lib-allm/resources/jev-benchmark/run_jev_benchmark.sh Qwen3.5-2B 300
```

脚本做五件事：prefetch 数据集 → 起 Metal 服务（默认端口 **18300**）→ 逐任务请求 → 入库/评测 → 出报告。
安全与纪律：

- **端口 18300**，刻意避开 18100（那是 abot 托管的实例，别抢也别复用）。
- 同一时刻只跑一个吃内存的模型；退出时 `trap` 杀掉自己起的服务。
- **可中断续跑**：已写过的请求自动跳过，重跑同一条命令即可接着跑。
- 前提：`python3` 装过 `datasets` 与 `scikit-learn`（`pip install datasets scikit-learn`）；
  HF 主站不通时脚本默认走 `hf-mirror.com`。
- 想把服务与客户端分开管（比如服务已经在跑）：设 `ALLM_URL=http://127.0.0.1:18300`，脚本就不再自己起服务。
- **多标签 / 多选项任务很贵**：每候选一次前向，`banking77`（77 类）约 10 s/请求、`go_emotions`
  （28 标签）约 12 s/请求。先拿小 `--limit` 试跑、把这类任务放最后。

参数与环境变量：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `<model-slug>` | — | 服务端 `--served-model-name`，也是结果目录名；请求体里的 `model` 必须与之一致 |
| `<limit>` | `300` | 每任务抽样例数（按 `sha256` 排序取前 N，子集嵌套：先用小 limit 试跑，数字对大 limit 仍成立） |
| `JEV_DIR` | `<本仓同级>/dsh-allm/jev-benchmarking` | jev 仓位置 |
| `ALLM_BIN` | `<本仓>/release/Qwen3.8-Flash-Next-Allm/artifacts/allm-metal-aarch64-apple-darwin` | 要评测的产物 |
| `MODEL_DIR` | `<本仓>/models/Qwen/<slug>` | 模型目录（容器或 safetensors 目录） |
| `ALLM_PORT` | `18300` | 服务端口 |
| `ALLM_URL` | 空 | 设了就**复用已启动的服务**、自己不起 |
| `ALLM_ARGS` | 空 | 额外 `serve` 参数，例如 `--quant q4k` |

## 结果在哪

2026-10-08 的**快速抽样轮**（23 任务 × 20 例 + 13 任务 × 5 例）已经跑过，数字在
`docs/allm-eval-report-2026-10-08.md`（jev 仓）与发布材料 `BENCHMARKS.md §6.6`；完整轮
（每任务 300 例）用同一条命令重跑即可，已写过的请求会自动跳过。

- 逐任务原始响应：`<JEV_DIR>/runs/allm/<slug>/*.jsonl`
- 响应库（评测读它）：`<JEV_DIR>/cache/responses.<slug>.db`
- 指标：`<JEV_DIR>/results/eval/open_models/<slug>/<task>.json`
- 报告：`<JEV_DIR>/docs/allm-eval-report-2026-10-08.md`（含耗时、延迟、跳过任务清单）

`allm-metal` 产物自带 Metal 后端；`/health` 里能看到 `backend` 与 `quantization.scheme`，
两者会记进报告，作为「这份数字是谁跑出来的」的证据链。

## 已知限制

1. **抽样，不是全量**：每任务 300 例，且与 jev 仓里 `results/eval/` 的**全量**评测
   （Jev / Qwen3.8-27B / gemma-4-E4B）不可直接比，报告里不并列。
2. **gated 数据集**：`lytang/LLM-AggreFact` 需要 HF token，会被跳过；跳过项在报告里逐条列出。
3. **CUDA 不在本轮**：只评测 Metal 产物（本机无 NVIDIA 设备）。
4. 结果依赖 `served-model-name` 与 `--model` 完全一致——名字进了响应库的主键，不一致不是报错而是白跑
   （`run_allm.py` 起跑前会用 `/v1/models` 预检并拒绝不一致的组合）。
