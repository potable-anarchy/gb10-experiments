# DGX Spark 2-Node Cluster

A 2-node NVIDIA DGX Spark cluster connected via 200 GbE QSFP DAC, running distributed LLM inference.

## Hardware

| | bottom (`spark-7986`) | top (`spark-cb79`) |
|---|---|---|
| SoC | NVIDIA GB10 (Grace + Blackwell) | NVIDIA GB10 (Grace + Blackwell) |
| Memory | 128 GB unified (LPDDR5X) | 128 GB unified (LPDDR5X) |
| GPU | Blackwell, sm_121, CUDA 13.0 | Blackwell, sm_121, CUDA 13.0 |
| NIC | 2x ConnectX-7 SuperNIC (200 GbE each) | 2x ConnectX-7 SuperNIC (200 GbE each) |
| OS | DGX OS 7.5 (Ubuntu 24.04 aarch64) | DGX OS 7.5 (Ubuntu 24.04 aarch64) |
| Driver | NVIDIA 580.142 | NVIDIA 580.142 |
| Backlink | 1x QSFP 200G DAC on port 0 (`enp1s0f0np0`) | 1x QSFP 200G DAC on port 0 (`enp1s0f0np0`) |

## Key Findings

### CX-7 Multi-Host Architecture

Each 200G QSFP port appears as **two Linux netdevs** (`enp1s0f0np0` and `enP2p1s0f0np0`) because GB10 can only present PCIe x4 to a single device. NVIDIA uses CX-7 multi-host mode to aggregate two x4 PCIe links from separate root complexes. **Do not bond them in Linux** -- aggregation is in CX-7 firmware.

### Bandwidth Measurements

| Test | Result |
|---|---|
| Single PCIe domain, unidirectional | 104 Gb/s (PCIe 5.0 x4 ceiling) |
| Dual PCIe domain, unidirectional | 177 Gb/s sustained (88% of 200G) |
| Single PCIe domain, bidirectional | 203 Gb/s (full duplex works free) |
| Dual PCIe domain, bidirectional | 295 Gb/s (highest measured) |
| NCCL all-reduce (2 node) | 138 Gb/s busbw = 276 Gb/s aggregate (94% of ceiling) |

### Inference Performance

| Model | Framework | tok/s (before tuning) | tok/s (after tuning) |
|---|---|---|---|
| Llama 3.3 70B Instruct abliterated (BF16, TP=2) | TRT-LLM 1.3.0rc5 | 2.80 | 3.41 (+22%) |

### Memory Limits

| Format | Max total weight size | Max param count | Notes |
|---|---|---|---|
| BF16 | ~140 GB | ~70B | Proven (97.5% utilization, 2GB swap spill) |
| FP8 | ~180 GB | ~180B | Estimated |
| INT4/AWQ | ~150 GB | ~300B | Estimated (405B INT4 confirmed OOM) |

## Setup

### Quick Start

```bash
# 1. Network (run on each Spark)
scripts/netplan-backlink.sh

# 2. Performance tuning (run on each Spark)
scripts/max-perf.sh

# 3. Start inference server (run scripts in order)
# On both Sparks:
scripts/run-trtllm-node.sh
# On bottom only:
scripts/launch-server.sh
```

### Prerequisites

- SSH keys deployed between both Sparks (via backlink IPs)
- `/etc/hosts` on each Spark: `bottom` -> `169.254.97.225`, `top` -> `169.254.152.58` (both self and peer)
- HF token at `~/.cache/huggingface/token` on both Sparks
- Docker group membership: `sudo usermod -aG docker brad`
- Suspend disabled: `sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
- WiFi power save disabled: `sudo nmcli connection modify hacienda_MLO 802-11-wireless.powersave 2`

## Directory Structure

```
scripts/          -- Automation scripts for cluster setup and operation
  netplan-backlink.sh   -- Configure CX-7 backlink (NVIDIA Option 1 link-local)
  max-perf.sh           -- Performance tuning (CPU boost, C-states, THP, network)
  run-trtllm-node.sh    -- Start TRT-LLM container on a Spark
  launch-server.sh      -- Launch trtllm-serve (run on head node after both containers up)
  chat.py               -- Interactive terminal chat client
  bench.sh              -- Inference benchmark (3 runs, reports tok/s)
docs/             -- Detailed findings and platform notes
  backlink.md           -- CX-7 multi-host architecture + bandwidth measurements
  inference.md          -- Distributed inference setup, gotchas, and performance
  tuning.md             -- Performance tuning guide
  platform-gaps.md      -- Known issues with DGX Spark tooling (DCGM, containers, etc.)
```
