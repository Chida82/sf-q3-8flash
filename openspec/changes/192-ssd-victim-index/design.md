# Design

## Context

`ds4_gpu_stream_expert_cache_victim_rank` combines route hotness (halved
every 16 passes) with the last-pass stamp of `188` (the high 32 bits mark an
entry used within the last full pass). A victim is the entry with the
lowest rank, then the oldest `last_used`, among reusable, not in flight and
not protected entries. Ranks change on every selection (hotness +1), on
decay (all entries of the cache at once) and when the pass advances (the
stamp ages).

## Decisions

### D1. Step 0

`DS4_METAL_STREAMING_EXPERT_TIMING_SUMMARY=1` prints `reuse_scan_calls`,
`reuse_scan_avg` and `reuse_scan_total`. Run the three `capped-*` kinds at
48, 54 and 60 GiB (3 runs each, by hand) and divide the scan time spent in
decode by decode's wall time. The decode share is the ceiling. Close below
1% at 54 GiB.

### D2. The index

Per layer, the position of its minimum (rank, `last_used`) among entries
that are reusable and not in flight, recomputed lazily: a layer is marked
stale when one of its entries changes, and a search recomputes only stale
layers, then takes the minimum over the 48 (or 49 with MTP) layer minima,
skipping protected entries by falling back to that layer's scan when its
minimum is protected. Decay halves every rank and preserves their order
within a layer, so it does not mark layers stale; the pass stamp's aging
changes ranks in bulk and marks every layer stale once per pass.

This is the shape of `188`'s scratch patch; it is read and reviewed first,
not taken as is.

### D3. Exactness

A model-less test drives the cache through a seeded random sequence (loads,
hits, protection sets, in-flight marks, decays, pass advances) and asserts
after every step that the indexed victim equals the full scan's. Streamed
equals resident on Q4 and Q2, and the victim counters (`evictions`,
`recent_victims`) equal `main`'s on the same run.

### D4. Keep rule

`190`'s bench, capped and RAM taken, 54 GiB, the three kinds, at least 8
pairs: kept when decode of any kind has a pooled CI above zero and no
metric's CI lies wholly below zero; confirmed at 48 and 60 GiB.

## Risks / Trade-offs

- Every writer of a rank must mark its layer stale; a missed writer picks a
  wrong victim silently. D3's random test is the guard, and the switch keeps
  the full scan available for comparison until closing.
