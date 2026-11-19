# Design

## Decisions

### D1. The shapes

The bench's `--frontiers` prefills each frontier on top of the previous
one, so one process per context measures a sequence: for the 8K context,
`--frontiers 8192,8256,8512,9536,13632 -n 16` (appends of 64, 256, 1024,
4096); for 32K the same offsets from 32768. Time to first token per append
is its prefill time plus the first decoded token (`gen_first_ms`). 3 runs
per cell; uncached reads with the fixed slots of `190`'s footprints;
resident with the same arguments and no streaming.

### D2. Attribution

With `DS4_METAL_STREAMING_EXPERT_TIMING_SUMMARY=1`: loads, read time,
split layers, per chunk. With `DS4_METAL_CB_TIMES=1` on one run per cell:
GPU time per chunk. The gap to resident is split into read wait (the GPU
idle while a layer's misses load) and the rest.

### D3. What follows

A follow-up proposal is written for a candidate only when its share of the
gap at 54 GiB is at least 10% of an append's time at some size, with the
table. A one-layer-ahead pipeline is judged against the read wait; the
chunk size against the per-chunk fixed cost.

## Risks / Trade-offs

- The bench's sequence is cleaner than a server's: no disk KV reload, no
  tokenization of tool output. The figures bound the engine's part only.
