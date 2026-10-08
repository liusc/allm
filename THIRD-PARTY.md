# THIRD-PARTY — 出处、归属与引用

本发布由三部分拼成：**权重的压缩方法**（上游）、**权重本身**（基座）、**运行时**（abot/allm）。
下面逐项说明出处、许可与引用。

---

## 1. 基座模型

| 项 | 值 |
|---|---|
| 模型 | `Qwen/Qwen3.8-Flash-Next` |
| 规模 | 176.9B 参数，BF16 约 354 GB |
| 许可 | **Apache-2.0**（本发布继承） |

## 2. 上游压缩发布（剪枝 + 量化）

| 项 | 值 |
|---|---|
| 发布 | `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF` |
| 实验室 | Deep Algorithms and Systems Lab (DASLab), Institute of Science and Technology Austria |
| 内容 | 512 → 256 专家/层（RCO 联合搜索），保留权重 3.5 bpw（GSQ）；GGUF IQ1_M 双分片 58.4 GB |
| 本发布与它的关系 | **同一份权重**，本发布只是换了一个运行时容器（`.allmpack`，不重编码） |

引用：

```bibtex
@article{gsq2026,
  title  = {GSQ: Highly-Accurate Low-Precision Scalar Quantization for LLMs via Gumbel-Softmax Sampling},
  author = {Dadgarnia, Alireza and Tabesh, Soroush and Nikdan, Mahdi and Helcig, Michael and Kurtic, Eldar and Kleinegger, Maximilian and Alistarh, Dan},
  journal= {arXiv preprint arXiv:2604.18556},
  year   = {2026}
}

@article{rco2026,
  title  = {Model Compression with Exact Budget Constraints via Riemannian Manifolds},
  author = {Helcig, Michael and Alistarh, Dan},
  journal= {arXiv preprint arXiv:2605.00649},
  year   = {2026}
}
```

- GSQ 代码：https://github.com/IST-DASLab/GSQ
- RCO 代码：https://github.com/IST-DASLab/RCO

## 3. 运行时（allm）

| 项 | 值 |
|---|---|
| 组件 | `allm`（`lib-allm` 的 `[[bin]] allm`） |
| 归属 | **abot** 项目的本地推理运行时 |
| 许可 | **Apache-2.0**（见同目录 `LICENSE`） |
| 关键依赖 | [Candle](https://github.com/huggingface/candle)（Apache-2.0/MIT）、axum（MIT）、tokenizers（Apache-2.0）、minijinja（Apache-2.0）等 |

本仓库中 `LICENSE` 是运行时（allm）的许可；权重继承基座许可，两者同为 Apache-2.0，无需分别声明。

## 4. 容器格式（.allmpack）

`.allmpack` 是 allm 的运行时权重容器格式，由 abot/allm 项目定义与实现
（`libs/lib-allm/src/common/pack`）。它**不改变权重数值**，只做对齐、丢弃 tokenizer 表、
裁剪逐层 n-gram 表三件事。
