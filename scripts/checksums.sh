#!/usr/bin/env bash
# 生成发布包内所有文件与二进制的 SHA256SUMS（在 release/Qwen3.8-Flash-Next-Allm 下执行）。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# macOS 自带 shasum，Linux 用 sha256sum；两者输出格式一致（`hash  file`）。
if command -v shasum > /dev/null 2>&1; then
  digest() { shasum -a 256 "$1"; }
else
  digest() { sha256sum "$1"; }
fi

: > SHA256SUMS

# 二进制
for f in artifacts/*; do
  [ -f "$f" ] && digest "$f" >> SHA256SUMS
done

# 权重与 tokenizer 三件套（假定已放入本目录；缺失则跳过并告警）
for f in Qwen3.8-Flash-Next-Allm.allmpack tokenizer.json tokenizer_config.json; do
  if [ -f "$f" ]; then
    digest "$f" >> SHA256SUMS
  else
    echo "warn: 缺少 $f（跳过）" >&2
  fi
done

echo "==> SHA256SUMS"
cat SHA256SUMS
