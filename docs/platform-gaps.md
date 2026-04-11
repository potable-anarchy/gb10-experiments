# DGX Spark Platform Gaps & Known Issues

DGX Spark is brand-new hardware (GB10 Grace+Blackwell, released late 2025). Several tools are not yet fully ported. This document tracks issues discovered during cluster bring-up.

## DCGM 4.5.3

- **ConnectX-7 SuperNICs not enumerated**: `dcgmi discovery -l` reports `0 ConnectX found` despite the CX-7s being on the same SoC and visible to `ibv_devices`
- **Diagnostic plugins partially ported**: `memory` and `pcie` plugins silently skip at level 2/3 (incompatible with Grace+Blackwell unified memory architecture)
- **Multinode diagnostic (`mnubergemm`) not supported**: returns `(Feature not supported) -6` -- designed for HGX-class multi-GPU nodes, not single-GPU-per-node Spark
- **SRAM Threshold Count**: NVML returns int64 sentinel value; DCGM correctly skips this sub-check
- **Profiling module**: shows "Not loaded" (lazy), untested whether it actually works on GB10

## Container Runtime

- **`/dev/nvidia-caps` not injected by `--gpus all`**: pynvml fails with `NVMLError_Unknown`. Workaround: add `-v /dev/nvidia-caps:/dev/nvidia-caps` to `docker run`
- **GPU state wedging after `kill -9`**: forcefully killing CUDA processes inside containers can leave NVML in a broken state where container-internal `nvidia-smi` fails but host `nvidia-smi` works. Fix: restart the container (or reboot if the container restart doesn't help)
- **Triton 3.5.1 bundled ptxas**: doesn't recognize `sm_121a` (GB10's compute capability). The system CUDA 13.1 ptxas in the same container DOES support it. Workaround: symlink

## Inference Frameworks

- **TRT-LLM 1.3.0rc5**: QKV weight loader assertion failure on `nvidia/Qwen3-235B-A22B-FP4` (NVFP4 quantized weights not supported by the fused QKV loading path in this version)
- **vLLM 25.11 + Ray**: NCCL `unhandled system error` during init_device on Grace+Blackwell multi-node. Works fine with MPI-based frameworks. Appears to be Ray-specific NCCL initialization bug
- **nvidia/Qwen3-235B-A22B-FP4**: published without tokenizer files (`vocab.json` missing, `tokenizer_config.json` empty). Only usable by TRT-LLM's internal pipeline, not by vLLM or generic HF loaders

## WiFi (MediaTek MT7925)

- **WiFi power save causes AP deauths**: the `mt7925e` driver with WiFi 7 MLO and default power save ON causes the AP to deauthenticate the client during idle periods. mDNS announcements are lost. Fix: `sudo nmcli connection modify <SSID> 802-11-wireless.powersave 2`
- **WiFi MAC randomization on resume**: after suspend/resume, WiFi may reassociate with a randomized MAC, causing stale ARP entries on other clients

## Power Management

- **Suspend enabled by default**: DGX Spark ships with GNOME desktop and default power management that suspends after inactivity. Both Sparks going to sleep simultaneously kills the cluster. Fix: `sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`

## GPU Overclocking

- All clock and power controls locked: `nvidia-smi -lgc`, `-pl`, `-ac` all return "not supported". The GPU auto-boosts but cannot be manually overclocked. This is a Spark-specific restriction; production DGX (H100/B200) exposes these controls
