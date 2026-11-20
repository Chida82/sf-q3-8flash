# Proposal

## Why

`196` measured the streamed process at the service's allocation (Q4,
`--ctx-alloc 262144 --mtp`, 10,725 slots): 50.1-50.3 GiB held against a
53.44 GiB plan at every context length from 2K to 254K, because about 3.8
GiB of the 20.01 GiB graph reserve is never allocated. At the owner's fixed
footprint (`190`) every GiB the plan holds back is a GiB the expert cache
does not get, and at 54 GiB decode gains about 0.9 t/s per GiB of cache:
up to about +3 t/s.

The reserve is `qwen4_graph_memory_estimate`. Per prefill row it takes the
larger of the graph's own row and an older conservative row, whose
`2 * blocks` term grows with the context (blocks = context / 4) while the
graph allocates `blocks + blocks / 8` per row. The engine admits sessions
and sizes the cache from this estimate; step 0 says which parts are never
allocated.

## What Changes

- **Step 0.** At the service's allocation, with a scratch probe: the
  estimate's parts (KV, indexer, scratch rows, fixed) against what the graph
  allocates and what the Metal scratch grows to over a prefill (half
  operands, Q8 unpacking), and the process footprint at 2K and at the longest
  context. Close if the recoverable share is under 1 GiB.
- **S1.** The estimate plans what is allocated, including the lazily grown
  scratch a long prefill reaches; the cache gets the difference at the same
  planned footprint. The slot counts of the capped footprints (48/54/60 GiB)
  are recomputed.

Output does not change: only the plan's size and the cache's slot count.

## Impact

- `ds4.c` (`qwen4_graph_memory_estimate`), `docs/SSD_STREAMING.md` (memory
  plan, slot table), `AGENTS.md` (capped slot counts).
- The admission of a further session uses the same estimate: it gets
  tighter, never looser than what is allocated.
