# Proposal

## Why

Prefill is compute-bound, and no upstream PR speeds it up for the Q4 model on
M5. On M5 the expert matmuls always use the Metal-4 tensor tiles `_nax64`
(64 rows × 64 tokens, K step 32) with half activations (default level 2,
`qwen4_moe_mm_nax_level`). Three costs remain:

- **Redundant loads.**
  - Q4_K staging loads 16 B of header plus 16 B of quants per 16 values, and
    only 8 B of the quants are live nibbles. Both threads of a row reload the
    same header on all 8 K steps of a super-block.
  - MXFP4 staging issues 17 single-byte loads, duplicated across both threads.
- **Serial staging.** The threadgroup A/B tiles are single-buffered, so each
  K step runs dequant -> store -> barrier -> matmul in sequence. ALU dequant
  never overlaps the tensor units.
- **Padding.** The tile width follows total T, not tokens per expert. With the
  disk KV cache, a typical turn prefills only a new suffix. At 512-2048 new
  tokens an expert receives about 10-40 tokens, so 64- or 32-token tiles can be
  37-70% padding. [inferred: first establish whether this range is
  compute-bound; padding costs little if it is bandwidth-bound]

Every item must leave the prefill output bitwise identical to the current
tiles. An item that cannot is dropped, not tuned toward a tolerance.

## What Changes

In this order:

1. **O5, header held in registers.** Keep the Q4_K header in registers and
   reload it every 8 K steps, and stage MXFP4 with packed word loads. Staging
   bytes drop from about 32 to about 18 per 16 values. Same values reach the
   same tensor op, so bitwise identical.
2. **O6, double-buffered staging.** Two A/B tile buffers per threadgroup: the
   dequant of K step k+1 overlaps the tensor op on step k. The `matmul2d` shape
   (64×64, K 32) and the K order stay as they are, so each tensor op receives
   the same operands in the same sequence. Only the pipelining idea comes from
   #864. Its split into two M=16 `matmul2d`s and the tail cull that depends on
   the split change the tensor-op shape and so the accumulation, and are not
   taken. Costs threadgroup memory (2× the A/B tiles): check occupancy.
3. **O7, tile width by tokens per expert.** Choose 8/16/32/64-token tiles from
   the tokens each expert received, the idea of #1056 `496b153`. Before
   building it:
   - measure compute versus bandwidth at 512 and 2048 tokens;
   - read the remainder-tile logic (function constant 905).

   A different tile width is a different `matmul2d` shape. It is taken only if
   the output stays bitwise identical to the 64-token tiles; otherwise drop.

Not in scope: moving `mm_min` (64 rows, `ds4.c` ~32500). It switches chunks
between the tile GEMM and the per-token kernels, which round differently and so
change greedy output.

Estimates on M5 [inferred]:

| Item | Prefill gain |
|---|---|
| O5 | +1-4%, largest at 512-2048-token chunks |
| O6 | +2-5% at chunks ≥2048 (#864 claims +5-8% on DeepSeek, M5 Max, including the split and cull not taken here) |
| O7 | unknown until measured |

## Capabilities

### New Capabilities
None. Every item is bitwise identical to the current tiles, so observable
behavior does not change (`skip_specs: true`).

### Modified Capabilities
None.

## Impact

- `kernel_qwen4_moe_mm_mid_nax_t` and `kernel_qwen4_moe_mm_down_nax_t`,
  `qwen4_load_raw16` and `qwen4_dequant_raw16` in `metal/qwen4.metal`.
- Tile selection in `ds4_metal.m`; path selection in `ds4.c` (about lines
  32500-32590).
- `20-perf-bench-harness` must report prefill at 512, 2048 and 8192 new tokens,
  and its bit-exact frontier-logits check is the acceptance gate for each item.
- No format or API change.
