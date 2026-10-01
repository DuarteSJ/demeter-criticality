#!/usr/bin/env bash
# Signal/metric ablation: run each config REPEATS times, round-robin (so drift
# over the session spreads across configs), and record which archive dir
# belongs to which config in a manifest for script/ablation_summary.py.
#
#   A      frequency ranking, load-latency samples (upstream Demeter)
#   B      frequency ranking, L3-miss samples      (signal effect: B vs A)
#   C      PAC ranking,       L3-miss samples      (metric effect: C vs B)
#          (L2MLP, cooling alpha 0.9: the 2026-10-01 bc runs)
# PAC with each MLP estimate (mlp_mode), L3-miss samples, PACT's alpha 1.0:
#   P0     MLP = 1 (control: slow-tier sample counting, no MLP)
#   P1     L2MLP
#   P2     L3-miss MLP
#   P3     window Little's Law over the whole VM, L3-miss occupancy / cycles
#   P4     slow-tier Little's Law from load-latency PEBS (PACT's per-tier
#          fallback; needs load_event 0, so its samples differ from P0-P3).
#          Threshold 190 cycles (~64ns at 3GHz, the Demeter paper's intent;
#          the register counts cycles, and upstream's 60 = ~20ns keeps L3
#          hits), so its slow samples are slow-tier misses only.
#   STATIC no Demeter, same DRAM ratio              (Linux first-touch placement)
#   DRAM   no Demeter, all memory in DRAM           (upper bound)
#   A_DRAM config A with all memory in DRAM         (Demeter overhead: vs DRAM)
# Overhead breakdown, all at 100% DRAM with upstream ranking (compare to DRAM):
#   O_A          upstream Demeter as-is (= A_DRAM)
#   O_NOSTORE    store sampling effectively off (period 1e9)
#   O_NOLOAD     load sampling effectively off (period 1e9)
#   O_NONE       both off: Demeter attached, no samples
#   O_THROTTLE   Demeter's throttle: sampling on 1s of every 5s
#   O_LDLAT190   load latency threshold 190 cycles (~64ns, the paper's value)
#
# Prerequisite (once per host boot): source script/setup-host.sh
# Usage: script/ablation.sh <workload> [repeats] [configs...]
# Env: BENCH_EXTRA (extra Bench flags), RUN_TIMEOUT (per run, default 30m)
#   e.g. script/ablation.sh gups 3            # all configs, 3 repeats
#        script/ablation.sh btree 1 C STATIC  # pilot of two configs

set -u
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd "$SELF/.." && pwd)"
cd "$REPO"

WORKLOAD="${1:?usage: $0 <gups|btree> [repeats] [configs...]}"
REPEATS="${2:-3}"
shift $(($# < 2 ? $# : 2))
CONFIGS=("${@:-A B C STATIC DRAM A_DRAM}")
read -r -a CONFIGS <<<"${CONFIGS[*]}"

RATIO=0.2
case "$WORKLOAD" in
# 3.2e9 updates: ~90s per pass at ~0.035 GUPS (3 passes), so the ~4 min after
# the first exchange (~30s after attach) dominate and the last-60s steady
# state falls inside the last pass. Hot set starts on CXL (--reverse, the
# bench default).
gups) WARGS=(gups --update=3200000000) ;;
# Default gups length (8e8 updates, ~25s passes) for overhead runs, where the
# effect shows before any migration.
gups-short) WARGS=(gups) ;;
# 1e10 lookups: ~60s lookup phase (2e9 took ~12s).
btree) WARGS=(btree --l=10000000000) ;;
# bc-kron (PACT): 20 trials (~15-22s each) so the tiered steady state, after
# Demeter's first exchange ~45s in, dominates; summary uses the last 5 trials.
bc) WARGS=(bc --trials=20) ;;
# PACT's other GAPBS graph workloads; TRIALS overrides the trial count.
# Defaults from the 2026-10-02 DRAM pilot (s/trial: pr 27.2, cc 1.23, bfs
# 0.71, bc-twitter 10.9), so a run lasts ~5-6 min, mostly after the first
# exchange. pr-kron showed no STATIC-vs-DRAM gap (27.06 vs 27.21 s/trial).
pr-kron) WARGS=(pr --trials="${TRIALS:-10}") ;;
cc-kron) WARGS=(cc --trials="${TRIALS:-250}") ;;
bfs-kron) WARGS=(bfs --trials="${TRIALS:-400}") ;;
bc-twitter) WARGS=(bc --f=/data/twitter.sg --trials="${TRIALS:-30}") ;;
# Any other bench workload with its default arguments (see bench/workload.py).
*) WARGS=("$WORKLOAD") ;;
esac

