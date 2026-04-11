# CX-7 Backlink Architecture & Bandwidth

## Multi-Host Architecture

Each DGX Spark has two ConnectX-7 SuperNICs. Each physical QSFP port appears as **two Linux network devices** because the GB10 SoC can only present PCIe 5.0 x4 to a single device. NVIDIA uses CX-7 multi-host mode to aggregate two x4 links from separate PCIe root complexes (domains `0000` and `0002`):

```
enp1s0f0np0      (PCI 0000:01:00.0)  ──┐
                                        ├── Same physical QSFP port
enP2p1s0f0np0    (PCI 0002:01:00.0)  ──┘
```

Both interfaces report `LINK_UP` with a single cable. **Do not bond them in Linux** -- the aggregation is handled by the CX-7 firmware.

To use the full 200G bandwidth, you must drive traffic through **both** PCIe-domain interfaces simultaneously.

## Configuration

We use NVIDIA's Option 1 (link-local IPv4) via netplan:

```yaml
# /etc/netplan/40-cx7.yaml (chmod 600)
network:
  version: 2
  ethernets:
    enp1s0f0np0:
      link-local: [ ipv4 ]
      mtu: 9000
    enp1s0f1np1:
      link-local: [ ipv4 ]
      mtu: 9000
```

Link-local addresses (169.254.x.x) are deterministic from MAC and stable across reboots.

## Bandwidth Measurements

All measurements taken with `ib_write_bw` from the `perftest` suite (pre-installed on DGX Spark), sustained 10-second duration (`-D 10`), 65536-byte messages.

### Unidirectional

| Configuration | Per-domain | Aggregate |
|---|---:|---:|
| Single PCIe domain (`rocep1s0f0` only) | **104 Gb/s** | 104 Gb/s |
| Both PCIe domains in parallel | 88 Gb/s each | **177 Gb/s** |

The single-domain ceiling of 104 Gb/s matches PCIe 5.0 x4 effective bandwidth exactly. Running both domains in parallel gives 177 Gb/s (88% of 200G nominal) -- a 15% per-domain contention tax from shared SoC memory bandwidth.

### Bidirectional

| Configuration | Sum (both directions) |
|---|---:|
| Single PCIe domain (`-b`) | **203 Gb/s** |
| Both PCIe domains (`-b`) | **295 Gb/s** |

Full duplex works essentially for free on a single PCIe channel (PCIe has separate TX/RX lanes). The 295 Gb/s aggregate is the highest measured throughput.

### MTU Impact

Bumping RoCE MTU from 1024 to 4096 (requires netdev MTU 9000) had **zero impact** on single-channel bandwidth. The ceiling is PCIe, not framing. However, **MTU mismatch between PCIe domains creates unfair sharing** -- when one domain was at MTU 4096 and the other at 1024, the higher-MTU domain grabbed 2.2x the bandwidth share.

### NCCL All-Reduce

```
NCCL 2.29.7, 2 ranks, all_reduce_perf -b 8M -e 256M:
Peak busbw at 256 MB: 17.39 GB/s = 138 Gb/s per direction = 276 Gb/s aggregate
```

This is **94% of the platform's raw RDMA bidirectional ceiling** (295 Gb/s from perftest). NCCL auto-detects and uses both PCIe domains.

## Key Takeaways

1. Any RDMA workload using only one `rocep*` device leaves half the cable's bandwidth on the floor
2. Even using both PCIe domains, there's a ~15% per-stream contention tax
3. For NCCL: `NCCL_IB_HCA=rocep1s0f0,roceP2p1s0f0` is already the default behavior (auto-discovery picks both)
4. MTU tuning doesn't help single-channel throughput but must be symmetric across all interfaces
