# Design

## Context

See proposal.md for the motivation and the step list. There is no spec delta
(`skip_specs: true`): every step must leave every output bit-identical.

State of the child that shapes the work:

- **Path.** `qwen4_graph_moe` (ds4.c) takes the tile GEMMs for T > 64
  (`mm_min`). `ds4_gpu_qwen4_moe_mm_mid_tensor` / `_down_tensor`
  (ds4_metal.m) pick the tensor tiles when `ds4_gpu_mpp_available()` and
  `qwen4_moe_mm_nax_level` gives a level (default 2: half operands, 64-token
  tiles). With `qwen4_moe_mm_tails(type, 8)` true (M5, Q4_K/MXFP4), function
  constant 905 (`tail_base`) is 64: `_nax64` runs every full 64-token tile and
  every remainder over 32, and `_nax` (32 tokens) a second dispatch for
  remainders of at most 32. The grid is expert-major on M5.
- **Kernels.** `kernel_qwen4_moe_mm_mid_nax_t<NR1, XT, COMP>` and
  `_down_nax_t` in `metal/qwen4.metal`, 128 threads (4 SIMD groups), one
  `matmul2d(NR1, 64, 32)` per K step (two for gate/up, twice more when
  COMP). Thread (ar, aq) stages row ar, 16-value half aq of the 32-block:
  `qwen4_load_raw16` for step k+1 goes to registers while
  `qwen4_dequant_raw16` writes step k; then the B slice is copied, barrier,
  `mm.run`, barrier. Threadgroup memory at NR1 64, half: mid 12 KB (dispatched
  as 16 KB), down 8 KB.
- **Load pattern per thread and K step.**
  - Q4_K: the 16 B super-block header and 16 quant bytes. Groups 2j and 2j+1
    read the same 16 bytes (low and high nibbles), and all 8 groups of a
    super-block read the same header.
  - MXFP4: 17 byte loads (scale and 16 quant bytes, 17-byte stride, so no
    alignment); aq picks the low or high nibbles, so both threads of a row
    load the same bytes.
- **Tests.** `test_moe_mm_tiles_exact(&arena, 39u)` (default suite, T 641,
  4 experts with counts 641/321/320/0) runs levels 1..5 and prints
  `MoE nax=<n> mid|down: ... hash=<h>`, bounded only against the simdgroup
  tiles (2e-3). The counts leave remainders of 1 and 0 only: nothing reaches
  the 64-token kernel's partial tile or a small expert.
- **Harness.** `ab_bench.py` reports `prefill 8192`, `+512`, `+2048` (plain)
  and `prefill 2048` (MTP kinds), and `--bitwise` compares every prefill and
  decode frontier-logits dump. `$SCR/c50/pool.py` pools runs, `--prefill
  <frontier>` for a prefill metric.
- **Profiler.** `DS4_QWEN4_TIMING=2` prints one GPU-ms line per prefill chunk
  with the groups of `50`; for T > 8 the MoE is a single `moe` group.

## Goals / Non-Goals

**Goals:**
- Lower the tile kernels' GPU time on M5 with every output bit-identical, at
  every level (1..6), not only the default.
- One step per idea, each measured and kept by the project rule.

**Non-Goals:**
- `mm_min`, the simdgroup tiles, the per-token and grouped kernels, the dense
  shared-expert GEMMs.
- Low-bit (IQ2/Q2_K, `70`) tuning: the shared `qwen4_raw16` paths for types
  10 and 16 stay byte-for-byte, only their callers' loop may move.
- Other devices: gates added here name M5.

## Decisions

### D1. Form of the work, snapshots, landing

As in `50`: branch `perf/60-q4-expert-prefill`; tree snapshots (`git add -A
-- . ':!openspec'`, `git write-tree`); `../sf-q3-8flash-prev` restored to the
previous kept snapshot as A; `../sf-q3-8flash-start` at `91f225a` for the
record row. One signed commit on `main` when the user asks. #864's pipelining
idea (O6) and #1056 `496b153`'s tile-width idea (O7) name their commits in the
message, with `Co-authored-by:` only for code taken, not for ideas.

