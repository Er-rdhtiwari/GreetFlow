#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:?Usage: smoke_test.sh https://host}"

echo "==> Health"
curl -fsS "${BASE_URL}/healthz" | jq .

echo "==> Greet"
curl -fsS -X POST "${BASE_URL}/api/greet" \
  -H "content-type: application/json" \
  -d '{"name":"Radhe","dob":"1995-01-10","occasion":"new_year","tone":"motivational"}' | jq .

echo "✅ Smoke test passed for ${BASE_URL}"
