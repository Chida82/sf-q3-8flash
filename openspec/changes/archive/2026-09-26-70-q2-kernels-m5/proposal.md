# Proposal

## Why

On the M5, the Q2 pack (`Qwen3.8-Flash-Next-Q2.gguf`, about 42 GiB resident, so
it fits a 64 GB Mac) still runs generic kernels for its experts:

- **Types.** IQ2_XXS gate/up (type 16) and padded Q2_K down (type 10, 640 of 768
  columns) in blocks 0-47. The shared expert is Q8_0. The MTP layer (block 48)
  is Q4_K/MXFP4 even in this pack.
- **Decode (T ≤ 8).**
  - IQ2 gate/up runs `kernel_qwen4_moe_mid`: two rows per SIMD group, and one
    `qwen4_row_dot` per row and projection, so the activations are loaded four
    times per block.
  - Q2_K down runs the generic `kernel_qwen4_moe_down`.
  - The function-constant specialization that removes the row dot's run-time
    type switch is gated to the M3 Ultra.
  - #1056 has dedicated IQ2 and Q2_K decode kernels (`cdfc0d5`, `13c53d9`,
    `9a8462a`, the Q2_K part of `5cbdb6e`), gated to the M1 Max.
- **Prefill.**
  - The tensor tiles run, but the remainder tails (`qwen4_moe_mm_tails`) are on
    for types 16/10 only on the M3 Ultra.
  - So on the M5 every Q2 remainder runs in a partly empty 64-token tile.
  - `60` measured that cost on Q4: a 64-wide pass over about 10 tokens per
    expert costs 34% more than the 16/8-token tiles.

**The Q4 side**, asked for explicitly. Two of these ideas also apply to the Q4
pack, the target machine's model, and neither is taken yet:
- **Shared Q8 slot in `kernel_qwen4_moe_down_mxfp4_pf`.** With two rows per
  SIMD group, it calls `qwen4_row_dot` once per row, loading the activations
  twice. `9a8462a` loads them once for both rows.
- **MXFP4 tile staging.** It computes `(half)(d * table[q])` per value. The
  exact E8M0×E2M1 half table `ds4_metal_mxfp4_half_lut` (`metal/moe.metal`) is
  already proven byte-exact against that expression for all 4096 (e, q) pairs
  by `make test-mxfp4-metal`.

Most of these steps are worth 0.3-1.5% each, around what the harness resolves
on decode (±1%). The user chose to extend the GPU section-time verdict of `61`
to decode kernel steps too.

## What Changes

In this order (the Q4 steps first, since Q4 is the target machine's model):

1. **S0, tool: decode shapes in the section-time mode.**
   - `ab_bench.py --sections` also reads the profiler's decode lines (T = 1,
     one mean per 50 passes). It judges a `decode` shape with the same
     target/untouched ratio and CI.
   - `openspec/config.yaml` extends the GPU-time rule to decode kernel steps.
   - Validated with an A/A run and with a known effect: `50`'s decode kernel
     steps (MoE mid -5.8%, down -9.4% GPU time).
   - The Q2 pack gets its start row: an A/A run on the segment start `91f225a`.
2. **P1 (Q4, decode): shared Q8 down slot in row pairs.**
   - A helper runs `9a8462a`'s shared-slot loop: blocks outside, both rows
     inside, one activation load.
   - It serves the MXFP4 per-token down kernel now, and the Q2_K kernel of
     step Q4 later.
3. **P2 (Q4, prefill): MXFP4 staging through the exact half table.** The
   `(half)(d * table[q])` of `qwen4_dequant_raw16` becomes one read of
   `ds4_metal_mxfp4_half_lut[e][q]`, with the existing fallback for `e = 0xff`.
4. **Q1 (Q2, prefill): remainder tails for types 16/10 on M5.**
   - A host gate, plus a byte-exact test of the Q2 tensor tiles against the
     32-token tiles, including the padded 640/768 Q2_K down. No test covers
     that today.
5. **Q2 (Q2, decode): the M3 Ultra function-constant specialization for types
   16/10 on M5.** A host gate only.
6. **Q3 (Q2, decode): the IQ2 gate/up kernel of `cdfc0d5`/`13c53d9`.**
   - Each lane's 8 activations are loaded once for both rows and for gate and
     up. There are NR1 and NR2 variants.
   - The shared Q8 slot goes through `qwen4_moe_shared_q8_mid`.
7. **Q4 (Q2, decode): the Q2_K down kernel of `5cbdb6e` + `9a8462a`.**
   - Activations shared by two rows; blocks 0-1 without tail checks, block 2
     only in the lanes that hold columns below 640.
   - The shared slot goes through P1's helper.

Every step must leave the output bitwise identical, for both packs. Upstream's
SSD-slot plumbing (`qwen4_moe_slot`, `slot_mask`, `dispatch_slots`) and M1 Max
gates are not taken: the child has no SSD streaming.

Not taken, with the reason:
- **#864's IQ2 half lookup table.** The bit-identical form must still form the
  product in f32. The half×half form double-rounds: 14% of the 1.5 M cases
  checked differ.
- **`a37fd7f`.** The M5 tensor path already reads the IQ2 header once. Its
  `stage16` branch runs only with `DS4_QWEN4_MOE_MM_NAX=0`.
- **`11811b9`.** The half operands are already in the M5 tensor path (level 2).
- **`496b153`.** Its M5 counterpart is Q1.

Estimates [inferred]:

| Step | Pack | Estimate |
|---|---|---|
| P1 | Q4 | decode +0.2-0.5% |
| P2 | Q4 | prefill moe_down up to a few %, possibly slower (a larger table) |
| Q1 | Q2 | prefill +2-5% at +512 |
| Q2 | Q2 | decode +0.5-1% |
| Q3 | Q2 | decode +1-2% (upstream: IQ2 kernel +6% on M1) |
| Q4 | Q2 | decode +0.5-1% |

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `perf-harness`: the section-time mode also judges a decode shape (the
  profiler's T = 1 lines) for the plain kind.

The kernel steps change no observable behavior: bitwise identical.

## Impact

- `speed-bench/ab_bench.py`, `tests/test_ab_bench.py`,
  `speed-bench/README.md`, `openspec/config.yaml`.
- `metal/qwen4.metal`:
  - the MXFP4 per-token down kernel's shared slot;
  - `qwen4_dequant_raw16` type 39;
  - new IQ2 mid and Q2_K down decode kernels.
- `metal/moe.metal`: the half table is reused, not changed.
- `ds4_metal.m`: kernel names and selection, `qwen4_moe_mm_tails`,
  `qwen4_moe_mv_specialize`.
- `tests/test_qwen4_kernels.c`: byte-exact Q2 tile and decode-kernel cases.
- `docs/upstream-prs.md`: the lines for `cdfc0d5`, `13c53d9`, `9a8462a`,
  `5cbdb6e`, `a37fd7f`, `496b153`, `11811b9` and #864.
- `speed-bench/perf-record.md`: the Q2 start row and the closing rows.
- No format or API change.
