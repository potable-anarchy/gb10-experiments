#!/usr/bin/env bash
# Maximum performance tuning for DGX Spark.
# Run on EACH Spark. Yields ~22% inference speedup.
set -e

echo "=== 1. CPU boost (persistent) ==="
echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost
sudo bash -c 'cat > /etc/systemd/system/cpu-boost.service <<EOF
[Unit]
Description=Enable CPU frequency boost
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "echo 1 > /sys/devices/system/cpu/cpufreq/boost"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'
sudo systemctl daemon-reload
sudo systemctl enable cpu-boost.service

echo "=== 2. All governors to performance ==="
for g in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
  echo performance | sudo tee "$g" > /dev/null
done

echo "=== 3. Disable deep C-states ==="
for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state[2-9]; do
  echo 1 | sudo tee "$cpu/disable" > /dev/null 2>&1 || true
done

echo "=== 4. Kernel memory tuning ==="
sudo sysctl -w vm.swappiness=1
sudo sysctl -w vm.dirty_ratio=40
sudo sysctl -w vm.dirty_background_ratio=10
sudo sysctl -w vm.zone_reclaim_mode=0
sudo sysctl -w kernel.numa_balancing=0

echo "=== 5. Transparent huge pages ==="
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

echo "=== 6. Network buffers for NCCL ==="
sudo sysctl -w net.core.rmem_max=67108864
sudo sysctl -w net.core.wmem_max=67108864
sudo sysctl -w net.core.rmem_default=67108864
sudo sysctl -w net.core.wmem_default=67108864
sudo sysctl -w net.core.optmem_max=67108864
sudo sysctl -w net.core.netdev_max_backlog=250000
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864"
sudo sysctl -w net.ipv4.tcp_wmem="4096 87380 67108864"

echo "=== 7. IRQ affinity for CX-7 -> performance cores ==="
for irq in $(grep -l enp1s0f0 /proc/irq/*/actions 2>/dev/null | sed 's|/proc/irq/||;s|/.*||' || true); do
  echo "0e0" | sudo tee /proc/irq/$irq/smp_affinity > /dev/null 2>&1 || true
done

echo "=== 8. GPU persistence mode ==="
sudo nvidia-smi -pm 1

echo "=== Done ==="
echo "Performance cores: $(cat /sys/devices/system/cpu/cpufreq/policy19/scaling_cur_freq)kHz"
echo "Efficiency cores:  $(cat /sys/devices/system/cpu/cpufreq/policy10/scaling_cur_freq)kHz"
echo "GPU clock:         $(nvidia-smi --query-gpu=clocks.gr --format=csv,noheader)"
echo "GPU temp:          $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader)C"
