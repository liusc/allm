---
license: apache-2.0
base_model: Qwen/Qwen3.8-Flash-Next
base_model_relation: quantized
library_name: allm
pipeline_tag: text-generation
tags:
  - moe
  - expert-pruning
  - quantization
  - 1-bit
  - iq1_m
  - gsq
  - rco
  - code
  - local-inference
  - qwen3.8-flash-next
  - systemone
  - jev
---

<div align="center">

# Qwen3.8-Flash-Next · Allm（9~15GB 内存）

等了一个月没等到能在 64GB Macbook 上跑的 Qwen3.8-Flash-Next，自己动手用 Rust + Abot 搓了一个 Allm + 量化权重，实际内存占用 9~15GB 左右，不影响其他应用，体验还行，分享给大家。

Allm 原本是一个只想做成类 Jev 的决策模型引擎，支持 Qwen3.5 系列稠密模型和 Qwen3.8 27B、Qwen3.8 FlashNext，提供 `/v1/systemone` 接口。后来想权重加载都加载上了，不如一并把推理的能力也放开吧，于是 `/v1/chat/completions` 接口也上了哈。

**Qwen3.8-Flash-Next · Allm：原 128B 参数、512 专家里剪掉一半、以 1-bit 量化打包进一个 27.6 GiB 的运行时容器，配一个 6–8 MB 的单文件运行时 `allm`，在一台 32 GB 的机器上跑起来。没有复杂的 Python 运行环境，也不用编译，单文件 + 模型就能跑起来。**

