# Design

## Context

A Qwen3.8 trunk layer routes 10 of 512 experts from its FFN input. The
predictor applies layer L+1's router weights to layer L's FFN input, so it
needs no new weights. `185` measured it on traces from a 978-2464-slot cache
(Q4: covered 38% / 36% of misses, wasted reads 0.45 / 0.68 per covered
read, prose / code, top 6). At 54 GiB the cache holds 9,701 slots and a miss
layer misses about 1.5-1.9 experts (`190` step 0), so whole-layer coverage
is closer to per-miss coverage than it was there.

## Decisions

### D1. Step 0

A scratch build records, per decode layer call: the routed ids, the
predictor's top 10 for the next layer, the cache's state, and the call's
read wait. Offline: share of miss layer calls fully covered by top 6 and top
10; their wait; wasted reads per covered call. Projection = covered wait /
decode time, less the predictor's GPU time (measured in the same build).
Close under 3% at 54 GiB, pooled over the four traces.

### D2. Placement of early reads

Early reads go into free slots first, then into victims chosen by the
current order with the next layer's real selection unknown. Two guards: an
early read never evicts an entry routed in the current or the previous pass
(the `188` rule), and early reads are capped per layer (top 6, or the D1
choice). A wasted early read leaves a cached expert that the order treats as
used once.

### D3. Concurrency

Early reads use the existing read pool after the current layer's own misses
are queued, so they never delay a demand read. When layer L+1's real ids
arrive, a predicted read still in flight is waited for if selected and left
to complete otherwise; its slot is protected while in flight, as demand
loads are.

### D4. Keep rule

`190`'s bench, capped and RAM taken, 54 GiB, three kinds, at least 8 pairs.
Kept when decode of an MTP kind has a pooled CI above zero and no metric's
CI lies wholly below zero; confirmed at 48 and 60 GiB; the RAM-free figures
reported (there it may lose, as `185`'s probe did; the owner's condition
decides).

## Risks / Trade-offs

- Wasted reads take slots and bandwidth. D2's guards and the cap bound
  them; D1 measures them before anything is built.
- The predictor costs a 512-wide router product per layer on the GPU, on
  the critical path. D1 measures it; a token-level budget is part of the
  projection.
