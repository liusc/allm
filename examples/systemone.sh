#!/usr/bin/env bash
# 调用 /v1/systemone：一次前向、无自由文本生成，typed questions 从决策位 logits 读取。
# 用法：systemone.sh [base_url]        缺省 http://127.0.0.1:18100
set -euo pipefail

BASE="${1:-http://127.0.0.1:18100}"

curl -sS "$BASE/v1/systemone" -H 'content-type: application/json' -d '{
  "model": "jev-latest",
  "state": "订单 #7710 到货时箱子破损，里面的花瓶裂了。已送达 3 天。",
  "questions": {
    "refund_eligible": {"type": "noul", "instructions": "按店铺政策，客户有权全额退款。"},
    "responsible_department": {"type": "choice", "instructions": "该由哪个部门处理？",
      "criteria": {"billing": "重复扣款与支付错误", "logistics": "运输破损、丢件或延误", "product_support": "商品缺陷排查"}},
    "urgency": {"type": "score", "instructions": "这个工单有多紧急？", "criteria": ["常规", "紧急", "火急"]}
  }}' | python3 -m json.tool
