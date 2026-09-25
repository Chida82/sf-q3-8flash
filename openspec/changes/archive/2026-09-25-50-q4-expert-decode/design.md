# Design

## Context

See proposal.md for the motivation, the probe figures and the step list. The
change has no spec delta (`skip_specs: true`): every step must leave every
output bit-identical, which the harness checks.

State of the child that shapes the work:

- **Decode path.** For T <= 8, `qwen4_graph_moe` (ds4.c) runs the per-token
  kernels with the shared expert as slot `n_slots`:
  - `ds4_gpu_qwen4_moe_mid_tensor` picks `kernel_qwen4_moe_mid_q4k_nr1` with 4
    SIMD groups on M5 for T <= 2, and for T = 3 on the exact verify path;
  - `ds4_gpu_qwen4_moe_down_tensor` picks `kernel_qwen4_moe_down_mxfp4_pf`
    with function constants: 1 row (`qwen4_moe_mv_rows`) and 16 groups
    (`qwen4_moe_mv_groups`).

  Decode batches (T 9..64) use the grouped kernels. Prefill (T > 64) uses the
  tiled GEMMs. Only T <= 8 changes here: plain decode, and MTP verify and draft
  rows.
- **Code already written for the same arithmetic.**
  - `qwen4_moe_mid_q4k_pass<NR, NJ>` reads a block's header, scales and nibbles
    as `uint`/`uint3`/`uint2` and the activations as `float4`. Its per-pair
    accumulation is the per-token kernel's order, and `test_moe_grouped` pins
    it against the per-token kernel.
  - `qwen4_moe_down_mxfp4_pass<NJ>` runs the pinned MXFP4 chain of the `_pf`
    kernel on two rows at once.

  Both take an expert list and index `x`/`mid`/`part` by `tok * n_slots +
  slot`. The per-token kernels index by `tok * (n_slots + 1) + slot`.
- **Tests that pin each kernel.**
  - `test_q4k_ordered_exact` (default suite): the Q4_K kernel at every NR/NSG
    against the generic `kernel_qwen4_moe_mid`, T 1 and 2, with and without the
    shared Q8 slot, F 640 and 641.
  - `test_moe_types` compares against the CPU double reference (default suite:
    Q4_K T 1 and 2 with Q8 down).
  - Under `DS4_TEST_QWEN4_MV_EXACT` (`make test-qwen4-q2`): the MXFP4 down at
    NR 1/2/4 × NSG 4/8/16 and the prefetched kernel against the plain one, at
    2560/640 T 1 and 2, and 256/672 T 3.
  - `test_moe_grouped`: grouped against per-token.
- **Probe.** `$SCR/c50/probe.patch` (86 lines, scratch only) puts the mid and
  down dispatches of T = 1 and the output head in their own command buffers,
  and prints their mean GPU time. Baseline on `7034f14`: mid 55.0 µs, down 29.9
  µs, head 1149.7 µs. The greedy output is unchanged with the probe. S0 turns
  it into a tool in the tree.
- **Profiling already in the tree.**
  - `DS4_QWEN4_TIMING=2` (`qwen4_graph_forward_tokens`, macro `QWEN4_PROF`) ends the
    command batch after each of six stage groups (ple, hc_attn, gdn, attn,
    hc_ffn, moe), for T > 1 only, and prints wall-clock ms per chunk.
  - `DS4_QWEN4_MOE_PROFILE` does the same inside the MoE for T > 8.
  - `ds4_gpu_wait_command_buffer` reads each command buffer's GPU start and end
    times, but only for `DS4_METAL_CB_TIMES` and `DS4_METAL_GPU_BUSY_PROFILE`.

## Goals / Non-Goals

**Goals:**
- Lower the GPU time of the two per-token expert kernels on M5 with every
  output bit-identical.
- Share code with the decode-batch passes instead of adding a third copy of
  the block walk.
- Measure each step on its own, and keep it only by the rule in D4.
- Leave a GPU-time section profiler in the tree (S0) that later work can point
  at any stage with one cut.

**Non-Goals:**
- The grouped and tiled paths (T > 8), prefill (`60-q4-expert-prefill`), the
  IQ2/Q2_K kernels (`70-q2-kernels-m5`), SSD streaming (`80`).
- Other devices: M3 Ultra keeps its current defaults, and gates this change
  adds name M5.
- The generic `qwen4_row_dot`: other kernels use it and the Q4 model does not
  reach its Q4_K and MXFP4 branches in decode.

## Decisions

### D1. Form of the work, snapshots, landing

- **Branch and snapshots.** Work on `perf/50-q4-expert-decode`. Each kept step
  is a tree snapshot (`git add -A -- . ':!openspec'`, `git write-tree`). A for
  the next A/B is `../sf-q3-8flash-prev` restored to the previous snapshot,
  as in `40-dense-decode-kernels`.
- **Landing.** One signed commit on `main` when the user asks. O4's loop comes
  from `13c53d9`, so its author goes in as `Co-authored-by:` and the commit is
  named in the message.
