#!/usr/bin/env bash
# Demeter functionality smoke test (upstream README "Quick Functionality Test").
# Boots N Demeter guests, sets up tiering, runs a trivial command inside each,
# and collects logs to bench/archive/<timestamp>/.
#
# Prerequisite (same shell): source script/setup-host.sh
# Usage: script/functionality-test.sh [num_vms]   (default 3)

set -eu
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd "$SELF/.." && pwd)"
cd "$REPO"

NUM="${1:-3}"

# Python env + staged binaries on PATH
source py313/bin/activate
export PATH="$(realpath bin):$PATH"

# Optional sanity checks (non-fatal)
echo "[test] NUMA nodes (expect DRAM 0/1, CXL system-ram 2/3):"
numactl --hardware | grep -E "node [0-9]+ (cpus|size)" || true
echo "[test] bridge (expect virbr921 192.168.92.1/24):"
ip -br addr show virbr921 || echo "  WARNING: virbr921 missing - run 'source script/setup-host.sh' first"

poetry -C bench install
poetry -C bench run python3 -m bench \
  --num "$NUM" --kernel demeter --mem 17179869184 \
  --dram-ratio 0.2 --dram_node 0 --pmem_node 2 \
  run 'echo "Hello, Demeter!" | sudo tee /out/hello.log'

echo "[test] done. Logs under bench/archive/ (newest):"
ls -1dt bench/archive/*/ 2>/dev/null | head -1 || true
