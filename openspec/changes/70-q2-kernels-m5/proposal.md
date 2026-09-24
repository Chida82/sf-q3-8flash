# Proposal

## Why

The Q2 model (`Qwen3.8-Flash-Next-Q2.gguf`, 147,207,127,040 bytes) is an
"IQ2_XXS imatrix trunk, padded Q2_K down, MTP" pack: about 41.7 GiB resident,
so it fits a 64 GB Mac. On M5 its IQ2_XXS trunk runs the generic
`kernel_qwen4_moe_mid`: a run-time type switch, 2 rows, and gate and up each
reload `x`. The specialized versions are gated to other devices:
- this child's IQ2 specialization is M3-Ultra-only;
- #1056's IQ2/Q2_K kernels (`cdfc0d5`, `13c53d9`, `9a8462a`) are M1-Max-only.

Low priority: the target machine runs Q4.

## What Changes

- Enable the M3 Ultra IQ2 specialization and #1056's M1-Max-gated IQ2/Q2_K
  decode kernels on M5 (Apple10), each after an A/B:
  - `cdfc0d5`, `13c53d9`: 2 rows per SIMD group; 8 activation values loaded once
    for both rows and for gate and up; aligned header loads.
  - `9a8462a` and the Q2_K-down part of `5cbdb6e`: each activation load reused
    for 2 output rows; the padded tail (640 of 768 columns) on half the lanes.
- Port `a37fd7f`, which is device-independent: the IQ2 header is read once per
  16 staged values instead of twice.
- Port #864's idea into the IQ2 branch of `qwen4_mm_stage8` and the tensor-tile
  dequant: a half lookup table pre-scaled by 0.25, with the sign applied by XOR
  on the half bits instead of a float multiply.
- Check `496b153` (8-token tiles) and `11811b9` (half operands) against what the
  M5 tensor path already does. For Q4 both proved already present or not useful;
  confirm for Q2.

Claims:
- #864: prefill +5-8% on DeepSeek, M5 Max.
- `13c53d9`: 173.8 -> 163.9 µs on M1.

Inferred on M5: Q2 prefill +3-8%; decode unknown.

## Capabilities

### New Capabilities
None. The device-gate extensions are bitwise identical per the PR. The
pre-scaled half lookup table is exact if every 0.25·grid value is representable
in half; that is checked first (`skip_specs: true`). If the check fails, the
lookup table is dropped.

### Modified Capabilities
None.

## Impact

- IQ2/Q2_K kernels in `metal/qwen4.metal` and device gates in `ds4_metal.m`.
- Depends on:
  - the Q2 download finishing;
  - `20-perf-bench-harness`;
  - `60-q4-expert-prefill`, which shares the tensor-tile staging code (take it
    first to avoid conflicts).
- No format or API change.
