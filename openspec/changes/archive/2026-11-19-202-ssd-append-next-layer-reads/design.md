# Design

## Decisions

### D1. Step 0

Scratch counters on `main`, the `198` shapes, 54 GiB capped, uncached, one
run per cell: per layer call of an append, the GPU time of the layer (from
command buffer spans), the read wall of its misses, and the set of uncached
experts of the next layer at the time this layer's experts are bound. The
ceiling per append is the sum over layers of min(read of l+1, GPU of l),
less the time to read experts the next layer does not route.

### D2. Which reads

All uncached experts of the next layer when the chunk has at least N rows
(N from step 0: where the routed share of a layer passes about 90%);
none below. The eviction for early reads takes the ordinary victim order and
never takes an entry this layer routes.

### D3. Keep rule

The `198` append shapes at 54 GiB (3 runs per cell), then 48 and 60: time
to first token of every append size at or below `main` (median of runs,
no cell more than 2% slower), at least one size 10% faster; the capped
decode kinds (`ab_bench.py`, capped, uncached) with no decode CI wholly
below zero. A loss confined to the first prefill of a fresh process does
not drop it.

## Risks / Trade-offs

- Reads that the next layer does not use evict entries a later decode
  wanted. D3's decode kinds measure it.
- The read pool is shared with the current layer's down reads; an early
  read must not delay them. Early reads start after this layer's loads.
