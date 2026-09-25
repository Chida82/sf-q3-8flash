# Proposal

## Why

`60-q4-expert-prefill` left two things behind.

- **A measuring tool the rules now require.** On the prefill metrics the A/B
  harness resolves only a few percent: `60`'s no-op step S0 read prefill 8192
  +3% with a pooled CI wholly above zero. The GPU section times of
  `DS4_QWEN4_TIMING=2` resolved every step. `openspec/config.yaml` now says a
  prefill kernel step whose effect is below the harness's resolution is
  decided on GPU time, and that the first change needing it adds that mode to
  `speed-bench/ab_bench.py`. This is that change.
- **Padding the 64-token tile still pays.** Probes after `60` (its design.md,
  "Follow-ups"), all with identical greedy output:
  - At about 10 tokens per expert, one pass over every expert costs 175 ms at
    tile width 8/16, 182 at 32 and 235 at 64.
  - Giving the narrow tiles the 64-token kernel's 16 KB of threadgroup memory
    moves them only +2.9%: the step from 32 to 64 columns costs width, not
    occupancy.
  - 32-token tiles only are 8-9% slower than the default at 2048 and 8192
    tokens, so full 64-token tiles must stay.

  An expert whose remainder is 33..63 tokens runs one partial 64-token tile
  and pays the whole width. A 48-token tile would take the remainders 33..48.

## What Changes

In this order, from `main` with `60-q4-expert-prefill` landed:

1. **S0, tool: section-time mode in the A/B harness.**
   - `ab_bench.py --sections <groups>` runs the usual A/B schedule with
     `DS4_QWEN4_TIMING=2` set for both builds.
   - It reads the per-chunk GPU times from each run's standard error. Per chunk
     shape it reports the ratio of the named groups' time to the time of the
     other groups in the same chunk, B against A per pair, as a median and a
     bootstrap 95% CI.
   - The token (and `--bitwise` logit) gate is unchanged. Pairs dropped as
     disturbed are left out.
   - The pooling script of `40`-`60` (session scratch) moves into
     `speed-bench/` and learns the same exclusion.
   - Checked with an A/A run (noise floor) and with a known effect (`main`
     before `60` against `60`).
2. **O9: a 48-token half tile for remainders 33..48.** The half (default)
   level of the Q4_K/MXFP4 tensor tiles gets 48-token gate/up and down
   instances, and the remainder rule sends 33..48 to them. Remainders
   49..63 keep the 64-token tile. It is taken only if every output stays
   bitwise identical, which the kernel test asserts. It is kept or dropped by
   the new GPU-time rule, with the harness run once as guard.

Not in scope:
- a narrower tile for the float or compensated levels (env-only accuracy
  options);
- splitting a remainder across two tiles (it would dequantize the weights
  twice);
- the other ideas of `60`'s review (the dead float `mid` store, the MXFP4 ALU
  decode, per-super-block Q4_K unrolling).

Estimates, from `60`'s probes [inferred]: O9 +0.5-0.8% prefill at
2048-token chunks, about +0.3% at 8192, and zero if a 48-wide `matmul2d`
costs what a 64-wide one does.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `perf-harness`: a section-time mode (GPU time per stage group, normalized by
  the untouched groups, with a CI), and pooling of several invocations'
  pairs, excluding dropped ones. O9 changes no observable behavior.

## Impact

- `speed-bench/ab_bench.py`, a new `speed-bench/ab_pool.py`,
  `tests/test_ab_bench.py`, `speed-bench/README.md`.
- `kernel_qwen4_moe_mm_mid_nax_t` and `kernel_qwen4_moe_mm_down_nax_t` in
  `metal/qwen4.metal` (48-token instances, remainder rule, staging guard). The
  tail dispatches in `ds4_gpu_qwen4_moe_mm_mid_tensor` / `_down_tensor` in
  `ds4_metal.m`.
- `tests/test_qwen4_kernels.c`: one tile-test shape with remainders 49..63.
- `docs/upstream-prs.md` (`496b153` line), `speed-bench/perf-record.md`.
- No model format, API or output change.