### D2. S0: prefill section cuts and a bit pin

- In the tile branch of `qwen4_graph_moe`, `qwen4_prof_cut` after the routed
  mid dispatch (`moe_mid`) and after the routed down dispatch (`moe_down`),
  as the per-token branch already does. The shared-expert GEMMs and the
  reduce stay in `moe`. Off by default through `g->prof`, as today.
- `test_moe_mm_tiles_exact` gains a T parameter and a second call at T 75:
  counts 75/38/37, so remainders 11 (32-token kernel), 38 and 37 (partial
  64-token tile). Its hash lines are the kernel-level pin.
- The pin: `make test-qwen4-kernels | grep 'hash='` on `T_S0` is saved to
  `$SCR/c60/hash-base.txt`; every later step's output must match it line for
  line. This is procedure, not code: the hashes depend on the GPU, so a
  constant in the test would fail on any other Mac. What holds on every
  device, that the tile width does not change a token's bits, the test
  asserts itself (level 2 against level 1, level 4 against level 3; added
  after the review).
- Rejected: an in-test comparison against a copy of the old kernel. It would
  keep a second kernel in the tree for the length of the change.

### D3. O5: fewer staging loads

- **O5a, Q4_K.** In both kernels, for type 12, the thread keeps the header
  `uint4` and the quant `uint4` across K steps and reloads the header when
  `kb % 8 == 0` and the quants when `kb % 2 == 0`; the register prefetch of
  step k+1 keeps that rule. `qwen4_dequant_raw16` is unchanged, so the same
  halves reach the same tile. The loop change is type-local: types 10, 16 and
  39 keep their per-step load.
- **O5b, MXFP4.** `qwen4_load_raw16` for type 39 loads the 5 aligned words
  that cover the 17 bytes (`blk & ~3`, up to 20 bytes read) and extracts the
  bytes with shifts. Each thread still dequantizes its own nibble half.
  The words reach up to 3 bytes past the block, which is still inside the row
  for every block but the row's last; that one keeps the byte loads, so no
  read passes the bound weight buffer and the host is unchanged. Dropped if
  the compiled kernel is not faster (the compiler may already merge the byte
  loads).
- Rejected: splitting a block's bytes between the two threads of a row and
  swapping halves with `simd_shuffle`. The two threads are adjacent lanes, but
  it adds a shuffle per value for a 9-byte saving that L1 mostly absorbs.

### D4. O6: double-buffered A/B tiles

- Two A and two B buffers per threadgroup. Step k's `mm.run` reads buffer
  k % 2 while the threads dequantize step k+1 into buffer (k+1) % 2; one
  barrier per K step instead of two. The `matmul2d` descriptor, K order and
  C accumulation are untouched, so each tensor op sees the same operands in
  the same sequence.
- Threadgroup memory at NR1 64: mid half 24 KB, down half 16 KB; COMP mid
  32 KB, the Apple limit. The host sizes change with the kernel. If COMP mid
  does not fit, the COMP instances keep the single buffer through a template
  parameter rather than a second kernel body.
- Occupancy: 24 KB lets fewer threadgroups share a core. The A/B decides.
  The step also reports `maxTotalThreadsPerThreadgroup` of the pipelines,
  unchanged at 128 or the step is dropped.
- Rejected: #864's split into two M=16 `matmul2d`s and its tail cull: a
  different tensor-op shape, so different accumulation.

### D5. O7: tile width by tokens per expert

- First a probe, no code kept: run the T 641 and T 75 tests with
  `DS4_QWEN4_MOE_TAILS=0` and compare the hashes with the default. Tails off
  sends every remainder through `_nax64` instead of `_nax`, so equal hashes
  show that a 32-token and a 64-token `matmul2d` give the same bits for the
  same token. Unequal hashes: O7 is dropped here, recorded, and ends.
- If equal: add 16- and 8-token instances (`NR1` 16 and 8; `NB` becomes
  fractional at NR1 < 32, so B staging gets a guard `item < NR1 * 4`), and let
  the host pick the width from the chunk's mean tokens per expert
  (`T * n_slots / n_expert`), since counts are GPU-side. Rows still 64.
  Kept only if the pin and `--bitwise` hold.
