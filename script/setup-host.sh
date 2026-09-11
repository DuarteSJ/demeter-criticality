#!/usr/bin/env bash
# Host per-boot setup for running Demeter on Ubuntu (e.g. traquina).
# The upstream README assumes Clear Linux, where these are already in place;
# on Ubuntu 26.04 + the demeterhost kernel we must do them explicitly each boot.
#
# SOURCE this file so the ulimit applies to your current shell:
#     source script/setup-host.sh
# (running it as ./script/setup-host.sh sets everything except the ulimit,
#  which would only affect the script's own subshell).

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

echo "[setup] kill leftover processes from previous runs"
echo "cloud-hyperviso virtiofsd pcm-memory gdb" | xargs -n1 sudo pkill -9 2>/dev/null || true

echo "[setup] load netfilter modules (kernel built them modular; Ubuntu libvirt needs them)"
sudo modprobe -a \
  ip_tables iptable_filter iptable_nat iptable_mangle iptable_raw \
  ip6_tables ip6table_filter ip6table_nat ip6table_mangle nf_nat \
  ipt_REJECT ip6t_REJECT xt_MASQUERADE xt_CHECKSUM xt_conntrack xt_tcpudp xt_mark xt_LOG \
  2>/dev/null || true

echo "[setup] system knobs"
sudo swapoff --all || true
sudo sysctl -w vm.overcommit_memory=1 >/dev/null
sudo sysctl -w kernel.perf_event_paranoid=-1 >/dev/null
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

echo "[setup] lock CPU frequency to 3.0 GHz (best-effort; ignore if governor forbids)"
echo 3000000 | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq >/dev/null 2>&1 || true
echo 3000000 | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq >/dev/null 2>&1 || true

echo "[setup] CXL/PMEM as system-ram NUMA nodes (idempotent)"
sudo daxctl reconfigure-device --human --mode=system-ram all >/dev/null 2>&1 || true

echo "[setup] VM networking (virbr921 bridge + ichb* taps)"
sudo "$SELF/network.bash" --restart || true

echo "[setup] raise file-descriptor limit for this shell"
ulimit -n 65535

echo "[setup] done. ulimit -n = $(ulimit -n); DRAM nodes 0/1, CXL nodes 2/3."
