# Proposal

## Why

`198` measured a 64-token append at 54 GiB (Q4, capped, RAM taken) at 437
ms on an 8K context against 165 resident, 435 against 189 on 32K. Its
expert reads are only a quarter of that (105-122 ms). Two other parts are
as large:

- the GPU works 67-85 ms longer than resident (241 against 156 ms on 8K):
  the streamed expert kernels at 64 rows, through the cache's address
  tables, cost more than the resident ones;
- the GPU is idle for 80-90 ms that no read explains: about 1.8 ms per
  layer for the per-layer stop of a multi-row call (drain, the router's
  ids and expert lists read back and validated on the CPU, the encode of
  the expert pass).

Together that is a third of a short append. Short appends (a tool result,
a short user turn) are the commonest request of an agent; at 256 tokens and
up these parts fall under 5% and the reads dominate (`202`).

## What Changes

- **Step 0.** At 64 and 256 tokens on 8K and 32K, 54 GiB: the per-layer
  GPU time of the streamed expert pass against resident (`DS4_QWEN4_TIMING`
  groups or command buffer spans), and the CPU time of each part of the
  per-layer stop. Close if neither part can be cut by 10% of a 64-token
  append's time.
- **S1, the kernels**: if the streamed expert pass is the extra GPU time,
  pick the resident kernel family for small multi-row calls (the address
  table only changes where a weight is read from).
- **S2, the stop**: if the CPU stop is the idle time, cut what it does per
  layer (the list validation reads every routed expert's list back; the
  counts alone bound what the kernels address).

Output does not change: the same arithmetic on the same bytes (S1 must be
bitwise against the current streamed path, or equal to resident).

## Impact

- `ds4_metal.m` (the streamed MM path for small row counts),
  `docs/SSD_STREAMING.md`.
