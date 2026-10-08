# BENCHMARKS — Qwen3.8-Flash-Next-Allm（IQ1_M 容器）

本文件是所有发布材料的**唯一数字来源**。README（中英各一份）只引用这里，不自行计算。
凡标注「**引用上游**」的数字不是本机实测；其余均为本机实测。

---

## 0. 机器与软件规格 / Machine and software

| 项 | 值 |
|---|---|
| 机器 | Apple **M4 Max**（`Mac16,5`），64 GiB 统一内存，16 核 |
| 系统 | macOS **26.5.1**（build 25F80） |
| Rust | `rustc 1.98.1 (48a229cea 2026-09-01)`（Homebrew） |
| 后端 | **Metal**（`/health.backend = "metal"`） |
| 运行时 | `allm v0.1.1`（本包发布的三个二进制，见 §7） |
| 权重 | `Qwen3.8-Flash-Next-Allm.allmpack`（IQ1_M + GSQ-RCO 256/512 专家） |

> **环境注记：** 测量期间同一台机器上还跑着 abot 托管的 **Qwen3.5-4B** 实例，它未参与本文
> 任何数字，但共享内存与页缓存；绝对延迟可能因此略高。测量是**串行**的（见 §1）。

---

## 1. 口径与纪律 / Caliber and discipline

1. **独占（单模型）**：同一时刻只跑一个吃内存的进程；起测前确认没有别的本模型进程。
2. **页缓存敏感**：decode 读数对页缓存极敏感（历史上同命令差过 10×）。两次数值差一个量级时，
   先怀疑换页（`vm_stat` 的 `Pageins` 差分），再怀疑代码。
3. **账本会拖慢**：`--timing` / `ALLM_QWEN4_TIMING=1` 会让一步 decode 明显变慢
   （历史记录 64.2 → 127.5 ms/token）。**基线一律关账本**；账本只用于看占比。
4. **`显存` 与 `峰值内存` 不是一回事**：`显存` 是 Metal `currentAllocatedSize`，包含
   23.4 GiB 的**零拷贝窗口**（背后是 mmap 的文件页，不是新拷贝的堆内存）；
   `峰值内存` 是进程的 `phys_footprint`。看「这台机器跑不跑得动」要看 `phys_footprint`
   与「设备侧新分配」，不能直接拿 29.87 GiB 去对 32 GB 机器。
5. **本机实测 vs 引用上游**：§6.5 的质量数字（SWE-bench / LiveCodeBench）**引用上游，不重跑**，
   与 §6.6 的本机自测**口径不同、不可互相换算**。

---

## 2. 体积 / Footprint

| 构成 | 字节 | 人类可读 |
|---|---:|---:|
| 本发布 `Qwen3.8-Flash-Next-Allm.allmpack` | 29 628 514 304 | **27.59 GiB** |
| `tokenizer.json` | 9 125 016 | 8.70 MiB |
| `tokenizer_config.json` | 10 635 | 10.4 KiB |
| **本发布合计** | **29 637 649 955** | **27.60 GiB** |
| 上游 GGUF（`-00001` + `-00002`） | 58 408 584 928 | 54.40 GiB |
| 基座 BF16（引用上游） | — | **354 GB** |

- 容器 = **上游 GGUF 的 50.7%**、**基座 BF16 的约 7.8%**。
- 容器结构：**1224 个张量 / section**，张量编码分布
  `BF16×484, F16×1, F32×292, IQ2_S×40, IQ3_S×20, IQ3_XXS×34, IQ4_NL×87, IQ4_XS×45, Q2_0×9, Q4K×47, Q5K×35, Q6K×129, Q8_0×1`。
- 容器相对源 GGUF 少掉的 26.8 GiB 几乎全是逐层 n-gram（PLE）表：转换期按
  `--rows-per-head 16384` 裁到 **23.6 MiB**（源表 26.82 GiB）。**权重本身不重编码。**
- **有效 1.89 bits/参数**（引用上游口径：按**基座原始** 176.9B 参数摊薄「剪枝 + 量化」的
  合并效果，不是任何单个权重的实际位宽）。
- **两个参数量别混用**：`176.9B` = 剪枝**前**的基座规模（只在「有效位宽」这个口径里出现）；
  `~128B` = 本发布剪枝后（512→256 专家）的规模，README 的卖点句用这个数。

---

## 3. 加载 / Load