[![ModelScope](https://img.shields.io/badge/ModelScope-Qwen%2FQwen3.8--Flash--Next--Allm-624aff)](https://modelscope.cn/models/liusc2abot/Qwen3.8-Flash-Next-Allm)
[![GitHub release](https://img.shields.io/badge/GitHub-liusc%2Fallm%20v0.1.1-181717)](https://github.com/liusc/allm/releases/tag/v0.1.1)
[![license](https://img.shields.io/badge/license-apache--2.0-19a34a)](#许可与引用)

</div>

> **English version:** [README.md](README.md)

---

## TL;DR

| 项 | 值 |
|---|---|
| 权重体积 | **27.59 GiB**（单个 `.allmpack` 容器） vs 基座 BF16 **354 GB** |
| 有效位宽 | **1.89 bits/参数**（剪枝 + 量化的合并效果，按原始参数摊薄） |
| 常驻内存 | `phys_footprint` 峰值 **9.2 – 12.5 GiB**；Metal 设备侧新分配仅 **6.25 GiB** |
| 加载 | 温热 **~2.9 s**，首次（冷页缓存）**~7.3 s** |
| 吞吐（M4 Max / Metal） | prefill **~215 tok/s**；decode **22 – 35 tok/s** |
| 运行时 | 单文件 `allm`（**cpu / metal** 两个构建，cuda 在下一批） |
| 端点 | `POST /v1/systemone`、`POST /v1/chat/completions` |
| 32 GB 机器能跑？ | **能**——设备侧真正新分配约 6.25 GiB，其余是文件页 |

全部实测数字、方法与纪律见 **[BENCHMARKS.md](BENCHMARKS.md)**。

---

## 亮点

- **硬件要求低**：一台 **32 GB** 的机器就够。Metal 设备侧真正新分配的只有 **6.25 GiB**，
  其余 23.4 GiB 是 **mmap 的文件页**（零拷贝），不占新增堆内存，跑起来不影响其他应用。
- **部署简单**：**单文件运行时 + 单文件权重**。没有 Python 环境、没有 CUDA/编译工具链，
  `chmod +x` 之后一条命令起服务；macOS（Metal / CPU）与 linux x86_64（CPU）都有现成二进制。
- **决策位接口，不是「生成再解析」**：`/v1/systemone` **一次前向**直接给出类型化答案——
  `noul`（是/否概率）、`choice`（选项分布 + confidence）、`score`（有序档位期望值），
  三个问题可以在**同一个请求**里并行问完，代码拿到就能分支，不需要解析自由文本。
- **公开基准上打得出成绩**：在 [jev-benchmarking](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking)
  的 37 个公开数据集上自测，**`imdb`、`financial_phrasebank`、`emotion` 三项超过参考模型
  Jev 的全量成绩**，`ag_news` 0.85 与 Jev 的 0.885 基本持平（详见「质量」）。
- **全本地、离线、零 API 费用**：权重和二进制都在本机，不联网也能用。

---

## 这是什么

这是 **Qwen3.8-Flash-Next** 的一个**能力定向压缩版**，并打包成 allm 的运行时容器：

- **剪枝**：每层 **512 个专家剪到 256 个**（48 层、每 token 激活 10 个）。剪掉的不是随机一半，
  而是用 **RCO**（Riemannian 约束优化）在标定数据上联合搜索出来的。
- **量化**：保留的权重用 **GSQ** 搜到 3.5 bpw；打包进 allm 容器时**不重编码**，字节原样搬运。
- **容器**：`.allmpack` 把每个张量对齐到 16384（零拷贝窗口基址），并把逐层 n-gram（PLE）表
  从 26.82 GiB 裁到 **23.6 MiB**——这一步省下的比专家还多。
- **运行时**：**allm**，一个单文件可执行程序，直接提供 `/v1/systemone` 与
  `/v1/chat/completions` 两个 HTTP 端点。allm 是 **abot** 项目的本地推理运行时。

> 剪枝、量化与容器三者**互补**：剪枝减少专家数量，量化降低每个保留权重的位宽，
> 容器只负责把这些字节以省内存、省启动的方式摆好。

---

## 快速开始

### 1. 下载

| 文件 | 大小 | 必需 |
|---|---:|---|
| `Qwen3.8-Flash-Next-Allm.allmpack` | 27.59 GiB | ✅ 权重（**唯一**权重依赖） |
| `tokenizer.json` | 8.7 MiB | ✅ 文本 ↔ id |
| `tokenizer_config.json` | 10.4 KiB | ✅ chat 模板 / eos |
| `allm-metal-aarch64-apple-darwin` | 7.6 MB | macOS 运行时 |
| `allm-cpu-aarch64-apple-darwin` | 6.4 MB | macOS（无 GPU 时） |
| `allm-cpu-x86_64-unknown-linux-gnu` | 9.0 MB | linux x86_64 运行时 |

**权重**在本 ModelScope 仓；**二进制**在
[GitHub `liusc/allm` v0.1.1](https://github.com/liusc/allm/releases/tag/v0.1.1)。
把三者放进**同一个目录**（容器与 tokenizer 必须同目录）：

```
Qwen3.8-Flash-Next-Allm/
├── Qwen3.8-Flash-Next-Allm.allmpack
├── tokenizer.json
├── tokenizer_config.json
└── allm-metal-aarch64-apple-darwin
```

### 2. 起服务

```bash
chmod +x allm-metal-aarch64-apple-darwin
./allm-metal-aarch64-apple-darwin serve \
  --model-dir ./Qwen3.8-Flash-Next-Allm \
  --port 18100 \
  --served-model-name Qwen3.8-Flash-Next-Allm
```

> 压缩档位与数值类型都有**按架构取的缺省**（`--quant auto` / `--dtype auto`）：本容器是
> 预量化档位，两者在它上面分别定成 `none` 与 `f32`，所以上面不用写。

> 如果是 Qwen3.8 27B 和其他稠密模型，可以指定动态量化，比如 `--quant q4k`、`--dtype bf16`。

### 3. 调用两个端点

```bash
./examples/systemone.sh http://127.0.0.1:18100          # 决策位接口
./examples/chat.sh http://127.0.0.1:18100               # OpenAI 兼容
./examples/chat.sh http://127.0.0.1:18100 --stream      # 流式
```

---

## 端点

| 端点 | 说明 |
|---|---|
| `POST /v1/systemone` | 一次前向的决策接口：`noul` / `choice` / `score`，可同请求并行多问 |
| `POST /v1/chat/completions` | OpenAI 兼容（流式 / 非流式 / tools / reasoning_content） |
| `GET /v1/models`、`GET /health`、`GET /health/live` | 模型列表与健康检查 |

`/v1/systemone` 请求与真实返回（节选）：

```json
{
  "model": "Qwen3.8-Flash-Next-Allm",
  "state": "订单 #7710 到货时箱子破损，里面的花瓶裂了。已送达 3 天。",
  "questions": {
    "refund_eligible": { "type": "noul", "instructions": "按店铺政策，客户有权全额退款。" },
    "responsible_department": {
      "type": "choice",
      "instructions": "该由哪个部门处理？",
      "criteria": {
        "billing": "重复扣款与支付错误",
        "logistics": "运输破损、丢件或延误",
        "product_support": "商品缺陷排查"
      }
    },
    "urgency": { "type": "score", "instructions": "这个工单有多紧急？", "criteria": ["常规", "紧急", "火急"] }
  }
}
```

```json
{
  "answers": {
    "responsible_department": { "type": "choice", "choice": "logistics",
      "probabilities": { "billing": 0.355, "logistics": 0.568, "product_support": 0.078 }, "confidence": 0.192 },
    "urgency": { "type": "score", "score": 1.139, "legend": { "0": "常规", "1": "紧急", "2": "火急" } },
    "refund_eligible": { "type": "noul", "noul": 0.552 }
  },
  "usage": { "input_tokens": 213, "output_tokens": 9 }
}
```

延迟（M4 Max）：冷 **437 ms**、热 **379 ms** 一次（`BENCHMARKS.md` §6.4）。

---

## 资源与性能

| 指标 | 值 | 说明 |
|---|---:|---|
| 容器体积 | 27.59 GiB | 单文件，1224 个张量 |
| `phys_footprint` 峰值 | 9.2 – 12.5 GiB | 随上下文增长，15 k 上下文也才 12.5 GiB |
| Metal 设备新分配 | 6.25 GiB | 非专家权重 + 激活 |
| 专家区 | 23.42 GiB | **文件映射（零拷贝）**，不是新拷贝的堆内存 |
| KV | ~48 KiB / token | 与上下文预算挂钩 |

M4 Max / Metal / 64 GiB：

| 上下文 | prefill | decode | 峰值内存 |
|---:|---:|---:|---:|
| 350 tok | 211 tok/s | 24.4 tok/s | 10.5 GiB |
| 4 275 tok | 217 tok/s | 32.1 tok/s | 11.8 GiB |
| 15 325 tok | 215 tok/s | 12.6 tok/s | 12.5 GiB |

> **怎么读「显存」**：跑完一次后 Metal 报告的 `currentAllocatedSize` 约 **29.87 GiB**，
> 其中 23.4 GiB 是零拷贝窗口——背后是 mmap 的文件页。判断「机器放不放得下」请用
> `phys_footprint` 与「设备侧新分配」。

---

## 质量：用 jev-benchmarking 自测

**用的什么标准**：我们选 [**jev-benchmarking**](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking)——
一个公开的多任务评测仓，**37 个数据集**（分类、NLI、阅读理解、常识推理、安全审核、打分），
接口与 [Jev](https://docs.typesafe.ai/introduction) 的**决策位接口同构**，且仓内自带多个参考模型的
**全量**成绩，可以直接对照。我们跑的是**本发布的两个文件本身**（Metal 产物 + `.allmpack` 容器），
一次前向一个请求、无采样。逐任务完整表见 [BENCHMARKS.md](BENCHMARKS.md) §6.6。

抽样轮（22 个任务 × 20 例，`eval` split，hash 抽样、子集嵌套可复现）：

| 任务 | 本发布 | 参考：Jev（全量） | 备注 |
|---|---:|---:|---|
| `imdb` 情感（2 选一） | **1.000** | 0.965 | ✅ 高于参考 |
| `financial_phrasebank` 金融情感（3 选一） | **0.850** | 0.730 | ✅ 高于参考 |
| `emotion` 情绪（6 选一） | **0.650** | 0.585 | ✅ 高于参考 |
| `ag_news` 新闻分类（4 选一） | 0.850 | 0.885 | 基本持平 |
| `sst2` 情感（2 选一） | 0.850 | 0.964 | |
| `rotten_tomatoes` 影评 | 0.750 | 0.933 | |
| `arc` 科学推理（4 选一） | 0.700 | 0.988 | |
| `boolq` 阅读理解（是/否） | 0.650 | 0.913 | |
| `hellaswag` / `commonsense_qa` 常识推理 | 0.500 | 0.955 / 0.882 | 见 Roadmap |
| `mmlu` 学科知识 / `banking77` 意图路由 / `agb_de` 德语新闻 | 0.35 / 0.05 / 0.00 | 0.92 / 0.80 / 0.20 | 见 Roadmap |

> 口径提醒：我们这批是**每任务 20 例**的抽样，参考列是仓内**全量**成绩，只作量级参照；
> 单任务 95% 置信区间约 ±0.15。**完整轮（每任务 300 例）与参考模型的同批样本对照随后补上**，
> 结论以那时为准。

**一键复跑**（需要 python 的 `datasets` + `scikit-learn`）：

```bash
resources/jev-benchmark/run_jev_benchmark.sh Qwen3.8-Flash-Next-Allm 300
```

### Roadmap（正在做 / 计划做）

| 方向 | 现状 | 计划 |
|---|---|---|
| **多选推理**（`mmlu` / `hellaswag` / `arc` / `commonsense_qa` / `winogrande`） | 0.35 – 0.70，低于参考 | 1-bit 档位下推理是主要短板；下一步做逐 head 阈值与**校准**（温度缩放），并补完整轮 |
| **大标签集路由**（`banking77` 77 类） | 0.05，但金标签平均排名 **15/77**（随机 39） | 信号存在、argmax 不稳 ⇒ 用阈值 + 候选重排序，而不是继续堆算力 |
| **多标签 / 长文档**（`go_emotions` / `toxic_chat` / `unfair_tos`） | 本轮未跑满 | per-label 阈值 + 完整轮补测 |
| **校准** | `confidence` 尚未可直接当门限 | 标定后重报 ECE，让 `confidence` 可用于「低于阈值就转人工」 |
| **CUDA 运行时** | 未验证 | 下一批发布 |
| **长上下文** | 15 k prefill ~71 s；128 k 为外推 | 稀疏注意力（QSA）路径优化 |
| **评测** | 每任务 20 例抽样 | 300 例/任务 + 参考模型跑同一批样本 + 污染探针 |

---

## 参与维护

这个项目是一边用一边长出来的，非常欢迎一起改：

- **跑一遍基准，把结果发回来**：`run_jev_benchmark.sh` 一条命令跑完 37 个数据集，
  结果表可以直接贴到 issue 里——你机器上的数字对我们最有价值。
- **报问题 / 提建议**：在 [GitHub `liusc/allm`](https://github.com/liusc/allm/issues) 开 issue，
  带上 `--version`、机器型号、内存与复现命令；崩了的话附上启动日志。
- **加任务集**：本仓 `resources/jev-benchmark/` 就是一个可照抄的例子（英文基准一键脚本），
  abot 源仓的 `systemone-zh` 是另一个（中文回归集）；照着加一个新任务集是很小的改动。
- **改运行时**：allm 是 Rust + Candle，单 crate，README 与 `BENCHMARKS.md` 里记着每条实测口径
  （内存、吞吐、纪律），方便你对着改。

---

## 文件清单与校验和

`SHA256SUMS` 覆盖包内三个二进制的校验和；把权重三件套放进同目录后重跑 `scripts/checksums.sh`，
即可把它们一并追加进去。校验：

```bash
shasum -a 256 -c SHA256SUMS
```

---

## 许可与引用

- 权重继承基座 **Qwen3.8-Flash-Next** 的许可：**Apache-2.0**。
- 剪枝方法 **RCO**：*Model Compression with Exact Budget Constraints via Riemannian Manifolds*
  （arXiv:2605.00649）。
- 量化方法 **GSQ**：*GSQ: Highly-Accurate Low-Precision Scalar Quantization for LLMs via
  Gumbel-Softmax Sampling*（arXiv:2604.18556）。
- 上游发布：`ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF`（Deep Algorithms and Systems Lab，
  IST Austria）。
- 评测标准：[`jev-benchmarking`](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking)
  （MIT）。
- **allm** 是 **abot** 项目的本地推理运行时。

---

<div align="center">
<sub>原权重来自 ISTA-DASLab 的 GSQ-RCO 压缩；运行时 <b>allm</b> 由 <b>abot</b> 项目开发。</sub>
</div>
