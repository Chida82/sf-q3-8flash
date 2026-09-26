# Design

## Context

See proposal.md for the motivation and the step list. What the work builds on
(`Q` = `metal/qwen4.metal`, `M` = `ds4_metal.m`; line numbers on `main` at
`79f6b42`):

- **The Q2 pack** (GGUF header). Blocks 0-47: gate/up IQ2_XXS (16) `2560 ×
  640 × 512`, down Q2_K (10) `768 × 2560 × 512`, padded (640 of 768 columns
  hold activations). The shared expert is Q8_0 in all 49 blocks. Block 48 (MTP)
  is Q4_K/MXFP4. The file is in the HF cache (`<Q2>` below); `gguf/` has no
  link to it.
- **Decode, T ≤ 8** (`ds4.c` `qwen4_graph_moe`). The shared expert is slot 10
  of the per-token kernels.
  - IQ2 mid: `kernel_qwen4_moe_mid` (Q:2814), NR2/NSG4, one
    `qwen4_row_dot` (IQ2 branch Q:2723) per row and projection.
  - Q2_K down: `kernel_qwen4_moe_down` (Q:3092), NR2/NSG4. Its row dot (Q:2705)
    skips lanes at or past column 640.
  - The shared slot takes the generic Q8 row dot (Q:2651) in both.
  - On M5, `qwen4_moe_mv_specialize` (M:39267) is false for 16/10. It is true
    only on the M3 Ultra, where function constants 901-904 fix type, shared
    type, width and rows, with NR1 and NSG8/16.
- **Decode, T 9..64.** The grouped kernels need Q4_K/MXFP4, so Q2 runs the same
  per-token kernels with the shared expert dense.
- **Prefill.** Tensor tiles at level 2 for 16/10 too (M:40747).
  - `qwen4_moe_mm_tails` (M:40807) is on for 16/10 only on the M3 Ultra, so on
    M5 every Q2 remainder runs in a partial 64-token tile.
  - The IQ2 staging (`qwen4_load_raw16` Q:3553, dequant Q:3624) already reads
    the header once per 16 values.
- **The Q4 targets.**
  - `kernel_qwen4_moe_down_mxfp4_pf` (Q:3221): on M5 two rows per SIMD group.
    Its shared Q8 slot loops `qwen4_row_dot` per row (Q:3243-3248). The routed
    rows already share activations through `qwen4_moe_down_mxfp4_pass`.
  - `qwen4_dequant_raw16` type 39 (Q:3638-3642):
    `(half)(ds4_metal_e8m0_to_f32(e) * ds4_metal_mxfp4_values[q])`.
  - `metal/moe.metal` is compiled before `qwen4.metal` and provides two exact
    replacements. Both are proven by `make test-mxfp4-metal` for all 4096
    (e, q) pairs:
    - `ds4_metal_mxfp4_half_lut_value(e, q)`: the 256×16 half table, falling
      back to the arithmetic for `e = 0xff`;
    - the `dequantize_mxfp4_half_scale` form: half(d)·half(v) for E8M0 in
      103..142, float arithmetic outside.
- **Tests.**
  - `test-qwen4-q2` runs `DS4_TEST_QWEN4_MV_EXACT=1 test_qwen4_kernels`:
    decode kernels against a double reference, plus byte-exact NR/NSG
    geometries for 16/10, including the padded 256/672 shape.
  - It then runs `test_qwen4_moe_mm_specialize`, byte-exact but on the
    simdgroup tiles only (NAX=0).
  - `test_moe_mm_tiles_iq2` (T 641, E=F=256, not padded) only bounds the
    tensor tiles against the simdgroup tiles (2e-3). Nothing checks the M5
    default Q2 tiles byte-exactly, or the padded Q2_K down on tensor tiles.
- **Profiler.** The single-token decode line is
  `ds4: Qwen3.8 T=1 GPU us/pass over 50 passes: <group> <us> ... sum <us>`
  (ds4.c:32877), printed every 50 passes. A plain harness run decodes 64
  tokens at each of 3 frontiers, so it prints 3 lines.

## Goals / Non-Goals

**Goals:**
- A decode section-time verdict, with the same statistic and schedule as the
  prefill one of `61`.
- For each step, a measured verdict under the project rule, with every output
  bit-identical for both packs.

**Non-Goals:**
- SSD streaming (`80`) and upstream's slot plumbing.
- M1 Max or M3 Ultra behavior. Gates added here name M5, and the M3 Ultra
  keeps its gates.
- The float and compensated tile levels (env-only options).

## Decisions

### D1. Form of the work, models, landing

- **Branch and snapshots.** Branch `perf/70-q2-kernels-m5` from `main`,
  snapshots as in `61`.
- **Worktrees.**
  - `../sf-q3-8flash-prev`: the previous kept step, starting at `main`.
  - `../sf-q3-8flash-start`: `91f225a`.
  - `../sf-q3-8flash-known`: `50`'s S0 tree `d5dc38b` (`$SCR/c50/steps.txt`),
    for the decode validation.
