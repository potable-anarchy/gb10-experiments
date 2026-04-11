#!/usr/bin/env bash
# Configure the CX-7 backlink per NVIDIA's Option 1 (link-local IPv4).
# Run on EACH Spark.
set -euo pipefail

cat <<'EOF' | sudo tee /etc/netplan/40-cx7.yaml > /dev/null
network:
  version: 2
  ethernets:
    enp1s0f0np0:
      link-local: [ ipv4 ]
      mtu: 9000
    enp1s0f1np1:
      link-local: [ ipv4 ]
      mtu: 9000
EOF

sudo chmod 600 /etc/netplan/40-cx7.yaml
sudo netplan apply
sleep 3

echo "Backlink configured:"
ip -br addr show enp1s0f0np0
echo "MTU: $(cat /sys/class/net/enp1s0f0np0/mtu)"
