# Proposal

## Why

Qwen3.8 refuses `--ssd-streaming` at engine open (`ds4.c` about line 38957;
upstream `0aaea5a` has the same check). Only the BF16 n-gram table is disk-only
today. So the Q4 model needs 69.7 GiB resident and the Q2 model about 41.7 GiB,
and machines under 50 GB cannot run Qwen at all. #1056 (open, head `b1af94b`)
adds routed-expert streaming for Qwen.

Low priority, but it is opened now for a second reason. The generic DeepSeek
streaming machinery is still in the child and is unreachable for Qwen:
- `stream_expert_cache`: 795 references in `ds4_metal.m`;
- `ssd_streaming`: 173 references in `ds4.c`.

That makes it an obvious ablation candidate. Whether this change reuses it
decides whether it may be removed, and removal is expensive to undo.

## What Changes

- **First task:** mark the generic streaming and expert-cache code
  `sf-keep: pending qwen-ssd-streaming` so no ablation removes it while this
  change is open.
- **Phase A, foundation.**
  - Port `e37f185`:
    - a (layer, expert) slot cache in owned `MTLBuffer`s, filled by parallel
      `pread`;
    - the row/MM/NAX kernels read per-expert GPU address tables through a
      function constant, so their arithmetic is unchanged;
    - only routed experts stream (63.40 GiB of the Q4 file); dense, shared, HC,
      router, head and embeddings (6.32 GiB) stay mapped.
  - Establish whether it reuses `stream_expert_cache` or builds its own.
  - Lift the Qwen refusal for `ssd_streaming` only, keeping the rest of the
    message's unsupported modes.
- **Phase B, overlap and I/O reduction.** Claims below are M1 Max 32 GB, Q2.

  | Commit | What it does | Claim |
  |---|---|---|
  | `e2b4a47` | a bounded heap picks eviction victims instead of scanning 40,960 entries per miss | scan time -81/-86% |
  | `9e1429b` | staging reserve sized from compact bounds, freeing cache slots | 7371 -> 8212 slots |
  | `d6cbc77` + `81b9ebb` | resident experts computed before and during the reads; address-table snapshots | decode +23-31% with MTP (with `9e1429b` and `e2b4a47`) |
  | `5cbdb6e` (Q4 parts) | two-stage prefill pipeline | prefill +6-11% |
  | `2ba92ab` | grid over active experts only | — |
  | `47ca2eb` | removes the M1 Max gate from `5cbdb6e`'s prefill overlap | — |
  | `85d37ae` | Q2 pack only: stages the selected experts of the Q4 MTP layer instead of the whole layer | 4.55 -> 7.86 t/s |

- **Testing on the 128 GB machine**: `sf-q3-8flash-bench --simulate-used-memory
  <GiB>` locks memory to emulate a smaller Mac, for example 80 GiB locked ≈ a
  48 GB machine.

Minimum RAM [inferred]: about 10 GiB (Q2) or 12 GiB (Q4) plus the expert cache.
On 32-48 GB about 20-45% of the Q4 experts fit in cache.

## Capabilities

### New Capabilities
- `ssd-streaming`: Qwen routed-expert streaming.
  - Output is identical to the resident run.
  - The resident path's performance does not regress.
  - Memory planning and the minimum RAM are documented.

### Modified Capabilities
None. There are no existing specs; the product contract lives in `AGENTS.md`.

## Impact

- Engine-open check in `ds4.c`; the `AGENTS.md` product contract ("engine open
  rejects ... SSD streaming ... for Qwen") and the misleading-name traps section.
- Expert cache in `ds4_metal.m`; Qwen MoE kernels (address tables); CLI, server
  and bench flags; docs.
- The largest change in this set. The refusal message is upstream text, so
  editing it conflicts at every sync until upstream does the same.
- Depends on `20-perf-bench-harness`; phase B follows phase A.