- **Models.** `<Q4>` is the default link; `<Q2>` is the absolute HF-cache path.
- **Order.** Every model-backed run (harness, section time, parity, MTP
  limits, CLI probes) runs alone. No build or test runs beside it.
- **Landing.** One signed commit on `main` when asked. Upstream authors of
  ported code (`cdfc0d5`, `13c53d9`, `9a8462a`, `5cbdb6e`) go in as
  `Co-authored-by:` for the steps that are kept.

### D2. S0: decode shape, rule, Q2 start row

- **Parsing.**
  - `DECODE = re.compile(r'^ds4: Qwen3\.8 T=1 GPU us/pass over 50 passes:(.*)$',
    re.M)`.
  - For the plain kind, `parse_sections` also returns `decode`: each group's
    mean over the run's T=1 lines.
  - A plain run without one is a run failure. MTP kinds add no decode shape:
    their passes are verify rows (T ≥ 2).
- **Everything else is shared** with the prefill shapes: `section_table`,
  `sections.csv` (shape `decode`), `ab_pool.py --sections decode <groups>`.
  The README states that the decode shape's time unit is µs per pass.
- **Rule** (`openspec/config.yaml`): "A prefill step that changes kernels" becomes
  "A prefill or decode step that changes kernels". It runs on the harness's
  shapes, which now include decode. The rest stays.
- **Tests**:
  - the T=1 lines parsed into the mean;
  - a plain run without them is a run failure;
  - a 2% `moe_down` decode change reads 0.98.
- **Validation.**
  - (a) A/A on `../sf-q3-8flash-prev` with `<Q4>`. The `decode` CI contains 1;
    its half-width is recorded.
  - (b) Known effect: `../sf-q3-8flash-known` against
    `../sf-q3-8flash-prev`, targets `moe_mid,moe_down`. The expected `decode`
    ratio is about 0.92 (`50` O3 down -9.4%, O4 mid -5.8%).
    - The prefill shapes of this run are not comparable: `50`'s S0 has no
      tiled-path cuts, so they read inconclusive, and exit 3 is expected.
- **Q2 start row.** An A/A on `../sf-q3-8flash-start` with `<Q2>`, appended to
  Segment 1 (the model cell tells it apart).
- **Rejected alternative:** judging decode by the harness only (±1%). The user
  chose the GPU-time rule for decode too.

### D3. P1: shared Q8 down slot in row pairs (Q4)

- **Helper.** `qwen4_moe_shared_q8_rows(sh_down, row0, nr, m, dim, tiisg, part…)`
  with the Q8 lane mapping of `qwen4_row_dot` (ix = lane/8 block stride, it =
  lane%8).
  - The loop is blocks outside, rows inside. Each lane loads its four `y`
    values once per block and adds `d_r * (four-term)` to row r's accumulator.
  - One `simd_sum` per row.
  - Per row, the block order, expression and reduction are those of
    `qwen4_row_dot`, so the result is bit-identical.
- It is called from `kernel_qwen4_moe_down_mxfp4_pf`'s shared branch when
  `st == 8`. Other types keep the row dot.
- **Test.** The existing MV_EXACT cases compare the prefetched kernel with the
  plain one, at T 1/2/3, 2560/640, with the shared slot. They must stay
  byte-exact.
- **Verdict.** Section time, decode shape, target `moe_down`, `<Q4>`.

### D4. P2: MXFP4 staging through an exact half form (Q4)

- **Two variants, measured in turn against the previous kept step.**
  - (a) `dst[i] = ds4_metal_mxfp4_half_lut_value(e, nibble)`: the 8 KB
    constant table.
  - (b) `dequantize_mxfp4_half_scale`'s form: `half dh = (half)d` once per
    block when 103 ≤ e ≤ 142, then `dh * ds4_metal_mxfp4_half_values[q]`; the
    float expression otherwise. The branch is per block, so uniform per thread.
- The better one is kept if it passes the rule; if neither passes, P2 is
  dropped.
- **Bitwise.** Both variants are proven against the current expression by
  `make test-mxfp4-metal`. The tile-test pin and the level-2-against-level-1
  checks must hold.
- **Verdict.** Section time, prefill shapes, target `moe_down`, `<Q4>`.

### D5. Q1: remainder tails for 16/10 on M5 (Q2)

- `qwen4_moe_mm_tails` adds `(type == 16u || type == 10u) &&
  ds4_gpu_device_is_m5_apple_silicon()`. The half-tile tails of `60`, 8 to
  64 tokens, then serve Q2 on M5.
- **Test.** `test_moe_mm_tiles_iq2` gains:
  - the level-2-against-level-1 byte-exact check that `60` added for Q4;
  - a padded shape: F 640 with Q2_K rows of 768 (weight_dim), T 161 for
    remainders 33/17/16 and T 641 for remainder 1.
