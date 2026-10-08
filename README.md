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

# Qwen3.8-Flash-Next · Allm (9–15 GB of memory)

I waited a month for a Qwen3.8-Flash-Next that would run on a 64 GB MacBook and gave up waiting:
I built **Allm** with Rust + Abot and did the quantization myself. It really does sit at around
9–15 GB of memory, it stays out of the way of everything else you are running, and it feels good
enough that I thought I would share it.

Allm started out as a decision-model engine in the spirit of Jev: Qwen3.5 dense models plus
Qwen3.8 27B and Qwen3.8 FlashNext, served through `/v1/systemone`. Once the weights were resident
anyway, it seemed silly not to open up plain inference as well — hence `/v1/chat/completions`.

**Qwen3.8-Flash-Next · Allm: 128B parameters, half of its 512 experts removed, quantized to 1 bit
and packed into a single 27.6 GiB runtime container — served by a 6–8 MB standalone binary on a
32 GB machine. No Python environment, no toolchain: one binary plus the weights and it runs.**

[![ModelScope](https://img.shields.io/badge/ModelScope-Qwen%2FQwen3.8--Flash--Next--Allm-624aff)](https://modelscope.cn/models/liusc2abot/Qwen3.8-Flash-Next-Allm)
[![GitHub release](https://img.shields.io/badge/GitHub-liusc%2Fallm%20v0.1.1-181717)](https://github.com/liusc/allm/releases/tag/v0.1.1)
[![license](https://img.shields.io/badge/license-apache--2.0-19a34a)](#license-and-citation)

</div>

> **中文版：** [README.zh.md](README.zh.md)

---

## TL;DR

| | |
|---|---|
| Weights on disk | **27.59 GiB** (one `.allmpack` container) vs **354 GB** for the BF16 base |
| Effective rate | **1.89 bits per parameter** (pruning + quantization, amortised over the original count) |
| Resident memory | peak `phys_footprint` **9.2 – 12.5 GiB**; only **6.25 GiB** newly allocated on the Metal device |
| Load | **~2.9 s** warm, **~7.3 s** cold (empty page cache) |
| Throughput (M4 Max / Metal) | prefill **~215 tok/s**; decode **22 – 35 tok/s** |
| Runtime | one `allm` binary (**cpu / metal** builds; cuda is next) |
| Endpoints | `POST /v1/systemone`, `POST /v1/chat/completions` |
| Fits a 32 GB machine? | **Yes** — ~6.25 GiB is genuinely new device allocation, the rest is file-backed |

Every measured number, method and caveat lives in **[BENCHMARKS.md](BENCHMARKS.md)**.

---

## Highlights

- **Modest hardware**: a **32 GB** machine is enough. Only **6.25 GiB** is newly allocated on the
  Metal device; the other 23.4 GiB is **mmap'd file pages** (zero-copy), not new heap, so the rest of
  your machine keeps working.
- **Trivial to deploy**: **one runtime binary + one weights file**. No Python environment, no CUDA or
  build toolchain — `chmod +x` and one command. Prebuilt binaries for macOS (Metal / CPU) and
  linux x86_64 (CPU).
- **A decision-bit API, not generate-then-parse**: `/v1/systemone` answers in **one forward pass** with
  typed answers — `noul` (yes/no probability), `choice` (distribution + confidence), `score`
  (expected value over ordered levels). Several questions can be asked in **the same request** and
  your code branches on the result directly, with no text to parse.
- **It holds its own on a public benchmark**: self-tested on the 37 datasets of
  [jev-benchmarking](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking), this release
  **beats the reference model Jev on `imdb`, `financial_phrasebank` and `emotion`**, and matches it on
  `ag_news` (0.85 vs 0.885) — see *Quality*.
- **Local, offline, no API bill**: weights and runtime stay on your machine.

---

## What this is

A **capability-targeted compression of Qwen3.8-Flash-Next**, packaged as an allm runtime container:

- **Pruning**: **512 experts per layer down to 256** (48 layers, 10 active per token). The removed
  half is not random — it is found with **RCO** (Riemannian constrained optimisation) over calibration
  data.
- **Quantization**: the surviving weights are searched to 3.5 bpw with **GSQ**; packing into the allm
  container **does not re-encode** them, the bytes move as they are.
- **Container**: `.allmpack` aligns every tensor to 16384 (the zero-copy window base) and trims the
  per-layer n-gram (PLE) table from 26.82 GiB to **23.6 MiB** — that saves more than the experts do.
- **Runtime**: **allm**, a single-file executable serving `/v1/systemone` and
  `/v1/chat/completions`. allm is the local inference runtime of the **abot** project.

> Pruning, quantization and the container are **complementary**: pruning removes experts, quantization
> lowers the bits per surviving weight, and the container only lays those bytes out to be cheap to map
> and cheap to start.

---

## Quick start

### 1. Download

| File | Size | Needed |
|---|---:|---|
| `Qwen3.8-Flash-Next-Allm.allmpack` | 27.59 GiB | ✅ the only weights dependency |
| `tokenizer.json` | 8.7 MiB | ✅ text ↔ ids |
| `tokenizer_config.json` | 10.4 KiB | ✅ chat template / eos |
| `allm-metal-aarch64-apple-darwin` | 7.6 MB | macOS runtime |
| `allm-cpu-aarch64-apple-darwin` | 6.4 MB | macOS, no GPU |
| `allm-cpu-x86_64-unknown-linux-gnu` | 9.0 MB | linux x86_64 runtime |

**Weights** live in this ModelScope repository; **binaries** are on
[GitHub `liusc/allm` v0.1.1](https://github.com/liusc/allm/releases/tag/v0.1.1).
Put everything in **one directory** (container and tokenizer must be siblings):

```
Qwen3.8-Flash-Next-Allm/
├── Qwen3.8-Flash-Next-Allm.allmpack
├── tokenizer.json
├── tokenizer_config.json
└── allm-metal-aarch64-apple-darwin
```

### 2. Serve

```bash
chmod +x allm-metal-aarch64-apple-darwin
./allm-metal-aarch64-apple-darwin serve \
  --model-dir ./Qwen3.8-Flash-Next-Allm \
  --port 18100 \
  --served-model-name Qwen3.8-Flash-Next-Allm
```

> Quantization and dtype have **architecture-aware defaults** (`--quant auto` / `--dtype auto`).
> This container is already pre-quantized, so they resolve to `none` and `f32` here — nothing to pass.

> For Qwen3.8 27B and other dense models, ask for load-time quantization instead, e.g.
> `--quant q4k --dtype bf16`.

### 3. Call the two endpoints

```bash
./examples/systemone.sh http://127.0.0.1:18100          # decision-bit API
./examples/chat.sh http://127.0.0.1:18100               # OpenAI-compatible
./examples/chat.sh http://127.0.0.1:18100 --stream      # streaming
```

---

## Endpoints

| Endpoint | What it does |
|---|---|
| `POST /v1/systemone` | One-forward-pass decisions: `noul` / `choice` / `score`, several per request |
| `POST /v1/chat/completions` | OpenAI-compatible (streaming / tools / `reasoning_content`) |
| `GET /v1/models`, `GET /health`, `GET /health/live` | Model list and health |

A `/v1/systemone` request and its real response (excerpt):

```json
{
  "model": "Qwen3.8-Flash-Next-Allm",
  "state": "Order #7710 arrived with the box crushed and the vase inside cracked. Delivered 3 days ago.",
  "questions": {
    "refund_eligible": { "type": "noul", "instructions": "Under the store policy the customer is entitled to a full refund." },
    "responsible_department": {
      "type": "choice",
      "instructions": "Which team should handle this?",
      "criteria": {
        "billing": "Duplicate charges and payment errors",
        "logistics": "Damage, loss or delay in transit",
        "product_support": "Diagnosing a faulty product"
      }
    },
    "urgency": { "type": "score", "instructions": "How urgent is this ticket?", "criteria": ["Routine", "Urgent", "Critical"] }
  }
}
```

```json
{
  "answers": {
    "responsible_department": { "type": "choice", "choice": "logistics",
      "probabilities": { "billing": 0.355, "logistics": 0.568, "product_support": 0.078 }, "confidence": 0.192 },
    "urgency": { "type": "score", "score": 1.139, "legend": { "0": "Routine", "1": "Urgent", "2": "Critical" } },
    "refund_eligible": { "type": "noul", "noul": 0.552 }
  },
  "usage": { "input_tokens": 213, "output_tokens": 9 }
}
```

Latency (M4 Max): **437 ms** cold, **379 ms** warm per request (`BENCHMARKS.md` §6.4).

---

## Footprint and throughput

| Metric | Value | Note |
|---|---:|---|
| Container | 27.59 GiB | one file, 1224 tensors |
| Peak `phys_footprint` | 9.2 – 12.5 GiB | grows with context; a 15 k context still fits in 12.5 GiB |
| New Metal allocation | 6.25 GiB | non-expert weights + activations |
| Expert region | 23.42 GiB | **file-backed (zero-copy)**, not new heap |
| KV | ~48 KiB / token | tied to the context budget |

M4 Max / Metal / 64 GiB:

| Context | prefill | decode | peak memory |
|---:|---:|---:|---:|
| 350 tok | 211 tok/s | 24.4 tok/s | 10.5 GiB |
| 4 275 tok | 217 tok/s | 32.1 tok/s | 11.8 GiB |
| 15 325 tok | 215 tok/s | 12.6 tok/s | 12.5 GiB |

> **How to read "GPU memory"**: after a request Metal reports `currentAllocatedSize` of about
> **29.87 GiB**, of which 23.4 GiB is the zero-copy window — file pages behind an mmap. To judge
> whether a machine fits, use `phys_footprint` and the new device allocation.

---

## Quality: self-tested with jev-benchmarking

**The yardstick**: we picked
[**jev-benchmarking**](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking) — a public
multi-task evaluation suite with **37 datasets** (classification, NLI, reading comprehension,
commonsense, safety moderation, rubric scoring) whose interface is **structurally identical to Jev's
decision-bit API**, and which ships **full-scale** results for several reference models to compare
against. We run **the two shipped files themselves** (the Metal binary plus the `.allmpack`
container), one forward pass per request, no sampling. The full per-task table is in
[BENCHMARKS.md](BENCHMARKS.md) §6.6.

Sampled round (22 tasks × 20 examples, `eval` split, hash-ordered and reproducible):

| Task | This release | Reference: Jev (full-scale) | Note |
|---|---:|---:|---|
| `imdb` sentiment (2-way) | **1.000** | 0.965 | ✅ above the reference |
| `financial_phrasebank` (3-way) | **0.850** | 0.730 | ✅ above the reference |
| `emotion` (6-way) | **0.650** | 0.585 | ✅ above the reference |
| `ag_news` topic (4-way) | 0.850 | 0.885 | on par |
| `sst2` sentiment (2-way) | 0.850 | 0.964 | |
| `rotten_tomatoes` | 0.750 | 0.933 | |
| `arc` science (4-way) | 0.700 | 0.988 | |
| `boolq` reading (yes/no) | 0.650 | 0.913 | |
| `hellaswag` / `commonsense_qa` commonsense | 0.500 | 0.955 / 0.882 | see Roadmap |
| `mmlu` / `banking77` / `agb_de` | 0.35 / 0.05 / 0.00 | 0.92 / 0.80 / 0.20 | see Roadmap |

> Caveat: our column is a **20-example sample per task** while the reference column is the suite's
> **full-scale** score, so this is an order-of-magnitude comparison only; a single task carries a 95%
> interval of roughly ±0.15. **The full round (300 examples per task) plus same-sample runs of the
> reference models are coming**, and the conclusions will be restated then.

**One-command reproduction** (needs `datasets` + `scikit-learn` in python):

```bash
resources/jev-benchmark/run_jev_benchmark.sh Qwen3.8-Flash-Next-Allm 300
```

### Roadmap

| Area | Today | Plan |
|---|---|---|
| **Multi-choice reasoning** (`mmlu` / `hellaswag` / `arc` / `commonsense_qa` / `winogrande`) | 0.35 – 0.70, below the reference | reasoning at 1 bit is the main gap; next up are per-head thresholds and **calibration** (temperature scaling), plus the full round |
| **Large label routing** (`banking77`, 77 classes) | 0.05 accuracy, but the gold label ranks **15/77** on average (chance 39) | the signal is there, the argmax is not ⇒ thresholds + candidate re-ranking rather than more compute |
| **Multi-label / long documents** (`go_emotions` / `toxic_chat` / `unfair_tos`) | not fully run this round | per-label thresholds + a complete round |
| **Calibration** | `confidence` is not yet usable as a gate | report ECE after calibration so `confidence` can drive "route to a human below this" |
| **CUDA runtime** | unverified | next release batch |
| **Long context** | 15 k prefill ~71 s; 128 k extrapolated | optimize the sparse (QSA) path |
| **Evaluation** | 20 examples per task | 300 per task + reference models on the same sample + contamination probes |

---

## Contributing

This project grows while it is being used, and help is very welcome:

- **Run the benchmark and send us the numbers**: `run_jev_benchmark.sh` covers all 37 datasets in one
  command; paste the table into an issue — results from your machine are the most useful thing you can
  contribute.
- **Report problems / propose changes**: open an issue on
  [GitHub `liusc/allm`](https://github.com/liusc/allm/issues) with `--version`, your machine and
  memory, and the exact command. Attach the server log if it crashed.
- **Add a task set**: `resources/jev-benchmark/` in this repo is a ready template (one-command
  English benchmark); the abot source repo carries another one (`systemone-zh`, Chinese regression
  set) — adding a new one is a small change.
- **Change the runtime**: allm is Rust + Candle in a single crate, and every measurement's caliber
  (memory, throughput, discipline) is written down in `BENCHMARKS.md` so you can work against it.

---

## Files and checksums

`SHA256SUMS` holds the checksums of the three shipped binaries; drop the three weight files next to
them and re-run `scripts/checksums.sh` to append theirs. To verify:

```bash
shasum -a 256 -c SHA256SUMS
```

---

## License and citation

- Weights keep the license of the base model **Qwen3.8-Flash-Next**: **Apache-2.0**.
- Pruning method **RCO**: *Model Compression with Exact Budget Constraints via Riemannian Manifolds*
  (arXiv:2605.00649).
- Quantization method **GSQ**: *GSQ: Highly-Accurate Low-Precision Scalar Quantization for LLMs via
  Gumbel-Softmax Sampling* (arXiv:2604.18556).
- Upstream release: `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF` (Deep Algorithms and Systems
  Lab, IST Austria).
- Evaluation suite: [`jev-benchmarking`](https://github.com/AppliedMachineLearning-Lab/jev-benchmarking)
  (MIT).
- **allm** is the local inference runtime of the **abot** project.

---

<div align="center">
<sub>Base weights are the GSQ-RCO compression from ISTA-DASLab; the <b>allm</b> runtime is developed by the <b>abot</b> project.</sub>
</div>
