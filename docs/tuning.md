# Performance Tuning Guide

## Results

All tuning combined yields **+22% inference throughput** (2.80 -> 3.41 tok/s) on Llama 3.3 70B BF16 TP=2.

## CPU Tuning

### Frequency Boost

DGX Spark ships with CPU boost **disabled by default**. Grace has a big.LITTLE layout:

| Cores | Type | Base clock | Boosted clock |
|---|---|---:|---:|
| 0-4, 10-14 | Efficiency | 2808 MHz | 2860 MHz (+1.9%) |
| 5-9, 15-19 | Performance | 3900 MHz | 4004 MHz (+2.7%) |

Enable:
```bash
echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost
```

### C-State Disabling

Disabling deep idle states eliminates wakeup latency when cores are needed:

```bash
for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state[2-9]; do
  echo 1 | sudo tee "$cpu/disable" > /dev/null 2>&1 || true
done
```

### Governor

Already `performance` by default on DGX Spark, but verify:

```bash
for g in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
  echo performance | sudo tee "$g" > /dev/null
done
```

## Memory Tuning

```bash
sudo sysctl -w vm.swappiness=1           # Avoid swap unless critical
sudo sysctl -w vm.dirty_ratio=40          # Allow more dirty pages
sudo sysctl -w vm.dirty_background_ratio=10
sudo sysctl -w vm.zone_reclaim_mode=0     # Don't reclaim from local zones
sudo sysctl -w kernel.numa_balancing=0    # Single-socket, no NUMA to balance
```

### Transparent Huge Pages

```bash
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
```

## Network Tuning (NCCL)

64 MB socket buffers for NCCL throughput:

```bash
sudo sysctl -w net.core.rmem_max=67108864
sudo sysctl -w net.core.wmem_max=67108864
sudo sysctl -w net.core.rmem_default=67108864
sudo sysctl -w net.core.wmem_default=67108864
sudo sysctl -w net.core.optmem_max=67108864
sudo sysctl -w net.core.netdev_max_backlog=250000
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864"
sudo sysctl -w net.ipv4.tcp_wmem="4096 87380 67108864"
```

### IRQ Affinity

Pin CX-7 interrupts to performance cores (5-9) to avoid efficiency-core handling:

```bash
for irq in $(grep -l enp1s0f0 /proc/irq/*/actions 2>/dev/null | \
             sed 's|/proc/irq/||;s|/.*||'); do
  echo "0e0" | sudo tee /proc/irq/$irq/smp_affinity > /dev/null 2>&1
done
```

## GPU

DGX Spark **locks down all GPU overclocking**:

| Control | Status |
|---|---|
| `nvidia-smi -lgc` (lock clocks) | Not supported |
| `nvidia-smi -pl` (power limit) | Not supported |
| `nvidia-smi -ac` (app clocks) | Not supported |
| Supported clocks query | N/A |
| Fan control | Firmware-managed |

The GPU auto-boosts from ~2405 MHz to 3003 MHz under load. Persistence mode should be enabled:

```bash
sudo nvidia-smi -pm 1
```

On production DGX (H100/B200 HGX), `-lgc`, `-pl`, and `-ac` all work and are standard operator knobs.

## What Doesn't Help

- **MTU increase** (1500 -> 9000): zero impact on single-channel bandwidth (PCIe is the bottleneck, not framing)
- **NCCL_IB_HCA explicit setting**: auto-discovery already picks both CX-7 PCIe domains
- **More QPs** (`ib_write_bw -q 8`): only +2.5% over single QP (not CPU-bound on QP processing)
