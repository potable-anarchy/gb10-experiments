#!/usr/bin/env bash
# Launch trtllm-serve on the head node (bottom).
# Run AFTER run-trtllm-node.sh on BOTH Sparks.
set -euo pipefail

MODEL="${MODEL:-huihui-ai/Llama-3.3-70B-Instruct-abliterated}"
NAME=trtllm-multinode
PORT=8355
HF_TOKEN=$(tr -d '\n' < ~/.cache/huggingface/token)

# Hostfile -- backlink IPs
cat > /tmp/openmpi-hostfile <<HF
169.254.97.225
169.254.152.58
HF
docker cp /tmp/openmpi-hostfile ${NAME}:/etc/openmpi-hostfile

# API config
docker exec ${NAME} bash -c 'cat > /tmp/extra-llm-api-config.yml <<API
print_iter_log: false
kv_cache_config:
  dtype: "auto"
  free_gpu_memory_fraction: 0.85
cuda_graph_config:
  enable_padding: true
API'

# Launch server detached
docker exec -d \
  -e MODEL="$MODEL" \
  -e HF_TOKEN="$HF_TOKEN" \
  -e HF_HUB_OFFLINE=1 \
  -e TRANSFORMERS_OFFLINE=1 \
  ${NAME} \
  bash -c "mpirun -x HF_TOKEN -x HF_HUB_OFFLINE -x TRANSFORMERS_OFFLINE \
    trtllm-llmapi-launch trtllm-serve \"\$MODEL\" \
    --tp_size 2 \
    --backend pytorch \
    --max_num_tokens 8192 \
    --max_batch_size 2 \
    --extra_llm_api_options /tmp/extra-llm-api-config.yml \
    --host 0.0.0.0 \
    --port ${PORT} > /tmp/trtllm-serve.log 2>&1"

echo "Server launching on port ${PORT}. Monitor: docker exec ${NAME} tail -f /tmp/trtllm-serve.log"
