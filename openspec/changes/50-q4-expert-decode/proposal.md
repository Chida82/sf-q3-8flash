# Proposal

## Why

Routed and shared experts are about a quarter of per-token decode bytes, and no
upstream PR optimizes the Q4 expert formats on M5. All expert-kernel work in
#1056 and #864 targets IQ2_XXS/Q2_K. Reading the child's decode kernels shows
the same load-issue waste that work removed for Q2:

- **`kernel_qwen4_moe_mid_q4k`** (gate/up, Q4_K), which M5 runs with 1 row per
  SIMD group, loads activations as 8 scalar floats and scales/quants byte by
  byte. The grouped variant (`qwen4_moe_mid_q4k_pass`) already uses word and
  `float4` loads.
- **`kernel_qwen4_moe_down_mxfp4_pf`** reads about 2.5 KB of float `mid` per
  340-byte weight row (about 7.5:1), and re-reads it for every row. The grouped
  pass already walks 2 rows together.
- **The shared-expert slot** calls `qwen4_row_dot` twice (gate, then up), so it
  reads `x` twice.

## What Changes

Original work in this child. The ideas come from #1056 (`cdfc0d5`, `13c53d9`,
`9a8462a`) and #864:

- **O2**: packed word/`float4` loads in the per-token Q4_K mid kernel, taken
  from the grouped pass.
- **O3**: 2-row MXFP4 down for T=1..3, reusing the grouped kernel's rowa/rowb
  walk. A/B of 8 versus 16 SIMD groups on M5.
- **O4**: fused shared-expert Q8 gate/up (`x` loaded once), the idea of
  `13c53d9`.
- **O8**: build the FP4 E2M1 value's half bits arithmetically instead of reading
  the constant table. The float scale multiply stays.

These also speed up the Q2 model's MTP layer, which is Q4_K/MXFP4.

Estimates on M5 [inferred]:

| Item | Decode gain |
|---|---|
| O2 | +1-2% |
| O3 | +0.5-2% |
| O4 | ≤0.8% |
| O8 | 0-2% |

## Capabilities

### New Capabilities
None. Every item keeps values and summation order, so outputs are bitwise
identical (`skip_specs: true`).

### Modified Capabilities
None.

## Impact

- Decode kernels in `metal/qwen4.metal` and their selection in `ds4_metal.m`.
- Following the child's correctness rules, each kernel change needs one
  CPU-reference comparison covering its edge sizes: T=1, 2, 3, and the shared
  slot.
- No format or API change.
