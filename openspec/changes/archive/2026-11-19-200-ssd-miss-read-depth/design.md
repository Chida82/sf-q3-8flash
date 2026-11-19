# Design

## Decisions

### D1. Step 0

Thread count needs no code. The split is a scratch patch: each tensor task
becomes N tasks on page boundaries (the uncached path reads whole pages
anyway; the buffered path takes the same boundaries). 3 runs per setting,
`capped-mtp-code` and `capped-plain`, at 9,701 slots; the stream timing
summary's `load_pread_avg` and `pread_ms` beside the decode rate. The RAM-free
condition is run once per winner and reported.

### D2. S1

The smallest change that holds the step 0 gain: if 18 threads alone wins,
only the default changes; a split is added only if it adds a gain of its
own. A split piece never crosses a tensor boundary, so a failed piece
fails its tensor as today.

### D3. Keep rule

`190`'s bench at 54 GiB, then 48 and 60: decode of any kind with a pooled CI
above zero, no metric's CI wholly below zero, prefill included.

## Risks / Trade-offs

- More threads and pieces cost CPU and syscalls; at high depth the host,
  not the drive, became the limit on sf-ds4-1flash (about 250k IOPS). The
  pieces here are hundreds of KiB, far from that.
