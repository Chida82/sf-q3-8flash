# Proposal

## Why

Decode is limited by memory bandwidth, and most bytes are not in the experts.
From the Q4 GGUF tensor table, a token reads about 6.6 GB:
- about 3.5 GB (53%) are Q8_0 dense projections;
- about 1.26 GB (19%) are F16 hyper-connection weights;
- about 1.30 GB (20%) are routed experts.

Two kernels leave bandwidth unused:

- **Q8_0 matvec** (`kernel_mul_mv_q8_0_f32`) runs 2 rows per threadgroup on M5.
  The fused pair path is M3-Ultra-only. With K=2560 each lane runs about 2.5
  iterations, so the reduction epilogue is a large share of each threadgroup's
  life. Activation loads outnumber weight loads about 2:1 and compete for the
  load slots that should keep DRAM weight requests in flight.
- **HC gate-mix** recomputes `sigmoid(l/hc)` per element (about 3.3M per call),
  although only 320 distinct values exist (the low-rank width).

## What Changes

From #1056 (open, head `b1af94b`):

1. `a50fecc` + `04c0867`: the Q8 matvec loads activations as `float4`, and the
   reduction drops one shared-memory clear and one barrier. Applies cleanly.
2. `9bff1ca`: 4 output rows per group for the 2560->6144/10240/12288 and
   6144->2560 shapes. Each activation load serves 4 rows and there are half as
   many threadgroups. Upstream enables it only on M1 Max; this change enables it
   on M5 after an A/B.
3. `cdfc0d5`, HC part (plus the 16-SIMD-group part of `bbbc012`): compute the
   320 (x, sigmoid) pairs once per threadgroup in threadgroup memory. Enabled on
   M5 only if it beats the current M5 prefetch kernel.

Carry the PR's Q8 GEMV reference test and re-run it on M5.

Estimates on M5 [inferred]:

| Step | Decode gain |
|---|---|
| 1 | 0-1.5% |
| 2 | +2-7% |
| 3 | 0-3% |

Claimed on M1 Max: Q8 kernel +11.6-28.7%; HC mixer 36.6 -> 17.6 µs per call.

## Capabilities

### New Capabilities
None. Outputs must be bitwise identical to the current kernels, so observable
behavior does not change (`skip_specs: true`). The PR claims bitwise equality,
verified only on M1; `04c0867` shows fast-math code generation can break it, so
the bitwise check on M5 is a task.

### Modified Capabilities
None.

## Impact

- `metal/dense.metal` (Q8 matvec), the HC kernels in `metal/qwen4.metal`, and
  kernel selection in `ds4_metal.m`.
- Tests: the Q8 GEMV reference (the PR ships about 900 lines; keep only what
  covers the shapes above).
- About 150 lines of kernel and host code.
- No format or API change.