| 场景 | 加载时间 | 说明 |
|---|---:|---|
| `allm serve` 首次启动（冷页缓存） | **7.33 s** | `/health.startup_seconds` |
| `examples/qwen4`，冷 | 4.63 s | 首次读容器 |
| `examples/qwen4`，温热 ×4 | 2.85 / 2.88 / 2.90 / 3.00 s | 页缓存热 |

冷加载偏慢的主因是 mmap 一个 27.6 GiB 文件并建立 1224 个 section 索引。

---

## 4. 内存 / Resident memory

`/health.memory`（服务进程加载完成后，`allm-metal`）：

| 字段 | 字节 | 人类可读 | 含义 |
|---|---:|---:|---|
| `weights_bytes` | 4 451 258 880 | 4.15 GiB | 非专家权重 |
| `experts_bytes` | 25 146 163 200 | 23.42 GiB | 专家区（**文件映射 / 零拷贝**） |
| `ple_bytes` | 23 592 960 | 23.6 MiB | 裁过的 n-gram 表 |
| `sampled_footprint_bytes` | 8 763 569 184 | **8.16 GiB** | 进程实际常驻（采样） |

Metal 设备侧（`examples/qwen4` 报告）：

| 指标 | 值 |
|---|---:|
| 加载后设备分配 | **6.25 GiB**（非专家权重 + 激活） |
| 运行后设备分配峰值 | **29.87 GiB**（其中 23.4 GiB 是零拷贝窗口，背后是文件页） |
| `recommendedMaxWorkingSetSize` | 51.84 GiB |
| `phys_footprint` 峰值 | **9.20 – 12.48 GiB**（随上下文长度） |

**结论（32 GB 机器能不能跑）**：设备侧**真正新分配**约 6.25 GiB，其余 23.4 GiB 是文件页
（前提是专家走零拷贝）。因此一台 32 GB 的统一内存机器放得下——`phys_footprint`
峰值在最长测到的 15 k 上下文下也只有 12.48 GiB。

---

## 5. 吞吐 / Throughput（Metal，M4 Max）

`examples/qwen4`，`--max-new 4`，中文长文提示词；prefill 为单次（不重复）。

| 上下文 tokens | prefill | decode | decode ms/token | 峰值 `phys_footprint` |
|---:|---:|---:|---:|---:|
| 6 | 22.2 tok/s | 35.1 tok/s | 28.5 | 9.86 GiB |
| 350 | 211.1 tok/s | 24.4 tok/s | 40.9 | 10.47 GiB |
| 1 375 | 217.1 tok/s | 22.1 tok/s | 45.3 | 11.57 GiB |
| 4 275 | 217.1 tok/s | 32.1 tok/s | 31.2 | 11.77 GiB |
| 15 325 | 215.2 tok/s | 12.6 tok/s | 79.5 | 12.48 GiB |

- 6-token 一行是**首次调用**（含 kernel 首次编译），故 prefill 低到 22 tok/s。
- 进入稳态后 prefill 稳定在 **215–217 tok/s**。
- decode 在 22–35 tok/s 间抖动（本机噪声），**15 k 上下文下掉到 12.6 tok/s**——长上下文路径
  是下一个优化目标（见 §9）。

### 5.1 CPU 对照（同一台 M4 Max，aarch64，仅 CPU 构建）

| 指标 | 值 |
|---|---:|
| 加载 | 2.80 s |
| prefill（6 token） | 16.739 s → **0.4 tok/s** |
| decode | **4310.2 ms/token**（0.23 tok/s） |
| 峰值 `phys_footprint` | 9.20 GiB |

CPU 慢两个数量级，仅作对照；**实际部署建议用 Metal**。

---

## 6. 端点 / Endpoints

### 6.1 TTFT（`/v1/chat/completions`，服务路径，单次请求）

用 shell 计时（本沙箱 `curl` 不支持 `-w` 的占位符），发出 `max_tokens: 1` 的请求：

| 提示词 tokens | 端到端耗时 | 折算 prefill |
|---:|---:|---:|
| 4 100 | **19 s** | ≈216 tok/s |
| 12 773 | **59 s** | ≈216 tok/s |

与 §5 的 prefill 速率一致——服务路径没有额外开销。

### 6.2 功能冒烟（全部 200）

