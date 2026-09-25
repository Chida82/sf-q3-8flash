# Proposal

## Why

The routed and shared experts take about a fifth of the Q4 model's decode time,
and their two kernels run well below the bandwidth the M5 Max reaches on a
plain read. A GPU-time probe on `main` (`7034f14`), taken on a scratch tree
with each kernel in its own command buffer, gave these figures for 127 decode
tokens × 48 layers, output unchanged:

| Kernel (T=1, per layer) | Bytes | GPU time | Rate | At 587 GB/s |
|---|---|---|---|---|
| `kernel_qwen4_moe_mid_q4k_nr1` (10 Q4_K gate/up + shared Q8 slot) | 21.9 MB | 55.0 µs | 399 GB/s | 37.3 µs |
| `kernel_qwen4_moe_down_mxfp4_pf` (10 MXFP4 down + shared Q8 slot) | 10.4 MB | 29.9 µs | 349 GB/s | 17.8 µs |
| output head, Q8 2560×248320 (reference) | 675 MB | 1149.7 µs | 587 GB/s | - |

Together they take 4.1 ms of the 17.9 ms token (22.7%). At the head's rate
they would save at most 1.4 ms per token, 8% of decode time. That is a ceiling,
not an estimate: kernels this small pay ramp-up and tail. `40-dense-decode-kernels`
showed that a bandwidth-bound kernel does not speed up from fewer load
instructions (its four-row Q8 matvec gave +0.3%). These two kernels are not
bandwidth-bound, so load issue and re-reads are where the gap can be:

- **Q4_K gate/up** (`kernel_qwen4_moe_mid_q4k`, 1 row per SIMD group on M5)
  loads the eight activations as scalars and the scales and nibbles byte by
  byte. The decode-batch pass `qwen4_moe_mid_q4k_pass` reads the same bytes as
  words, `uint3` and `float4`, and computes the same values in the same order.
- **MXFP4 down** (`kernel_qwen4_moe_down_mxfp4_pf`, 1 row per SIMD group and 16
  groups on M5) reads each slot's 2.5 KB of float `mid` again for every one of
  its 2560 rows: 6.5 MB of cache traffic per slot for 0.87 MB of weights. The
  grouped pass `qwen4_moe_down_mxfp4_pass` already walks two rows at a time
  against one `mid` load.
- **The shared-expert Q8 slot** of the Q4_K kernel calls `qwen4_row_dot` for
  gate and then for up, so it loads `x` twice.
- **FP4 values** come from a 16-entry constant table, indexed per lane.

## What Changes

Original work in this child, in this order, each step measured against the
previous one with bitwise logits:

0. **S0, GPU section times**: the probe becomes a tool in the tree, for this
   change's steps and for later work on any kernel. It extends
   `DS4_QWEN4_TIMING=2`, which today syncs after each prefill stage group and
   reports wall-clock ms:
   - each group is timed by the GPU time of its command buffers;
   - it also works for decode, with a per-token summary for T <= 8 at exit;
   - it adds three groups: MoE mid and MoE down (per-token path), and the
     output head.

   It is off by default and changes no output.
1. **O2**: the per-token Q4_K gate/up kernel runs the decode-batch pass for one
   token. The pass takes the token's input and output rows instead of an
   expert list. The per-token kernel's own block loop, about 40 lines, goes.
2. **O3**: the per-token MXFP4 down kernel walks its rows in pairs with the
   grouped pass's two-chain body. On M5 the default becomes 2 rows per SIMD
   group. A second measurement compares 16 with 8 SIMD groups.
3. **O4**: the Q4_K kernel's shared Q8 slot loads each activation group once
   for gate and up. The loop is `13c53d9`'s, as a helper that
   `70-q2-kernels-m5` can reuse for the IQ2 kernel.
4. **O8**: the MXFP4 down chain builds each E2M1 value from its code bits
   instead of reading the table. The values are the table's, bit for bit.

Every kernel step keeps the values and the summation order. The existing byte-exact
tests pin each kernel against the one it replaces.

Estimates on M5 [inferred], bounded by the probe:

| Step | Kernel headroom per token | Plain decode |
|---|---|---|
| O2 | mid: at most 0.85 ms | 0 to +2% |
| O3 | down: at most 0.58 ms | 0 to +1.5% |
| O4 | shared slot, about 16% of mid bytes | 0 to +0.3% |
| O8 | down arithmetic | 0 to +1% |

These kernels also run the Q2 model's MTP layer (Q4_K/MXFP4). No Q2 GGUF is on
this machine, so that is not measured.

## Capabilities

### New Capabilities
None. Every step keeps values and summation order, so outputs are bitwise
identical (`skip_specs: true`).

### Modified Capabilities
None.

## Impact

- `metal/qwen4.metal`: the Q4_K per-token mid kernel and the decode-batch pass
  it shares, the MXFP4 per-token down kernel and the grouped pass it shares,
  the shared Q8 slot, the FP4 value decode in the down chain.
- `ds4_metal.m`: the MXFP4 down row count and group count on M5, and the GPU
  time of completed command buffers for S0 (`ds4_gpu.h` declares it).
- `ds4.c`: the `DS4_QWEN4_TIMING=2` stage groups, their cuts in the MoE and
  head, and the decode summary.
- `docs/METAL.md`: one line for `DS4_QWEN4_TIMING=2` next to the other inline
  diagnostics.
- `tests/test_qwen4_kernels.c`: one more production-shape case (T=3) in the
  MXFP4 exactness list. The existing cases already compare against the CPU
  reference at T=1 and 2 and pin every kernel against the one it replaces.
- `docs/upstream-prs.md`: the `13c53d9` line and the #864 summary.
- No format or API change.