- **Verdict.** Section time, prefill shapes, targets `moe_mid,moe_down`,
  `<Q2>`, `--bitwise`.

### D6. Q2: decode specialization for 16/10 on M5 (Q2)

- `qwen4_moe_mv_specialize` adds 16/10 on M5. This sets function constants
  901-904 on the generic mid/down kernels, with NR1/NSG8 (16 groups for Q2_K
  on M3 Ultra only).
  - Per-row arithmetic is unchanged; the MV_EXACT geometry cases already pin
    it.
- Measured before Q3/Q4 because it is one line. If Q3 or Q4 is kept, its
  kernel replaces the generic one for that type, and the final pass removes
  the part of this gate that has become dead.
- **Verdict.** Section time, decode shape, targets `moe_mid,moe_down`, `<Q2>`.

### D7. Q3: IQ2 gate/up decode kernel (Q2)

- **Kernel.** `kernel_qwen4_moe_mid_iq2<NR>` (NR 1, 2) from `cdfc0d5` and
  `13c53d9`, without upstream's slot plumbing and M1 gate.
  - Each lane loads its 8 `y` values of a 32-block once and uses them for
    every row and both projections.
  - Per row it keeps `part += grid*±y; acc += dl*part` and the `simd_sum`.
  - The invalid-expert branch is kept, as in the generic kernel.
- **Shared slot.** The shared Q8 slot runs `qwen4_moe_shared_q8_mid` (`50`),
  as in the Q4_K kernel.
- **Selection.** For type 16 on M5: NR1 for T ≤ 2 (the policy `m5_single` uses
  for Q4_K, M:40508), NR2 above.
- **Test.** A byte-exact case against the generic kernel at T 1/2/3, with and
  without the shared slot, F 640 and 641. The double reference also covers it.
- **Bitwise risk.** Different fma contraction when the loads are shared. The
  test decides. On a mismatch the arithmetic is pinned (`fp contract(off)`),
  as the MXFP4 chain is.
- **Verdict.** Section time, decode, target `moe_mid`, `<Q2>`.

### D8. Q4: Q2_K down decode kernel (Q2)

- **Kernel.** `kernel_qwen4_moe_down_q2k` from `5cbdb6e`'s Q2_K part and
  `9a8462a`.
  - NR2 with the activations shared by both rows.
  - Blocks 0-1 without tail checks, block 2 in lanes < 16: exactly the lanes
    the generic `continue` keeps.
  - The shared slot goes through P1's helper.
  - `9a8462a`'s packed loads are taken only where the step review shows the
    same values in the same order.
- **Test.** Byte-exact against the generic kernel at the padded production
  shape (768/640 → 2560) and at 256/672, T 1/2/3, shared slot on.
- **Verdict.** Section time, decode, target `moe_down`, `<Q2>`.

### D9. Correctness, review, closing

- **Every step:**
  - `make -j8` with no warnings;
  - `make test -j8`, reading the suite names;
  - `make test-qwen4-kernels`: every byte-exact line, and every tile-test hash
    equal to `main`'s (checked by running the same test on the `main`
    worktree when a test shape is added);
  - `make test-qwen4-q2`;
  - `make test-mxfp4-metal`;
  - `python3 tests/test_ab_bench.py`.
- **Guard for a kept kernel step.** One throughput harness run, `--bitwise`, on
  the pack it targets: PASS, and no metric's CI wholly below 0
  (`ab_pool.py`).
- **Review.** A step review after each step. The final pass covers P1's
  helper, P2's staging, both new kernels, the host selections and the gates.
  It settles whether Q2's gate is still needed after Q3/Q4.
- **Closing.**
  - Parity oracle with `<Q4>` and with `<Q2>`.
  - `tests/test_qwen4_mtp_limits.py` with both.
  - Closing throughput A/B against `main` with both packs.
  - Record rows against `91f225a` for both packs.
  - `docs/upstream-prs.md`: every line D1 names.

## Risks / Trade-offs

- [A 1-2% decode step is still near the decode section noise floor] → the A/A
  run measures that floor first. An inconclusive run is repeated once and
  pooled.
- [The 8 KB table of P2(a) thrashes the constant cache during tile staging] →
  variant (b) needs only 32 bytes, and both are measured.
- [Q1's tails on Q2 cost an extra dispatch at shapes without remainders, as
  `61` found for the 48-token tile] → the tails are one mechanism with `60`'s
  Q4 tails, and the section time decides.
- [Upstream's kernels assume their SSD slot layout] → the port keeps only the
  arithmetic, and the byte-exact tests compare against the generic kernels.
- [Two packs double the measurement time] → Q4 steps first. Every model run is
  sequential: about 4-5 hours of machine time in all.
- [Sync] → #1056 edits the same kernels. The ported kernels carry its
  arithmetic, so a later merge conflicts on shape, not numbers.
