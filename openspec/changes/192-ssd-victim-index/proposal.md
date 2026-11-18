# Proposal

## Why

When the streamed expert cache is full, every load picks its victim by
scanning every entry of every layer (`ds4_gpu_stream_expert_cache_take_reusable`
and the batch planners beside it in `ds4_metal.m`): 40,960 entries per
scan, whatever the cache size, so the cost is paid per missing layer call
and grows with how often the cache misses, not with how big it is.

In `190`'s step 0 (Q4, capped at 40% of the experts, close to the 54 GiB
development footprint, plain decode on code, 8192-token context and 512
generated tokens) the stream timing summary counts 12,259 scans at 0.054 ms
each, 663 ms in a run whose decode lasted about 22 s: up to 3% of the run,
on the CPU path that the GPU waits for. `188` measured 0.030 ms per scan at
a smaller cache and left a scratch patch that keeps a per-layer stamp of the
lowest rank (`scratch/188-eviction-replay:scratch-188/rank-per-layer-stamp.patch`,
unmeasured).

sf-ds4-1flash closed the same idea (`110`, a 722-line upstream index) because
its scan was 0.05 ms against a 0.7% share of a token. Here the share is
larger, for a reason that holds only in the capped condition: a 54 GiB
footprint misses on about a third of the layer calls, and each miss layer
pays a scan.

## What Changes

- **Step 0.** Measure the scan's share of decode at 48, 54 and 60 GiB in
  `190`'s bench (the summary already prints it), plain and MTP. Close if the
  share is under 1% at 54 GiB.
- **S1.** Keep, per layer, the minimum victim rank and its expert, updated
  where an entry's rank or state changes (load, hit, decay, in-flight,
  protection), so a victim search visits the layers' minima instead of every
  entry. The order stays exactly the current one: the lowest rank, then the
  least recently used, protected and in-flight entries skipped, the
  last-pass rule of `188` included. Ties resolve as today.
- One kill switch for the A/B, removed at closing unless measured otherwise.

Output does not change: the same victims in the same order. A model-less
test compares the indexed choice with the full scan over a random
sequence of loads, hits, decays and protections.

## Impact

- `ds4_metal.m` (the cache's victim functions and every writer of an
  entry's rank), `tests/test_qwen4_ssd_experts.c`.
- Starts after `190`. Independent of `191`, but measured against whatever
  of it has landed.
