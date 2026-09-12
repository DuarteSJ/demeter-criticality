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

Goal: bring **performance-criticality** (PACT-style) into Demeter's
guest-delegated tiering, in place of its frequency-based hotness.

- **Within-VM metric:** replace Demeter's frequency+recency range ranking
  (`rt_rank_cmp` in `mm/demeter/core.c`) with a per-page criticality score
  (PACT's `PAC = k * misses_slow / MLP`, with a core-PMU / in-guest MLP
  estimate via Little's Law), so promotion is criticality-driven.
- **Cross-VM provisioning (later):** a criticality-aware policy for the host
  balloon (Demeter leaves the provisioning policy open), using each VM's
  aggregate slow-tier stall to size its fast-tier budget.

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
