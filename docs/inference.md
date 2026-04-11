# Distributed Inference on DGX Spark

## Architecture

Two DGX Sparks running TensorRT-LLM with tensor parallelism (TP=2) across the 200G backlink. Each Spark holds half the model weights in unified Grace+Blackwell memory.

```
bottom (spark-7986)                    top (spark-cb79)
┌──────────────────────┐              ┌──────────────────────┐
│ TRT-LLM Rank 0       │              │ TRT-LLM Rank 1       │
│ ~66 GiB weights      │◄── NCCL ───►│ ~66 GiB weights      │
│ ~52 GiB KV cache     │  200G DAC    │ ~52 GiB KV cache     │
│ Port 8355 (API)      │              │                      │
└──────────────────────┘              └──────────────────────┘
```

## Container Setup

NGC container: `nvcr.io/nvidia/tensorrt-llm/release:1.3.0rc5` (33.9 GB, aarch64)

The container entrypoint runs OpenSSH on port 2233 for MPI inter-container communication. The actual inference server is launched via `docker exec` after both containers are up.

### Critical Container Fixes

1. **`/dev/nvidia-caps` must be bind-mounted** (`-v /dev/nvidia-caps:/dev/nvidia-caps`) -- without this, pynvml fails to initialize inside the container. Likely a CDI / `nvidia-ctk 1.19.0` regression on aarch64.

2. **Triton's bundled `ptxas` doesn't support GB10's `sm_121a`** even though the system CUDA 13.1 ptxas does. Fix: symlink the bundled binary to the system one:
   ```bash
   docker exec $CONTAINER bash -c \
     "mv /usr/local/lib/python3.12/dist-packages/triton/backends/nvidia/bin/ptxas /tmp/old.ptxas; \
      ln -sf /usr/local/cuda/bin/ptxas /usr/local/lib/python3.12/dist-packages/triton/backends/nvidia/bin/ptxas"
   ```

3. **`HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`** are essential when serving from cached weights -- otherwise startup hits HF Hub HEAD-request retries that compound with WiFi latency.

4. **`--add-host bottom:169.254.97.225 --add-host top:169.254.152.58`** must be passed to `docker run` because the container has its own `/etc/hosts`.

5. **Self-aliases in `/etc/hosts`** (`bottom` on bottom, `top` on top) are required or mpirun can't resolve local hostname.

## Performance

### Inference Speed

| | tok/s | Notes |
|---|---:|---|
| Before tuning | 2.80 | Default DGX Spark config |
| After tuning | 3.41 | +22%, CPU boost + kernel tuning |

### Why "only" 3.4 tok/s?

Tensor parallelism across nodes pays a **per-layer all-reduce latency penalty**. Llama 3.3 70B has 80 transformer blocks x 2 all-reduces = **160 cross-node NCCL syncs per token**. This is latency-bound, not bandwidth-bound -- no amount of cable bandwidth fixes it.

Real DGX SuperPODs keep TP within node (NVLink, ~900 GB/s) and use the inter-node fabric for PP/DP only. Single-GPU-per-node Spark forces TP across nodes -- that's the architectural cost of the form factor.

### Unified Memory Advantage

Grace+Blackwell unified memory means model weights don't need to be copied from CPU to GPU memory:

```
[load_weight_shard] Skipping device transfer from cpu to cuda
                    on integrated GPU to conserve shared memory.
```

This eliminates the PCIe copy bottleneck that discrete GPU systems face during model loading.

## Memory Limits

| Format | Max total weights | Max params | Status |
|---|---:|---:|---|
| BF16 | ~140 GB | ~70B | Proven (97.5% util, 2GB swap) |
| INT4/AWQ | ~150 GB | ~300B | Estimated |
| INT4/AWQ 405B | 200 GB | 405B | Confirmed OOM |

The bottleneck is the **transient loading peak** -- TRT-LLM loads safetensors in parallel, briefly needing ~1.5-2x model size. On unified memory there's no separate VRAM to absorb this.

## Model Notes

- **`huihui-ai/Llama-3.3-70B-Instruct-abliterated`** (BF16): proven working, 132 GB on disk, ~66 GiB per rank
- **`nvidia/Qwen3-235B-A22B-FP4`**: incompatible with TRT-LLM 1.3.0rc5 (QKV weight assertion error) and vLLM 25.11 (missing tokenizer)
- **`hugging-quants/Meta-Llama-3.1-405B-Instruct-AWQ-INT4`**: OOMs during loading (~200 GB weights exceed transient peak capacity)

## vLLM Compatibility

vLLM 25.11 (`nvcr.io/nvidia/vllm:25.11-py3`) with Ray has a **broken NCCL initialization on Grace+Blackwell**. The error (`NCCL error: unhandled system error`) persists even with `NCCL_IB_DISABLE=1`. MPI-based frameworks (TRT-LLM, nccl-tests) work fine on the same hardware. This appears to be a vLLM/Ray-specific NCCL issue on this platform.
