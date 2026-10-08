#!/usr/bin/env bash
# 在 linux x86_64 构建机上产出 allm-cpu 并把二进制取回本机（macOS）。
# 用法：build-runtime-linux.sh [user@host] [port]     （缺省 dev@192.168.3.5 2222）
set -euo pipefail

HOST="${1:-dev@192.168.3.5}"
PORT="${2:-2222}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # meta 仓根
OUT="$ROOT/release/Qwen3.8-Flash-Next-Allm/artifacts"
REMOTE_DIR="~/dsh-abot"

echo "==> 同步工作树到 ${HOST}:${REMOTE_DIR}（排除 target/.git/node_modules）"
tar -czf - -C "$ROOT" \
    --exclude=target --exclude=.git --exclude=node_modules \
    AGENTS.md Cargo.toml Cargo.lock rust-toolchain.toml abot libs \
  | ssh -p "$PORT" "$HOST" "mkdir -p $REMOTE_DIR && tar -C $REMOTE_DIR -xzf -"

echo "==> 远端构建 allm-cpu (x86_64-unknown-linux-gnu)"
ssh -p "$PORT" "$HOST" "export PATH=\$HOME/.cargo/bin:\$PATH; cd $REMOTE_DIR && cargo build --release -p lib-allm --bin allm && ./target/release/allm --version"

echo "==> 取回二进制（base64：直连 `cat` 会被管道做文本化，二进制被截断）"
mkdir -p "$OUT"
ssh -p "$PORT" "$HOST" "base64 -w0 $REMOTE_DIR/target/release/allm" \
  | base64 -d > "$OUT/allm-cpu-x86_64-unknown-linux-gnu"
chmod +x "$OUT/allm-cpu-x86_64-unknown-linux-gnu"

# 本地校验：长度必须与远端一致（不信任管道）
LOCAL_BYTES="$(wc -c < "$OUT/allm-cpu-x86_64-unknown-linux-gnu")"
REMOTE_BYTES="$(ssh -p "$PORT" "$HOST" "wc -c < $REMOTE_DIR/target/release/allm")"
if [ "$LOCAL_BYTES" != "$REMOTE_BYTES" ]; then
  echo "取回长度不一致：本地 $LOCAL_BYTES / 远端 $REMOTE_BYTES" >&2
  exit 1
fi
ls -lh "$OUT/allm-cpu-x86_64-unknown-linux-gnu"
