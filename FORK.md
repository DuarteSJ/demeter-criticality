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

## Not included in this repo (fetched by the build)

- Base kernel trees (vanilla Linux 6.10 for Demeter, 5.15.162 for the
  baselines) — downloaded by `make -f kernel.mk`.
- Toolchains, built kernels, binaries — produced by the build (`toolchain/`,
  `build/`, `bin/`).
- The evaluation VM disk image (`root.img*`) — separate Zenodo download.

See `README.md` for the original build/run instructions.
