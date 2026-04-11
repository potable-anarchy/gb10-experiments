#!/usr/bin/env bash
# Benchmark inference tok/s. Run on the head node (bottom).
set -e

MODEL="${MODEL:-huihui-ai/Llama-3.3-70B-Instruct-abliterated}"
ENDPOINT="${ENDPOINT:-http://localhost:8355/v1/chat/completions}"
RUNS="${1:-3}"

echo "Model: $MODEL"
echo "Endpoint: $ENDPOINT"
echo "Runs: $RUNS"
echo

echo "=== Warm-up ==="
curl -s "$ENDPOINT" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}" > /dev/null

echo "=== Benchmark ==="
total_tps=0
for i in $(seq 1 $RUNS); do
  t0=$(date +%s%N)
  resp=$(curl -s "$ENDPOINT" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Write exactly 100 words about distributed computing.\"}],\"max_tokens\":200,\"temperature\":0.7}")
  t1=$(date +%s%N)
  comp=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['usage']['completion_tokens'])")
  elapsed=$(echo "scale=2; ($t1-$t0)/1000000000" | bc)
  tps=$(echo "scale=2; $comp/$elapsed" | bc)
  total_tps=$(echo "scale=2; $total_tps+$tps" | bc)
  echo "Run $i: ${comp} tokens in ${elapsed}s = ${tps} tok/s"
done
avg=$(echo "scale=2; $total_tps/$RUNS" | bc)
echo
echo "Average: ${avg} tok/s"
