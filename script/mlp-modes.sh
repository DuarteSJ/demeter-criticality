#!/usr/bin/env bash
# Overnight comparison of PAC's MLP estimates (P0-P3) against the baselines,
# one VM at a time, on the workloads with a clear STATIC-vs-DRAM gap. Runs
# script/ablation.sh per workload (configs round-robin within a workload);
# each workload gets its own manifest under bench/ablation/.
#
# Prerequisite (once per host boot): source script/setup-host.sh
# Usage: setsid nohup script/mlp-modes.sh [repeats] >bench/mlp-modes.log 2>&1 &
# Env: WORKLOADS, CONFIGS (space-separated) override the defaults below.

set -u
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPEATS="${1:-3}"
WORKLOADS="${WORKLOADS:-bc xsbench graph500 liblinear}"
CONFIGS="${CONFIGS:-DRAM STATIC A B P0 P1 P2 P3 P4}"

echo "[mlp-modes] $(date) repeats=$REPEATS workloads=$WORKLOADS configs=$CONFIGS"
for w in $WORKLOADS; do
	# shellcheck disable=SC2086
	"$SELF/ablation.sh" "$w" "$REPEATS" $CONFIGS
done
echo "[mlp-modes] $(date) all done"
