# Proposal

## Why

Decode is limited by memory bandwidth, and most bytes are not in the experts.
From the Q4 GGUF tensor table, a token reads about 6.6 GB:

- about 3.5 GB (53%) are Q8_0 dense projections;
- about 1.26 GB (19%) are F16 hyper-connection weights;
- about 1.30 GB (20%) are routed experts.

Two kernels leave bandwidth unused:

- **Q8_0 matvec** (`kernel_mul_mv_q8_0_f32`) runs 2 rows per threadgroup on M5.
  A single decode token reaches it through
  `ds4_gpu_qwen4_matmul_q8_0_tensor` -> `ds4_gpu_matmul_q8_0_legacy_tensor`,
  with NSG 4 and no M5 special case. With K=2560 each lane runs about 2.5
  iterations, so the reduction epilogue is a large share of each threadgroup's
  life. Activation loads outnumber weight loads about 2:1 and compete for the
  load slots that should keep DRAM weight requests in flight.
- **HC gate-mix** recomputes `sigmoid(l/hc)` per element (about 3.3M per call),
  although only 320 distinct values exist (the low-rank width). On M5, a single
  token takes the register-prefetch kernel (`..._F16_PF`); two MTP verify rows
  take the pair kernel, which already shares the activated inputs.

## What Changes

From #1056 (open, head `b1af94b`), in this order, each step measured against
the previous one:

1. `a50fecc` + `04c0867`, one step: the Q8 matvec loads activations as
   `packed_float4`, and a Q8-only reduction drops one shared-memory clear and
   one barrier. The eight-term dot loop stays as it is: `04c0867` reverts the
   `char2` pairing that changed rounding under fast math.
2. `9bff1ca`: a four-row variant for the 2560->6144/10240/12288 and 6144->2560
   shapes. Each activation load serves four rows, and there are half as many
   threadgroups. Upstream gates it to M1 Max; this change gates it to M5,
   provided the A/B shows a gain.
3. HC reuse, the HC part of `cdfc0d5`: the kernel computes the 320
   (x, sigmoid) pairs once per threadgroup and reuses them. Its F16 op order is
   pinned as in `028b43f`, so it stays byte-identical to the current kernels.
   It is used for one token on M5 only if it beats the `_PF` kernel.

The PR's two Metal oracles (`test_metal_q8_reduction.m`,
`test_metal_q8_gemv_reference.m`) and its four-row dispatch test come along.
A trial port on a scratch clone:

- applies steps 1-2 with conflicts only in the Makefile and in code the child
  no longer has;
- builds without warnings and passes `make test-qwen4-kernels`;
- runs both oracles on this M5 Max with **0 bit differences** (1024 fixtures,
  571,136 values, two- and four-row variants, default and safe math).

Dropped:

- `bbbc012`: its HC-down tile is for prefill (T 8-128) on M1 Max only, and the
  16-SIMD-group pair default it extends is already in the child for M3 Ultra.
  The same default on M5 costs one line and is measured as step 4, optional.
- `028b43f`, apart from the op order the reuse kernel needs: its M6 gate does
  not matter here. Its rewrite of the generic HC kernels would change code the
  child's tests already pin as bitwise equal on M5.

Estimates on M5 [inferred]:

| Step | Plain decode |
|---|---|
| 1 | 0-1.5% |
| 2 | +2-7% |
| 3 | 0-3% |

Claimed on M1 Max: Q8 kernel +11.6-28.7% in isolation, +0.34% end to end on
SSD decode; HC mixer 36.6 -> 17.6 µs per call.

## Capabilities

### New Capabilities
None. Outputs must stay bit-identical to the current kernels, so observable
behavior does not change (`skip_specs: true`). The harness's `--bitwise` gate
on every kind is the check.

### Modified Capabilities
None.

## Impact

- `metal/dense.metal` (Q8 matvec and reduction), the HC gate-mix kernels in
  `metal/qwen4.metal`, and kernel selection in `ds4_metal.m`.
- Tests: two standalone Metal oracles (about 1,000 lines, trimmed to what covers
  these kernels), the four-row dispatch case in `tests/test_qwen4_kernels.c`,
  and Makefile targets for them.
- About 150 lines of kernel and host code.
- No format or API change.
- Sync: `dense.metal` is shared with upstream. If #1056 lands, the Q8 kernel
  merges cleanly or conflicts once; the registry names the child commits.