- **Section times.** From S0 on, `DS4_QWEN4_TIMING=2` on the step's own tree
  gives the per-token GPU time of each group before the step's A/B. The times
  explain an A/B result. They do not decide it (D4).

### D2. The section profiler, and shared passes instead of new kernels

- **S0.** The existing `DS4_QWEN4_TIMING=2` mechanism is extended rather than
  a second one added.
  - `ds4_metal.m` always adds each completed command buffer's GPU span to a
    running total. `DS4_METAL_GPU_BUSY_PROFILE` already keeps one under its
    env. `double ds4_gpu_take_gpu_seconds(void)` (in `ds4_gpu.h`) returns the
    total since its previous call.
  - In `ds4.c`, `QWEN4_PROF` becomes a function over a small state the graph
    carries (`g->prof`, NULL when off), so `qwen4_graph_moe` and the head can
    cut too.
  - A cut ends the batch, adds `ds4_gpu_take_gpu_seconds()` to the group just
    closed, and begins again.
  - The groups are the six existing ones plus `moe_mid`, `moe_down` (cut in
    the per-token path) and `head` (the final mixer and output GEMV).
  - The mode now runs for every T. T > 8 keeps the per-chunk line, in GPU ms.
    T <= 8 accumulates per T and prints, every 50 passes of that T (as the
    `DS4_QWEN4_TIMING=1` line next to it does), the mean GPU µs per pass of
    each group and their sum.
  - Rejected: keeping wall-clock times. They include each cut's commit and wait
    (tens of µs), the same order as a MoE kernel.
  - Rejected: the scratch probe's own buckets and atexit in `ds4_metal.m`,
    which would be a second profiler.
  - `DS4_QWEN4_MOE_PROFILE` (upstream code, T > 8) stays; the final pass decides
    whether to fold it in against the sync cost.
  - Off by default: one static read of `DS4_QWEN4_TIMING`, as today.
- **O2.** `qwen4_moe_mid_q4k_pass` takes the pair indices and their token
  stride instead of the list: a pair p reads `x` row p / stride and writes
  `mid` row p, which holds for both layouts (stride `n_slots` grouped, `n_out`
  per-token).
  - The grouped kernel reads its list into the pair array.
  - `kernel_qwen4_moe_mid_q4k<NR>` calls the pass with NJ 1 and its own
    pair, and loses its own block loop.
  - The shared slot and the invalid-expert branch stay in the kernel.
  - Rejected: a third copy of the word-load loop inside the per-token kernel,
    which adds the same arithmetic in a new shape.
- **O3.** `qwen4_moe_down_mxfp4_pass` takes the pair indices and a `two`
  flag from its caller instead of the list; `mid` and `part` are pair-major
  in both layouts.
  - The grouped kernel reads its list into the pair array; `two` is its
    matrix-end test, as before.
  - `kernel_qwen4_moe_down_mxfp4_pf` walks `row0 .. row0 + nr` two rows at a
    time through it with NJ 1; `two` also stops at `row0 + nr`, so a SIMD
    group never writes its neighbour's row.
  - `qwen4_moe_mv_rows()` takes the weight type and defaults to 2 for MXFP4 on
    M5, still overridden by `DS4_QWEN4_MOE_MV_NR`.
  - The shared Q8 slot keeps the generic row dot.
  - Rejected: a separate `_pf2` kernel next to `_pf`. It would be one more name
    and one more selection path.
- **O3b.** One extra A/B on top of O3 changes only the M5 group count for MXFP4
  from 16 to 8. With two rows per group, 16 groups make 32-row threadgroups
  and 80 per slot.
- **O4.** A helper `qwen4_moe_shared_q8_mid` holds `13c53d9`'s loop: the same
  Q8 lane mapping, block order, four-term expression and final SIMD sums as two
  `qwen4_row_dot` calls, sharing only the `x` loads. It is called from the
  Q4_K kernel's shared branch when `shared_type == 8`. Other types keep the two
  row dots. `70-q2-kernels-m5` reuses the helper for the IQ2 kernel.
- **O8.** `qwen4_e2m1(uint code)` builds the float bits:
  - magnitude codes 2..7 as `((m >> 1) + 126) << 23 | (m & 1) << 22`;
  - code 1 as `0x3F000000`, code 0 as `0`;
  - the sign from bit 3, so code 8 gives `-0.0f` as the table does.

  It replaces the table reads in `QWEN4_MXFP4_PF_ACC_TO`, which both the
  per-token and the grouped down use. The generic row dot keeps the table.

### D3. Correctness per step

- `make -j8` with no warnings.
- `make test -j8`, reading the suite names (AGENTS.md rule 19).
- `make test-qwen4-kernels`: the Q4_K ordered, grouped and CPU-reference cases.
- `make test-qwen4-q2`: the MXFP4 NR/NSG exactness and prefetch-vs-plain
  cases. It runs at every step, not only at the end, because O3 and O8 change
  the down kernels.
- O3 adds `test_moe_types(&arena, 8, 6, 2560, 640, 3, 12u, 39u)` to the
  `DS4_TEST_QWEN4_MV_EXACT` list. That is T = 3 at the production shape, the
  MTP depth-3 verify.
