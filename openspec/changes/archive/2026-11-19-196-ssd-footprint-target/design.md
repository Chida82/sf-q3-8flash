# Design

## Context

`qwen4_streaming_memory_admit` takes `graph_bytes` (KV plus graph buffers
for the allocated context and prefill chunk) as fixed. At `--ctx-alloc
262144 --mtp` it prints 20.01 GiB of graph reserve (KV 8.33, buffers 11.68)
against 8.07 GiB at 8192 tokens. Which of them are touched lazily is not
documented; step 0 measures it.

## Decisions

### D1. Step 0

One bench process per length, MTP, 262,144 allocated, 54 GiB plan, uncached
reads: frontiers at 2K, 16K, 64K, 128K and 256K tokens with a few decoded
tokens; `phys_footprint` (`footprint`, or `task_info`) sampled once a second
and at each frontier. Report the footprint per frontier and its parts
(cache, statics, the rest). The untouched share at each length is the plan
minus the footprint.

### D2. Accounting

The engine tracks the bytes its context buffers hold now: the KV pages up
to the current position (raw and compressed rows), the graph buffers
touched so far (measured by D1 per buffer: those touched at the first
prefill count in full). The check before a chunk adds the chunk's growth.
`footprint = statics + cache + held context + margin`. The margin is D1's
largest per-chunk jump plus 2 GiB.

### D3. Shrink and regrow

Shrink uses `186`'s mechanism (release slots, unlock, free), keeping the
victim order. Regrow happens only between requests, when the context is
reset or truncated, up to the open-time cap.

### D4. Keep rule

The service's configuration (`--ctx 262144 --mtp`, Q4) with
`--ssd-streaming-footprint 54GB` against `--ssd-streaming-cache-experts
9701` (the same 54 GiB by today's plan), `190`'s bench at an 8192-token
context, capped and RAM taken: decode of an MTP kind with a pooled CI above
zero, no metric's CI wholly below zero. A long-context run (128K) shows the
shrink and that the peak footprint stays under 54 GiB.

## Risks / Trade-offs

- A shrink before a chunk costs evictions and later re-reads. D4's long run
  measures it.
- An external tool that reports footprint differently from the engine's
  accounting makes the option look broken; the plan line prints the
  engine's figure, and D1's samples tie the two.
