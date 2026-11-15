# Proposal

## Why

The sync to `b3f5018` (`90`) brought #1238's decode path. On Q4 the A/B run
against the old `main` (`ab_bench.py --bitwise`, 18 valid pairs, thermal
Nominal) gave plain decode +4.1% (range +3.8..+4.4%) and left MTP decode where
it was: `mtp-code` 87.3 -> 87.2 t/s, `mtp-prose` 64.6 -> 64.8, the per-cycle
times k1/k2/k3 within 0.4%, tokens per cycle unchanged.

So the gain is in the single-token kernels and the MTP cycle does not use
them. An MTP cycle is a verify of 2 or 3 rows, which `82` runs on its own
row-exact kernels (each row computes exactly as single-token decode), plus
the predictor's drafting. Whatever #1238 made faster in the T=1 path, the
verify rows still do the old way. MTP is the mode the child is built around:
it decodes at 87 t/s on code against 57 plain.

## What Changes

1. **Measure where a cycle goes.** `ab_bench.py --sections` per group on the
   MTP kinds, old `main` against `main`, to see which groups #1238 sped up
   for T=1 and not for the verify rows (expected: the routed-expert mid and
   down passes).
2. **Bring #1238's technique to the verify rows**, group by group, where the
   T=1 kernel's arithmetic can serve 2 or 3 rows unchanged: run the row loop
   inside the faster kernel, or dispatch it per row when the cost per row is
   lower than the multi-row kernel's. `82`'s rule is the gate: verify rows
   byte-exact against single rows (`make test-qwen4-kernels`, "MTP verify
   rows ... byte-exact vs single rows") and `test_qwen4_mtp_identity.py`
   SAME at every depth.
3. **One measured step per group**, kept only on a gain, each with a
   perf-record row.

Non-goals: no change to the draft policy or to output; Q2 effects measured
with the Q2 pack, not assumed.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: bit-identical performance work)

## Impact

- `ds4_metal.m` (verify-row dispatch), `metal/qwen4.metal` and
  `metal/moe.metal` kernels, `tests/test_qwen4_kernels.c`.
- `speed-bench/perf-record.md`.
- Depends on `90`. Independent of `95`; run after it if both touch the same
  MoE pass (`95` step 3).
