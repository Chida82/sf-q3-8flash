# Proposal

## Why

`198` measured agent appends under streaming at the owner's footprint (Q4,
54 GiB, capped, RAM taken). From 256 tokens up, an append does the same GPU
work as resident and leaves the GPU idle for 40-55% of its time, about as
long as its expert reads take: +256 on an 8K context 673 ms against 324
resident, 353 ms idle, 402 ms of reads; +4096 4,315 against 2,803, 1,862
idle, 2,068 of reads. Each of the 48 layers reads its missing experts only
once its router has run, and the GPU waits.

A multi-row chunk routes most of a layer's 512 experts (a 256-token chunk
selects 2,560 slots), so which of the next layer's experts it will need is
known with little doubt before its router runs: nearly all of them, and the
cache holds 44% of them at 54 GiB. `194` predicted single decode rows and
lost on wasted reads; a chunk does not have that problem in the same way,
since what it reads early it almost surely uses. sf-ds4-1flash took its
largest prefill gains from the same idea (`60`, `100`).

## What Changes

- **Step 0.** On scratch counters, per append size (64, 256, 1024, 4096 on
  8K and 32K) at 54 GiB: for layer l+1, the share of its missing experts
  that a "read every uncached expert of the next layer" rule would have
  read, the wasted reads, and how long layer l's GPU work runs against the
  time to read l+1's misses. Close if the reads that could overlap a
  layer's GPU work save under 10% of an append's time at every size.
- **S1.** For a multi-row streamed call above a row threshold, start
  reading the next layer's uncached experts (all of them, or the step 0
  rule) into cache slots as soon as this layer's experts are bound, and
  join them at the next layer's load. Slots of experts read early are
  protected like in-flight loads; a read the next layer does not use stays
  in the cache as an ordinary entry.

Output does not change: the same bytes reach the same slots; only when they
are read moves.

## Impact

- `ds4_metal.m` (the streamed batch path, pending loads, victim choice for
  early reads), `tests/test_qwen4_ssd_experts.c`, `docs/SSD_STREAMING.md`.
- Decode rows keep their path (`194`).