- `GET /health/live` → `{"status":"ok"}`
- `GET /v1/models` → `Qwen3.8-Flash-Next-Allm`
- `GET /health` → `startup_seconds=7.33`，`backend=metal`，`maximum_sequence_length=262144`
- `POST /v1/systemone` → 三问（`noul` / `choice` / `score`）齐备
- `POST /v1/chat/completions`（非流式）→ 正确产出迭代版 Rust `sum`
- `POST /v1/chat/completions`（流式）→ 逐块 `data:` + `data: [DONE]`
- 前缀缓存 → 重复请求 `prompt_tokens_details.cached_tokens == prompt_tokens`

### 6.3 `POST /v1/systemone` 中文回归（`libs/lib-allm/resources/systemone-zh/`，abot 源仓）

**位置平衡集**（`cases/`，18 例，选项首位置轮换）：

| 集子 | 总准确率 | 首位命中率 |
|---|---:|---:|
| `systemone-zh` 位置平衡集 | **11/18 = 0.611** | 0.667 |

- 这 18 例的 `.expected` 由更大的模型产出，验收标准是「**不低于**同模型历史基线」，
  **不是 18/18**；该集子本身偏小，且天然偏向第一个选项。
- 未命中的例集中在语义上真正相邻的选项（如 `does_not_power_on` 与 `wrong_invoice_title`），
  详见 `libs/lib-allm/resources/systemone-zh/README.md`。
- 需要看多选项能力请用英文基准（§6.6）——18 例的集子信噪比不够。

> 设计说明：`choice` 不是读标签 logits，而是对候选**整段文本**打分（`common/continuation.rs`）；
> 候选列表会进请求前缀（`Options:` / `Levels:`），续写只回列表短码，所以选项键名
> （`option_a/b/c`）不参与打分。

### 6.4 `/v1/systemone` 延迟（`bench_systemone.sh`，20 次）

| 场景 | 单次耗时 |
|---|---:|
| 冷（6 个新 state） | **437 ms** |
| 热（20 次请求） | **379 ms** |
| 全量扫（18 个 case） | **429 ms** |

### 6.5 上游质量（**引用上游，不重跑**）

| 基准 | 基座 BF16（354 GB） | 上游 GSQ-RCO Coder（58.4 GB） | 保留 |
|---|---:|---:|---:|
| SWE-bench Verified | 82.80 | **75.60** | 91.3% |
| LiveCodeBench v6 | 87.43 | **86.28** | 98.7% |

- 来源：上游 model card（ISTA-DASLab Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF），
  **xhigh reasoning effort**。
- 本发布与上游是**同一份权重**，只是换了一个运行时容器（`.allmpack`）；上游数字对本发布
  成立的前提是「解码数值一致」，见 §9 末尾的数值一致性说明。

---

### 6.6 自测质量：jev-benchmarking 37 数据集（**本机自测**，抽样）

