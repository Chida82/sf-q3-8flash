# Design

## Decisions

### D1. Step 0

A scratch probe prints the estimate's parts and, from `qwen4_graph_alloc`
and the Metal scratch helpers, what is allocated, at `--ctx-alloc 262144
--mtp` (the service's shape) and at an 8K context. Footprint by
`footprint -p` every second while one process prefills 2K, then the longest
context, as `196` did. The recoverable share is the planned graph reserve
minus the largest of what is allocated and what is resident at any point.

### D2. What the plan keeps

Everything the graph allocates at open, the recurrent state and the
snapshots MTP keeps, the session's host-visible logits, and the largest
lazily grown Metal scratch a prefill chunk reaches (half operands of an
8192-row chunk, Q8 unpacking). The 2 GiB runtime headroom stays as it is.
Nothing is planned that no path allocates.

### D3. Keep rule

The footprint at or under the plan at 2K and at the longest context, with
the new slot count. Capped kinds (`ab_bench.py`, capped, uncached) at 54 GiB:
`main` at today's slots against S1 at the new slots, same planned footprint;
decode CI above zero on an MTP kind and no decode CI wholly below zero; then
48 and 60 GiB the same way. A loss only in the first prefill of a fresh
process (a larger cache locks more slabs) does not drop it.

## Risks / Trade-offs

- An estimate that undercounts lets the process exceed its footprint; the
  footprint check at the longest context is the guard.
- Non-streamed (resident) admission uses the same estimate and gets tighter
  only where it overcounted.
