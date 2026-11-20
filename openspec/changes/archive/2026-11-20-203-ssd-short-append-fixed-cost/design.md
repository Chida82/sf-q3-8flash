# Design

## Decisions

### D1. Step 0

On `main`, the `198` shapes at 64 and 256 tokens, 54 GiB capped, uncached,
3 runs per cell: GPU time per layer of the expert pass, streamed and
resident; and a scratch timer per part of the streamed call's CPU stop
(synchronize, ids read, list read and validation, cache lookup, encode).

### D2. Which step

S1 is built if the extra GPU time is in the expert pass and a resident
kernel can serve the cache's addresses; S2 if the stop's CPU parts other
than the drain exceed 0.5 ms per layer. Both if both.

### D3. Keep rule

The `198` appends at 54 GiB, 3 runs per cell: the 64-token append 10%
faster on both contexts, no other size slower by more than 2%; the capped
decode kinds with no decode CI wholly below zero.

## Risks / Trade-offs

- The list validation guards the kernels against stale or truncated lists
  (a trust boundary between GPU output and cache addressing). S2 keeps a
  check that bounds every address the kernels read.