- Measure first: the S0 cuts at +512 and +2048 give `moe_mid`/`moe_down` GPU
  ms; the weight bytes of one layer's routed experts over that time give the
  achieved bandwidth. Near the device bandwidth, padding is free and O7 stops
  with the numbers recorded.

### D6. Correctness per step

- `make -j8` with no warnings; `make test -j8`, reading the suite names;
  `make test-qwen4-kernels` ending in `all qwen4 kernel tests passed`, and
  its `hash=` lines equal to `$SCR/c60/hash-base.txt`; `make test-qwen4-q2`
  (types 10/16 share the loaders).
- Every step: `ab_bench.py --bitwise` on all kinds.
- At the end: `tests/test_qwen4_mtp_limits.py` and the parity oracle.

### D7. Measurement and keep rule

- A/B against the previous kept step, all kinds; the repeat and pooling as in
  `50`, per prefill metric with `pool.py --prefill <frontier>`.
- Keep by `openspec/config.yaml`. The target is the prefill metrics: kept when
  at least one prefill metric's pooled CI lies above 0 and no throughput
  metric's (prefill or decode) lies wholly below 0. S0 is a tool step.
- Section times on each step's tree are recorded, never the verdict.

### D8. Review

As `openspec/config.yaml` requires: a step review after each step builds,
*fix now* or *refine later*; a final pass over both tile kernels, the two
loaders, the host tile selection and the test change. Questions for it:
whether the single-buffer COMP path (if D4 needed it) can go; whether the
unused levels 1, 3, 4, 6 are worth their instances (their deletion would be a
separate, measured ablation, not a refinement); whether the comments above the
kernels still describe the loop. The refinements are measured like a step and
land in the same squashed commit.

### D9. Record, registry, docs

- Closing A/B against a worktree of `main`, and the record row against
  `91f225a` appended to Segment 1 of `speed-bench/perf-record.md`.
- `docs/upstream-prs.md`: the #864 cell (double-buffered staging: taken or
  measured and dropped), the `496b153` line (O7's outcome), the #1056 summary.
- `docs/METAL.md`: the `DS4_QWEN4_TIMING=2` paragraph names the prefill
  `moe_mid`/`moe_down` split.

## Risks / Trade-offs

- [Held registers raise pressure in a kernel with cooperative tensors] → the
  A/B decides; the section times show the MoE share directly.
- [O5b reads past the tensor end] → the guard in D3; the T 75 test puts an
  expert last with a partial tile.
- [O6 lowers occupancy] → measured; COMP mid at 32 KB may not fit, D4's
  template fallback.
- [O7's bitwise premise fails] → the probe decides before any code.
- [The gains are inside the noise] → prefill pairs are fewer than decode
  pairs; the repeat run with `--budget 600` and pooling exist for that.
- [Measurement time] → S0, O5a, O5b, O6, O7 and the refinement, repeats, the
  closing runs, parity twice: about 3 hours of machine time.
- [Sync] → #1056 edits the same kernels for M1 Max; the loop shape changes
  here, the arithmetic does not, so a merge conflicts on shape, not numbers.

## Follow-ups (probes after the review, not built)

- **A 48-token tile for remainders 33..48.** At about 10 tokens per expert a
  pass costs, per full expert set, 175 ms at width 8/16, 182 at 32 and 235 at
  64 (`DS4_QWEN4_MOE_TAILS=0`), and giving the narrow tails the 64-token
  kernel's 16 KB moves them only +2.9%: the step from 32 to 64 columns costs
  width, not occupancy. Remainders 33..63 still pay it. If a 48-wide pass
  costs midway, the tile saves about 0.5-0.8% of prefill at 2048-token
  chunks and about 0.3% at 8192. Two instances (gate/up and down), one more
  dispatch per matrix, the staging guard generalised to `tid + b * 128 >=
  NR1 * 4`; kept only if the test's level-2-against-level-1 check stays
  byte-exact (T 161 gives remainder 33) and the GPU-time rule of
  `openspec/config.yaml` shows the gain.
