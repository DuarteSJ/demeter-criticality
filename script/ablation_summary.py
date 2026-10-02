#!/usr/bin/env python3
"""Summarize a script/ablation.sh manifest: per-run metrics and per-config
mean/stdev. Also writes the per-second gups throughput series next to the
manifest (series.csv) for plotting.

Usage: python3 script/ablation_summary.py bench/ablation/<run>/manifest.csv
"""

import csv
import re
import statistics
import sys
from datetime import datetime
from pathlib import Path

GUPS_FINAL = re.compile(r"GUPS: iteration (\w[\w ]*?) final ([\d.]+)")
GUPS_INST = re.compile(r"^(\S+Z)\s.*GUPS: iteration (\w[\w ]*?) hitherto [\d.]+ instaneous ([\d.]+)")
BTREE_LOOKUP = re.compile(r"got \d+ matches in ([\d.]+) seconds")
BTREE_TOTAL = re.compile(r"Total time: ([\d.]+)")
EXCH = re.compile(r"^\[\s*([\d.]+)\] policy_send_exch_reqs: exchange request sent promotion=(\d+)M")
POLICY = re.compile(r"target_drop: policy=\d+ permyriad=(\d+)")
CLS = re.compile(r"rt_pac_tick: cls .*fast=(\d+) slow=(\d+)")
WALL = re.compile(r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (?:(\d+):)?(\d+):([\d.]+)")
GAPBS_AVG = re.compile(r"^Average Time:\s+([\d.]+)", re.M)
GAPBS_TRIAL = re.compile(r"^Trial Time:\s+([\d.]+)", re.M)
XS_RUNTIME = re.compile(r"^Runtime:\s+([\d.]+) seconds", re.M)
G500_CONSTRUCT = re.compile(r"^construction_time:\s+([\d.e+-]+)", re.M)
PAC_TICK = re.compile(r"rt_pac_tick: tick=\d+ samples=\d+ slow=(\d+) W=\d+ occ=\d+ busy=(\d+) mlp_x1000=(\d+)")


def read(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def parse_run(workload: str, run: Path, series: list, cfg: str, rep: str) -> dict:
    m = {}
    log = read(run / f"{workload}.log")
    if workload == "gups":
        for label, val in GUPS_FINAL.findall(log):
            m[f"gups_{label.replace(' ', '_')}"] = float(val)
        pts = []
        for ts, label, val in (GUPS_INST.match(l).groups() for l in log.splitlines() if GUPS_INST.match(l)):
            t = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
            pts.append((t, label, float(val)))
        if pts:
            t0 = pts[0][0]
            series.extend((cfg, rep, round(t - t0, 1), label, v) for t, label, v in pts)
            last = [v for _, _, v in pts[-60:]]
            m["gups_last60s"] = statistics.mean(last)
    else:
        if (x := BTREE_LOOKUP.search(log)):
            m["btree_lookup_s"] = float(x.group(1))
        if (x := BTREE_TOTAL.search(log)):
            m["btree_total_s"] = float(x.group(1))

    # Every workload runs under /bin/time --verbose (stderr -> <workload>.err).
    if (x := WALL.search(read(run / f"{workload}.err"))):
        h, mnt, sec = x.groups()
        m["wall_s"] = int(h or 0) * 3600 + int(mnt) * 60 + float(sec)
    if (x := GAPBS_AVG.search(log)):
        m["gapbs_avg_trial_s"] = float(x.group(1))
    # Early trials run before Demeter migrates anything (~45s after attach);
    # the last trials are the tiered steady state.
    trials = [float(t) for t in GAPBS_TRIAL.findall(log)]
    if trials:
        m["gapbs_first_trial_s"] = trials[0]
        m["gapbs_last5_trial_s"] = statistics.mean(trials[-5:])
        series.extend((cfg, rep, i, "trial", t) for i, t in enumerate(trials))

    # Workload-reported time of the measured phase (excludes data setup).
    if (x := XS_RUNTIME.search(log)):
        m["xsbench_runtime_s"] = float(x.group(1))
    # Graph500's BFS phase is ~2s; generation (~100s, before Demeter's first
    # exchange) and CSR construction (~70s) dominate, so report construction.
    if (x := G500_CONSTRUCT.search(log)):
        m["graph500_construct_s"] = float(x.group(1))

    dmesg = read(run / "dmesg")
    exch = [(float(t), int(mb)) for t, mb in (EXCH.match(l).groups() for l in dmesg.splitlines() if EXCH.match(l))]
    if dmesg:
        m["exchanges"] = len(exch)
        m["promoted_mb"] = sum(mb for _, mb in exch)
        if exch:
            m["first_exch_s"] = exch[0][0]
    if (x := POLICY.search(dmesg)):
        m["policy_cpu_pct"] = int(x.group(1)) / 100
    cls = [(int(f), int(s)) for f, s in CLS.findall(dmesg)]
    if cls:
        fast, slow = sum(f for f, _ in cls), sum(s for _, s in cls)
        m["slow_share_pct"] = 100 * slow / max(fast + slow, 1)
    # PAC tick log (1/s): the MLP the chosen mlp_mode saw, over ticks whose
    # denominator counted (mode 0 logs MLP 1), and how often a window had
    # slow-tier samples to attribute.
    ticks = [(int(sl), int(b), int(x)) for sl, b, x in PAC_TICK.findall(dmesg)]
    if ticks:
        mlps = [x / 1000 for _, b, x in ticks if b]
        if mlps:
            m["pac_mlp_mean"] = statistics.mean(mlps)
        m["pac_ticks_slow_pct"] = 100 * sum(1 for sl, _, _ in ticks if sl) / len(ticks)
    return m


def main():
    manifest = Path(sys.argv[1])
    # <timestamp>-<workload>[-<variant>]; the log is named after <workload>
    workload = manifest.parent.name.split("-")[1]
    rows = list(csv.DictReader(manifest.open()))
    repo = manifest.resolve().parents[3]  # <repo>/bench/ablation/<run>/manifest.csv
    series, per_run = [], []
    for r in rows:
        run = repo / r["dir"] / "0"
        m = parse_run(workload, run, series, r["config"], r["repeat"]) if r["status"] == "ok" else {}
        exits = manifest.parent / f"{r['config']}-{r['repeat']}.exits"
        if m and (x := re.search(r"^\s*(\d+)\s+kvm:kvm_exit", read(exits), re.M)) and (
            t := re.search(r"([\d.]+) seconds time elapsed", read(exits))
        ):
            m["vmexits_k_per_s"] = int(x.group(1)) / float(t.group(1)) / 1000
        per_run.append((r["config"], r["repeat"], r["status"], m))

    keys = sorted({k for *_, m in per_run for k in m})
    print("== per run")
    print("config rep status " + " ".join(keys))
    for cfg, rep, status, m in per_run:
        print(f"{cfg} {rep} {status} " + " ".join(f"{m[k]:.4g}" if k in m else "-" for k in keys))

    print("\n== per config: mean +- stdev (n)")
    for cfg in dict.fromkeys(c for c, *_ in per_run):
        ms = [m for c, _, s, m in per_run if c == cfg and s == "ok"]
        cells = []
        for k in keys:
            vals = [m[k] for m in ms if k in m]
            if not vals:
                cells.append(f"{k}=-")
            elif len(vals) == 1:
                cells.append(f"{k}={vals[0]:.4g} (1)")
            else:
                cells.append(f"{k}={statistics.mean(vals):.4g}+-{statistics.stdev(vals):.2g} ({len(vals)})")
        print(f"{cfg}: " + "  ".join(cells))

    if series:
        out = manifest.parent / "series.csv"
        with out.open("w", newline="") as f:
            w = csv.writer(f)
            # gups: x = seconds, kind = pass, value = GUPS;
            # gapbs: x = trial index, kind = "trial", value = trial seconds.
            w.writerow(["config", "repeat", "x", "kind", "value"])
            w.writerows(series)
        print(f"\nseries: {out}")


if __name__ == "__main__":
    main()
