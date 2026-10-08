#!/usr/bin/env bash
# 产出 macOS arm64 的两个发布变体：allm-metal / allm-cpu。
# 用法：build-runtime.sh        （在 meta 仓内任意位置执行；脚本自己定位仓根）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # meta 仓根
OUT="$ROOT/release/Qwen3.8-Flash-Next-Allm/artifacts"
TRIPLE="$(rustc -vV | awk '/^host:/{print $2}')"
case "$TRIPLE" in
  *-apple-darwin) ;;
  *) echo "build-runtime.sh 只用于 macOS（当前 host: $TRIPLE）" >&2; exit 1 ;;
esac

mkdir -p "$OUT"

echo "==> allm-metal ($TRIPLE, --features metal)"
cargo build --release --manifest-path "$ROOT/Cargo.toml" -p lib-allm --bin allm --features metal
cp "$ROOT/target/release/allm" "$OUT/allm-metal-$TRIPLE"

echo "==> allm-cpu ($TRIPLE, 默认 feature)"
cargo build --release --manifest-path "$ROOT/Cargo.toml" -p lib-allm --bin allm
cp "$ROOT/target/release/allm" "$OUT/allm-cpu-$TRIPLE"

chmod +x "$OUT"/allm-*-"$TRIPLE"
echo "==> 产物"
ls -lh "$OUT"
