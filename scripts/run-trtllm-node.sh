#!/usr/bin/env bash
# Start the TRT-LLM multinode container on this Spark.
# Run on BOTH Sparks before launch-server.sh.
set -euo pipefail
NAME=trtllm-multinode

if docker ps -a --format '{{.Names}}' | grep -q "^${NAME}$"; then
  docker rm -f ${NAME} >/dev/null
fi

docker run -d --rm \
  --name ${NAME} \
  --gpus '"device=all"' \
  --network host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --device /dev/infiniband:/dev/infiniband \
  -v /dev/nvidia-caps:/dev/nvidia-caps \
  --add-host bottom:169.254.97.225 \
  --add-host top:169.254.152.58 \
  -e UCX_NET_DEVICES="enp1s0f0np0,enp1s0f1np1" \
  -e NCCL_SOCKET_IFNAME="enp1s0f0np0,enp1s0f1np1" \
  -e OMPI_MCA_btl_tcp_if_include="enp1s0f0np0,enp1s0f1np1" \
  -e OMPI_MCA_orte_default_hostfile="/etc/openmpi-hostfile" \
  -e OMPI_MCA_rmaps_ppr_n_pernode="1" \
  -e OMPI_ALLOW_RUN_AS_ROOT="1" \
  -e OMPI_ALLOW_RUN_AS_ROOT_CONFIRM="1" \
  -e CPATH=/usr/local/cuda/include \
  -e TRITON_PTXAS_PATH=/usr/local/cuda/bin/ptxas \
  -v "$HOME/.cache/huggingface/:/root/.cache/huggingface/" \
  -v "$HOME/.ssh:/tmp/.ssh:ro" \
  nvcr.io/nvidia/tensorrt-llm/release:1.3.0rc5 \
  sh -c "curl -fsSL https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/refs/heads/main/nvidia/trt-llm/assets/trtllm-mn-entrypoint.sh | sh"

# Fix Triton's bundled ptxas (doesn't support sm_121a)
sleep 5
docker exec ${NAME} bash -c \
  "mv /usr/local/lib/python3.12/dist-packages/triton/backends/nvidia/bin/ptxas /tmp/old.ptxas 2>/dev/null; \
   ln -sf /usr/local/cuda/bin/ptxas /usr/local/lib/python3.12/dist-packages/triton/backends/nvidia/bin/ptxas"

# Wait for sshd
for i in $(seq 1 30); do
  if nc -z localhost 2233 2>/dev/null; then
    echo "Container ${NAME} up, sshd:2233"
    docker exec ${NAME} nvidia-smi -L 2>&1 | head -3
    exit 0
  fi
  sleep 1
done
echo "WARNING: sshd:2233 not responding after 30s"
exit 1
