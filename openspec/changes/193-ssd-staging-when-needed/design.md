# Design

## Context

`qwen4_streaming_memory_admit` computes `fixed = statics + vision + graph +
staging + 2 GiB` and gives the cache the rest of the budget, capped by the
request. The owned-buffer path allocates its buffers per call with
`newBufferWithLength`, so the reserve is plan headroom, not memory held:
removing it changes what the cache may take, not what the path allocates.

## Decisions

### D1. Step 0

A scratch counter at `qwen4_stream_read_selected` and
`qwen4_stream_read_layer`, printed with the timing summary. Runs: Q4 and Q2,
7,326 / 9,701 / 12,076 slots on Q4 and the slots of the same footprints on
Q2, plain and MTP kinds, uncached reads. Expected: zero on Q4 everywhere;
on Q2 only the MTP layer. If Q4 reaches it, the change closes with the
count and the reason.

### D2. The rule

Staging is reserved when `cache slots < DS4_N_EXPERT` (one call can select
every expert of a layer) or when any streamed layer's expert bytes differ
from the trunk's (then sized for that layer alone, a compact window, as
today). A request in slots is checked against the plan after the change;
a request in bytes keeps meaning "cache plus staging", with staging now
possibly zero.

### D3. Safety

Memory: the owned path still allocates on demand; reaching it without a
reserve means the process can exceed its plan by that call's buffers. D1
says whether it can happen at the targeted sizes; a test with a cache under
512 slots checks that the reserve comes back.

### D4. Keep rule

The same footprint, before and after: at 54 GiB in `190`'s bench, capped,
RAM taken, three kinds, at least 8 pairs. Kept when decode of an MTP kind
has a pooled CI above zero and no metric's CI lies wholly below zero;
confirmed at 48 and 60 GiB. The planned total and the peak footprint are
recorded on both sides: the planned total must not grow.

## Risks / Trade-offs

- A future caller that streams a layer of another size on Q4 would find no
  reserve. The plan line names the rule, and D2 reserves for any off-size
  streamed layer it can see at open.
