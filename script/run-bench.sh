#!/usr/bin/env bash
# Run any bench command with the env functionality-test.sh sets up (py313 venv,
# staged binaries on PATH). Arguments are passed straight to `python3 -m bench`.
# Logs go to bench/archive/<timestamp>/ (guest dmesg: 0/cloud-hypervisor.stdout).
#
# Prerequisite (once per host boot): source script/setup-host.sh
# Example:
#   script/run-bench.sh --num 1 --mem $((16<<30)) --dram-ratio 0.2 \
#     --dram_node 0 --pmem_node 2 --env='{"ranking_mode": 1}' gups

set -eu
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd "$SELF/.." && pwd)"
cd "$REPO"

source py313/bin/activate
export PATH="$(realpath bin):$PATH"

poetry -C bench run python3 -m bench "$@"

echo "[run-bench] logs (newest):"
ls -1dt bench/archive/*/ 2>/dev/null | head -1 || true