OUT="bench/ablation/$(date +%Y%m%dT%H%M%S)-$WORKLOAD${BENCH_EXTRA:+-extra}"
mkdir -p "$OUT"
MANIFEST="$OUT/manifest.csv"
echo "config,repeat,dir,status" >"$MANIFEST"
echo "${BENCH_EXTRA:-}" >"$OUT/bench_extra.txt"
echo "[ablation] $WORKLOAD x${REPEATS}: ${CONFIGS[*]} -> $MANIFEST"

run_one() { # config repeat
	local cfg=$1 rep=$2 ratio=$RATIO env='{}' extra=()
	case "$cfg" in
	# rtree_exch_thresh 8MiB (upstream: 2MiB = the split granularity): on
	# workloads without sharp local hotspots (bc-kron) ranges stall around
	# 8MiB and upstream never migrates. Same value for A, B and C.
	A) env='{"ranking_mode": 0, "load_event": 0, "rtree_exch_thresh": 8388608}' ;;
	B) env='{"ranking_mode": 0, "load_event": 1, "rtree_exch_thresh": 8388608}' ;;
	C) env='{"ranking_mode": 1, "load_event": 1, "rtree_exch_thresh": 8388608, "pac_alpha_pm": 900, "mlp_mode": 1}' ;;
	P[0-3]) env='{"ranking_mode": 1, "load_event": 1, "rtree_exch_thresh": 8388608, "pac_alpha_pm": 1000, "mlp_mode": '"${cfg#P}"'}' ;;
	P4) env='{"ranking_mode": 1, "load_event": 0, "rtree_exch_thresh": 8388608, "pac_alpha_pm": 1000, "mlp_mode": 4, "load_latency_threshold": 190}' ;;
	STATIC) extra=(--launcher=env) ;;
	DRAM) ratio=1.0 extra=(--launcher=env) ;;
	A_DRAM | O_A) ratio=1.0 env='{"ranking_mode": 0, "load_event": 0}' ;;
	O_NOSTORE) ratio=1.0 env='{"ranking_mode": 0, "load_event": 0, "retired_stores_sample_period": 1000000000}' ;;
	O_NOLOAD) ratio=1.0 env='{"ranking_mode": 0, "load_event": 0, "load_latency_sample_period": 1000000000}' ;;
	O_NONE) ratio=1.0 env='{"ranking_mode": 0, "load_event": 0, "retired_stores_sample_period": 1000000000, "load_latency_sample_period": 1000000000}' ;;
	O_THROTTLE) ratio=1.0 env='{"ranking_mode": 0, "load_event": 0, "throttle_pulse_width_ms": 1000, "throttle_pulse_period_ms": 5000}' ;;
	O_LDLAT190) ratio=1.0 env='{"ranking_mode": 0, "load_event": 0, "load_latency_threshold": 190}' ;;
	*) echo "unknown config $cfg" >&2; return 1 ;;
	esac
	local log="$OUT/$cfg-$rep.log" dir status
	# VM launch occasionally fails right away (VmNotCreated / API RecvError,
	# not specific to any config); retry up to 3 times, 20s apart.
	for try in 1 2 3; do
		[ "$try" -gt 1 ] && sleep 20
		# Host-side VM-exit count over the whole run (boot included), so a
		# workload's exit rate (which drives guest PMU overhead) is on record.
		sudo env LC_ALL=C perf stat -a -e kvm:kvm_exit -o "$OUT/$cfg-$rep.exits" &
		local perf_pid=$!
		# BENCH_EXTRA: extra Bench flags for every run, e.g. --idle_poll=True
		timeout --signal=INT --kill-after=2m "${RUN_TIMEOUT:-30m}" \
			script/run-bench.sh --num 1 --mem $((16 << 30)) --dram-ratio "$ratio" \
			--dram_node 0 --pmem_node 2 --env="$env" ${BENCH_EXTRA:-} \
			"${WARGS[@]}" "${extra[@]}" >"$log" 2>&1
		local rc=$?
		sudo pkill -INT -P "$perf_pid" perf 2>/dev/null || sudo kill -INT "$perf_pid"
		wait "$perf_pid" 2>/dev/null
		dir=$(ls -1dt bench/archive/*/ | head -1)
		if grep -qa "Exit status: 0" "$dir"0/"${WORKLOAD%%-*}".err 2>/dev/null; then
			status=ok
			break
		fi
		status=failed
		# Only retry the launch flake, not a run that hit RUN_TIMEOUT.
		if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
			status=timeout
			break
		fi
	done
	echo "$cfg,$rep,$dir,$status" >>"$MANIFEST"
	echo "[ablation] $(date +%T) $cfg rep $rep: $status ($dir)"
}

for rep in $(seq 1 "$REPEATS"); do
	for cfg in "${CONFIGS[@]}"; do
		run_one "$cfg" "$rep"
	done
done
echo "[ablation] done: python3 script/ablation_summary.py $MANIFEST"