- S0: greedy output with `DS4_QWEN4_TIMING=2` identical to a run without it;
  its `moe_mid`, `moe_down` and `head` means within 5% of the probe baseline
  (2640, 1435 and 1149.7 µs per token, that is 55.0 and 29.9 µs per layer); the
  prefill chunk line still printed.
- Every step: `ab_bench.py --bitwise` on all kinds.
- At the end: `python3 tests/test_qwen4_mtp_limits.py` and the StarForge
  parity oracle.

### D4. Measurement and keep rule

- **A/B.** `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise`, all kinds,
  against the previous kept step. An inconclusive run is repeated once with
  `--budget 600` on the kinds that decide it.
- **Pooling.** The verdict uses the pooled pair ratios of both runs with a
  bootstrap 95% CI (`$SCR/c50/pool.py`, the `40` script).
- **Keep.** The project rule in `openspec/config.yaml`, which is binding:
  - plain decode's pooled CI above 0, however small the gain;
  - or neutral and deleting more lines than it adds. O2 can pass this way,
    since it removes the per-token loop; O3, O4 and O8 cannot;
  - never kept as neutral for a later step's sake;
  - S0 is a tool step: it needs bitwise output and no metric below 0.
- **Section times.** Recorded per step and reported, never used as the keep
  rule.

### D5. Review of the new code

As the project rule requires (`openspec/config.yaml`):

- **Step review.** After each step builds and before its A/B. *Fix now* for
  what would make the step wrong or break a child rule; *refine later* for the
  rest.
- **Final pass.** Over the section profiler, both passes and their helpers,
  the per-token Q4_K and MXFP4 kernels, `qwen4_moe_mv_rows`/`_groups`, the
  shared helper, `qwen4_e2m1` and the added test case. Questions to settle:
  - whether `DS4_QWEN4_MOE_PROFILE` folds into the section cuts (less code)
    or stays (fewer sync conflicts);
  - whether the `_pf` kernel still needs its function-constant `nr` loop, or
    one row pair per SIMD group suffices;
  - whether the grouped kernels' duplicated invalid-expert and ownership
    branches can share the per-token kernel's code;
  - `QWEN4_MXFP4_GROUPED_ROWS`/`_TAIL` are dead on `main` (defined and
    `#undef`'d, never expanded): delete them;
  - whether the comments still match the code: the "Q4_K gate/up input reuse"
    and "prefetched" comments describe loops that D2 moves.
- **Gate.** `--bitwise` against the last kept step, and no decode metric below
  noise. The pass lands in the same squashed commit, and its findings go in
  the report.

### D6. Record, registry, docs

- **Change result.** The closing A/B is `--a <worktree of main> --b .`, plus
  the record row against the Segment 1 start `91f225a`, appended to
  `speed-bench/perf-record.md`. Its B-commit cell reads `this row's commit`.
- **Registry.** In `docs/upstream-prs.md`:
  - the `13c53d9` line records whether `50` took its shared Q8 loop as a
    helper; `70` keeps the IQ2 part;
  - the #864 summary cell, which assigns "FP4 decode" to `50`, gets O8's
    outcome.
- **Docs.** `docs/METAL.md` gets `DS4_QWEN4_TIMING=2` next to the other
  inline diagnostics, with what its summary means. No device-default list
  exists in `docs/` (checked in `40`).

## Risks / Trade-offs

- [The word loads compile to a different fast-math contraction in the
  per-token grid than in the grouped one] → `test_q4k_ordered_exact` and
  `test_moe_grouped` compare bit for bit. On a mismatch, pin the pass's
  expressions with `fp contract(off)` the way the MXFP4 chain is pinned, and
  re-check.
- [Unaligned vector loads] → `float4` reads of `x` need 16-byte alignment:
  `x` rows are 2560 floats and the lane offset is a multiple of 8. `uint2`/
  `uint3` on Q4_K blocks at 144-byte strides are what the grouped pass already
  does on the same tensors.
- [Two chains per SIMD group raise register pressure and lower occupancy] →
  O3b measures 8 against 16 groups. The probe shows the down time directly.
- [An odd last row computes a discarded second chain] → only under an NR
  override or on odd `out_rows`, and no Qwen shape has that (2560 and 256).
- [The ceiling is small] → the whole change is bounded by 1.4 ms per token
  (8%), and each step's share is 0-2%, the size of the harness noise. D4's
  pooled CI and a repeat run exist for that.
- [Section cuts change what they measure] → each cut splits the batch, so a
  group's GPU time excludes overlap with its neighbours, and a profiled run
  decodes at about half speed. It is a diagnostic; the harness never runs with
  it.
- [Measurement time] → six A/B runs (S0, O2, O3, O3b, O4, O8), repeats where
  inconclusive, the refinement, the two closing runs, parity twice, and six
  section-time runs of about 2 minutes: about 2.5 to 3 hours of machine time.
- [Sync] → `metal/qwen4.metal` is shared with upstream, and #1056 edits the
  same Q4_K/MXFP4 kernels for M1 Max. The passes' arithmetic is unchanged, so a
  later merge conflicts on shape, not on numbers.