**标准**：全部质量数字取自公开评测仓
[`jev-benchmarking`](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking)——
**37 个数据集**（分类、NLI、阅读理解、常识推理、安全审核、打分），接口与
[Jev](https://docs.typesafe.ai/introduction) 的决策位接口同构，仓内自带多个参考模型的**全量**
成绩可直接对照。

**口径**：`eval` split，每任务按 `sha256(uid)` 排序取前 **20** 例（子集嵌套、可复现、无采样），
Metal 后端，一次前向一个请求（`POST /v1/systemone`）。跑的是**本发布的两个文件本身**：
`artifacts/allm-metal-aarch64-apple-darwin`（sha256 `b1f89e17…`）+
`Qwen3.8-Flash-Next-Allm.allmpack`（29 628 514 304 B）。每行的 metric 由 jev 定义
（accuracy / f1），跨行不可直接平均。本表由同日两批抽样合成（合计 22 个任务）。

**逐任务结果**（按本发布数值排序；随机列是该任务的多数类 / 随机基线）：

| 任务 | 题型 | 本发布（20 例） | 参考：Jev（全量） | 备注 |
|---|---|---:|---:|---|
| `imdb` 情感 | Choice 2 | **1.000** | 0.965 | ✅ 20/20，高于参考 |
| `ag_news` 新闻分类 | Choice 4 | **0.850** | 0.885 | 基本持平 |
| `financial_phrasebank` 金融情感 | Choice 3 | **0.850** | 0.730 | ✅ 高于参考 |
| `sst2` 情感 | Choice 2 | 0.850 | 0.964 | |
| `rotten_tomatoes` 影评 | Choice 2 | 0.750 | 0.933 | |
| `arc` 科学推理 | Choice 4–5 | 0.700 | 0.988 | |
| `boolq` 阅读理解 | Noul | 0.650 | 0.913 | |
| `emotion` 情绪 | Choice 6 | **0.650** | 0.585 | ✅ 高于参考 |
| `sms_spam`（F1） | Noul | 0.571 | 0.938 | 不平衡二分类 |
| `art` 论证类型 | Choice 2 | 0.550 | 0.839 | |
| `belebele` 多语阅读 | Noul | 0.500 | — | |
| `commonsense_qa` 常识 | Choice 5 | 0.500 | 0.882 | 见 §9 |
| `hellaswag` 常识续写 | Choice 4 | 0.500 | 0.955 | 见 §9 |
| `prompt_injections` 注入识别 | Noul | 0.500 | — | |
| `paws` 复述判定 | Noul | 0.450 | 0.850 | |
| `pubmedqa` 医学阅读 | Noul | 0.450 | — | |
| `toxigen` 毒性识别 | Noul | 0.450 | — | |
| `winogrande` 指代消解 | Choice 2 | 0.450 | 0.914 | |
| `anli` 自然语言推理 | Choice 3 | 0.400 | 0.739 | |
| `mmlu` 学科知识 | Choice 4 | 0.350 | 0.918 | 见 §9 |
| `banking77` 意图路由 | Choice 77 | 0.050 | 0.797 | 见 §9 |
| `agb_de` 德语新闻（F1） | Noul | 0.000 | 0.204 | 见 §9 |

- **22 任务均值 0.546**；分布上 14 个任务 ≥ 0.50、其中 8 个 ≥ 0.65。
- **`imdb` / `financial_phrasebank` / `emotion` 超过参考模型 Jev 的全量成绩**，`ag_news` 已很接近
  （0.850 vs 0.885）。
- **`confidence` 已一并落库**（jev 的 ECE 列）：本批 ECE 在 **0.10 – 0.58** 之间
  （`imdb` 0.100 最好、`sms_spam` 0.583 最差），目前还只能当趋势看，校准列入 §9。
- **噪声**：20 例下单任务 95% CI 宽达 **±0.15 – 0.22**。同日另一批同样本同配置的抽样里
  `boolq` 是 0.500、`sms_spam` F1 是 0.333——一两例之差，**不代表能力变化**。这也是 §9 要跑
  完整轮（300 例/任务）的原因。
- **参考列的口径**：上方参考列是仓内**全量**成绩，我们这批是同一批任务的 **20 例子集**，
  只作量级参照，**不可直接比大小**，更不可据此下「与 Jev / 27B 相当」的结论。
- **未跑满的任务**（8 个，各 5 例）：`bigbench` `ceval` `clinc150` `go_emotions` `language_id`
  `openai_moderation` `sib200` `toxic_chat`——多标签 / 多选项 / 长输入，单请求 5–120 s；
  5 例的差异全是噪声，不列入本表。
- `lytang/LLM-AggreFact`（`llm_aggrefact`）是 **gated** 数据集，需 HF token，跳过。
- **完整报告**：`allm-eval-report-2026-10-08.md`（jev-benchmarking 仓内，含逐任务 n、
  耗时；容器 1 579 次请求中位延迟 **1.05 s** / p95 10.22 s）。
- **复跑**：

```bash
libs/lib-allm/resources/jev-benchmark/run_jev_benchmark.sh Qwen3.8-Flash-Next-Allm 300
```

---

## 7. 二进制 / Shipped binaries

| 文件 | 目标三元组 | 后端 | 大小 |
|---|---|---|---:|
| `allm-metal-aarch64-apple-darwin` | `aarch64-apple-darwin` | Metal | 7 605 952 B |
| `allm-cpu-aarch64-apple-darwin` | `aarch64-apple-darwin` | CPU | 6 446 208 B |
| `allm-cpu-x86_64-unknown-linux-gnu` | `x86_64-unknown-linux-gnu` | CPU | 9 394 280 B |

`SHA256SUMS`（由 `scripts/checksums.sh` 生成）：

```
b1f89e17a6cfe9bd4160e76d21fc64fd1f11e55196dde8ebc65d04bfe6eb2f39  artifacts/allm-metal-aarch64-apple-darwin
369e337c43eb6ad9f8f42ec7e9b5e3cab3f3fac75a6afa1ce07a3a91466efb3d  artifacts/allm-cpu-aarch64-apple-darwin
6732ce5745708d2eb28d982b1285c0c9d3ebd0c86fd72ceb755ccddce23fb9ba  artifacts/allm-cpu-x86_64-unknown-linux-gnu
```

- macOS 两个二进制在本机实测（`--version` → `allm 0.1.1`）。
- linux x86_64 二进制在 x86_64 构建机上交叉构建并自检通过；**本轮不采集 linux 性能数字**（§9）。

---

## 8. 复现命令 / Reproduction

```bash
# 构建运行时（macOS；需在 abot 源仓内执行）
scripts/build-runtime.sh

# 起服务（档位与数值类型的缺省由架构定：本容器上分别是 none 与 f32，所以不用写）
./allm-metal-aarch64-apple-darwin \
  serve --model-dir <MODEL_DIR> --port 18300 \
  --served-model-name Qwen3.8-Flash-Next-Allm

# 加载 / 内存 / 吞吐（需在 abot 源仓内执行）
cargo run --release -p lib-allm --features metal --example qwen4 -- \
  <MODEL_DIR>/Qwen3.8-Flash-Next-Allm.allmpack --prompt '用一句话解释零拷贝。' --max-new 8 --device metal

# 端点
examples/systemone.sh http://127.0.0.1:18300
examples/chat.sh      http://127.0.0.1:18300
examples/chat.sh      http://127.0.0.1:18300 --stream

# 中文回归与延迟（需 abot 源仓内的 libs/lib-allm/resources/systemone-zh/）
bash .../systemone-zh/run.sh                   http://127.0.0.1:18300
bash .../systemone-zh/run_position_balanced.sh http://127.0.0.1:18300
bash .../systemone-zh/bench_systemone.sh       http://127.0.0.1:18300 20

# 【自测质量】jev-benchmarking 37 数据集抽样（需 python 的 datasets + scikit-learn；见
# resources/jev-benchmark/README.md，服务由脚本自己起在 18300 端口）
resources/jev-benchmark/run_jev_benchmark.sh Qwen3.8-Flash-Next-Allm 300
```

---

## 9. Roadmap（后续迭代）

| 方向 | 现状（实测） | 计划 |
|---|---|---|
| **多选推理** `arc` / `hellaswag` / `commonsense_qa` / `mmlu` / `winogrande` | 0.35 – 0.70，低于参考 0.88 – 0.99 | 逐 head 阈值 / 候选重排序；完整轮 + 参考模型跑同一批样本 |
| **大标签集路由** `banking77`（77 类） | 0.050，但金标签平均排名 **15/77**（随机 39） | 信号在、argmax 不稳 ⇒ 阈值 + 重排序，而不是继续堆算力 |
| **二值任务阈值** `boolq` / `paws` / `agb_de` | 同一批样例两批抽样差 0.15，固定 0.5 阈值偏保守 | 在 dev 上调阈值、只在 eval 上应用，把已有判别力兑换成准确率 |
| **校准** | ECE **0.10 – 0.58**，`confidence` 尚不可直接当门限 | 温度缩放 / Platt 标定后重报 ECE，让 `confidence` 可用于「低于阈值转人工」 |
| **多标签 / 长文档** `go_emotions` / `toxic_chat` / `unfair_tos` | 本轮未跑满（5 例） | per-label 阈值（dev 调）+ 完整轮补测 |
| **长上下文** | 15 k prefill ~71 s、decode 12.6 tok/s；128 k 为外推 | 稀疏注意力（QSA）路径优化 |
| **CUDA 运行时** | 未验证 | 第二批发布（`--features cuda` + 数字） |
| **评测规模** | 每任务 20 例，95% CI ±0.15 – 0.22 | 300 例/任务 + 参考模型同样本 + 污染探针 |

### 数值一致性说明

CPU 与 Metal 在**真实提示词**上给出逐位相同的生成 id（0.0 差异）；差异只出现在不同设备
内部量化矩阵乘的窄精度上（Metal 的量化 matmul 与 CPU 有 ~1e-5 的 `1-cosine`，逐层累计到
第 48 层约 0.972）。因此「与上游同权重、同质量」的推断在 **CPU 路径上严格成立**，
在 Metal 路径上是「ID 级一致、尾数有差」——引用上游质量数字时请带上这句限定。
