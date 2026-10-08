#!/usr/bin/env bash
# 调用 /v1/chat/completions（OpenAI 兼容）。
# 用法：chat.sh [base_url] [--stream]     缺省 http://127.0.0.1:18100，非流式
set -euo pipefail

BASE="http://127.0.0.1:18100"
STREAM=false
for a in "$@"; do
  case "$a" in
    --stream) STREAM=true ;;
    http*) BASE="$a" ;;
  esac
done

BODY='{"model":"Qwen3.8-Flash-Next-Allm","messages":[{"role":"user","content":"把这个函数改成迭代写法：fn sum(v:&[i32])->i32 { v.iter().sum() }"}],"max_tokens":256,"temperature":0'

if [ "$STREAM" = true ]; then
  curl -N -sS "$BASE/v1/chat/completions" -H 'content-type: application/json' -d "$BODY,\"stream\":true}"
else
  curl -sS "$BASE/v1/chat/completions" -H 'content-type: application/json' -d "$BODY}" | python3 -m json.tool
fi
