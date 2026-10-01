# Fork notice

This repository is a **fork of Demeter** for MSc thesis work. It is **not** the
official Demeter repository.

## Original work

> Junliang Hu, Zhisheng Hu, Chun-Feng Wu, and Ming-Chang Yang. 2025.
> *Demeter: A Scalable and Elastic Tiered Memory Solution for Virtualized Cloud
> via Guest Delegation.* In ACM SIGOPS 31st Symposium on Operating Systems
> Principles (SOSP '25). https://doi.org/10.1145/3731569.3764801

- Original authors: The Chinese University of Hong Kong / National Yang Ming
  Chiao Tung University.
- Original artifact (pristine): Zenodo, https://zenodo.org/records/16912877
- License: **GPL-2.0** (unchanged; see `LICENSE`).

The first commit of this repository (`Import Demeter SOSP'25 artifact
(pristine, GPL-2.0)`) is the unmodified artifact. Every later commit is a change
made for this thesis.

## What this fork changes / adds

Goal: bring **performance-criticality** (PACT, PAC = k * misses_slow / MLP) into
Demeter's guest-delegated tiering, computed entirely inside the guest, in place
of its frequency-based hotness. Scope: placement within one VM.

Kernel changes are patches applied by `kernel.mk` on top of `patch/demeter.patch`:

- `patch/spr-pebs.patch`: Sapphire/Emerald Rapids fixes. Guest module: load
  event `precise_ip` 3 -> 2 (PDist exists only on GP counter 0, which load
  latency cannot use, so attach failed with EINVAL). Host KVM: program the
  load-latency threshold and drop `PERF_SAMPLE_DATA_SRC` from the host backing
  event (it needs the mem-loads-aux group, else ENODATA).
- `patch/load-event.patch`: module parameter `load_event` picks the PEBS load
  event: 0 = load latency (upstream), 1 = `MEM_LOAD_RETIRED.L3_MISS` (PACT).
- `patch/pac.patch`: `ranking_mode=1` ranks ranges by PAC instead of frequency.
  Every `pac_window_ms` (20) the policy loop closes a window: slow-tier samples
  (physical address on the slow node) get `S * share`, with S = k * N_slow / MLP
  from per-task core counters; scores are cooled by `pac_alpha_pm` (default 1000,
  no cooling, PACT's default). Demotion skips ranges touched in the last
  `pac_recency_ticks` windows; rank ties fall back to the frequency order.
  `mlp_mode` picks the MLP estimate (no core counter is per tier, so all are per
  VM unless noted): 0 = none (MLP = 1, control), 1 = L2MLP (default),
  2 = L3-miss MLP, 3 = window Little's Law over the whole VM (L3-miss
  occupancy / cycles), 4 = slow-tier Little's Law from load-latency PEBS
  (period * sum of slow latencies / cycles; PACT's per-tier fallback, needs
  `load_event=0`; the slow-access count cancels in S, which this mode tests).

Bench and scripts: GAPBS workloads (bc, pr, cc, bfs; PACT's graph set) and an
opt-in guest `idle=poll`; `script/run-bench.sh` (run any bench command),
`script/ablation.sh` +
`script/ablation_summary.py` (configs round-robin, per-run metrics, host VM-exit
rate), `script/mlp-modes.sh` (all MLP modes against the baselines).

## Running on Ubuntu 26.04 (port notes)

The upstream artifact targets **Clear Linux + systemd-boot**. This fork is run on
**Ubuntu 26.04 + a kernel built from the Demeter config + grub**, which needs a
few adaptations. Build-time fixes are committed in the source; runtime pieces are
either automated by `script/setup-host.sh` or listed here as one-time host setup.

**Build-time (committed):**
- `toolchain.mk`: symlink `libxml2.so.2` -> system `libxml2.so.16` (prebuilt
  `ld.lld`/`clang` need the old soname).
- `kernel.mk`: after patching, exempt the glibc-2.41 const-string `-Werror` in the
  host tools `tools/lib/bpf/Makefile` and `tools/lib/subcmd/Makefile`.
- `workload/graph500/make.inc`: move `-lm` from `CFLAGS` to `LDLIBS` (modern `ld`
  `--as-needed` drops a lib placed before the objects).
- `bin.mk`: create the qcow2 root overlays with an **absolute** backing path;
  cloud-hypervisor resolves a relative backing against its cwd, not the overlay.
- `bench/bench/utils.py`: pick a **local** (`/etc/group`) group for virtiofsd's
  `--socket-group`; the static musl virtiofsd cannot resolve an LDAP-only primary
  group (common on clusters).

**One-time host setup (per machine):**
- Add your user to the `kvm` group: `sudo usermod -aG kvm "$USER"` (re-login).
- Passwordless sudo for your user: the bench launches `virtiofsd` via `sudo`
  non-interactively, so sudo must not prompt
  (`echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/90-$USER-nopasswd`).
- Python 3.13 venv: `fire` still does `import pipes` (removed in 3.13); patch it with
  `sed -i 's/^import pipes/import shlex as pipes/' py313/.../site-packages/fire/{core,trace}.py`.
- Secure Boot off (unsigned demeterhost kernel), and the host kernel installed via
  `installkernel` + `update-initramfs -c -k 6.10.0-demeterhost` + `update-grub`.

**Per-boot (automated):** `source script/setup-host.sh` handles netfilter modules,
swapoff, sysctls, CPU-freq lock, CXL->system-ram, the virtiofsd secure_path
symlink, the bridge (`network.bash`), and the fd ulimit. `script/functionality-test.sh`
runs the README smoke test.

## Not included in this repo (fetched by the build)

- Base kernel trees (vanilla Linux 6.10 for Demeter, 5.15.162 for the
  baselines) — downloaded by `make -f kernel.mk`.
- Toolchains, built kernels, binaries — produced by the build (`toolchain/`,
  `build/`, `bin/`).
- The evaluation VM disk image (`root.img*`) — separate Zenodo download.

See `README.md` for the original build/run instructions.
