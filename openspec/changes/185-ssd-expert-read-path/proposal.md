# Proposal

## Why

Streamed decode is the slow side of `--ssd-streaming`: at emulated 48 GB the
Q2 pack decodes at 26.9 t/s plain against 47-49 resident, while streamed
prefill is close to resident (`docs/SSD_STREAMING.md`). Two things in the
read path cost time or memory on every missed expert:

- Expert bytes are read with `pread` on the main model descriptor
  (`ds4_metal.m:12146`), a buffered descriptor. Every expert that enters the
  cache is therefore held twice for a while: in the owned Metal buffer and in
  the page cache. On a machine that streams because memory is short, the
  second copy is what the kernel then has to reclaim. The n-gram table
  already reads through its own `F_NOCACHE` descriptor (`ds4.c:2340`).
- A layer's missing experts are known only after that layer's router ran and
  its ids were read back (`ds4_gpu_qwen4_moe_stream_tensor`,
  `ds4_metal.m:40144`). The disk read then starts with the GPU waiting.
  `F_RDADVISE` covers the same layer only (`ds4_metal.m:11976`).

Splash 1.7.0 (incoai/splash, Apache-2.0) serves the same model streamed and
documents both remedies: uncached expert reads (it reports 9.3 against
8.1 GB/s with under half the CPU) and read-ahead of the next block's experts,
predicted by running that block's router on the current block's input. Its
figures are for other GGUFs, other Macs and a lossy default configuration, so
none of them is taken as a target here. Only the two ideas are taken, and
each is measured on its own. No Splash code is copied.

Performance under the intake criteria, on the path the owner named as a next
focus.

## What Changes

- **S1, uncached expert reads.** Routed-expert `pread`s go through a second
  descriptor on the GGUF opened with `F_NOCACHE` (and `F_RDAHEAD` off), with
  offsets and lengths widened to the page size where the kernel requires it.
  The same-layer `F_RDADVISE` hint is re-measured against it and removed if
  it no longer pays.
- **S2, next-layer expert read-ahead.** While layer L computes, predict layer
  L+1's routed experts and start reading the ones the cache misses into free
  or evictable slots. Prediction only chooses what to read early; the layer
  still routes on its real input and loads whatever the prediction missed.
- Each step is kept or dropped by its own measurement (design D3).

Output must not change: token ids of a streamed run stay identical to the
resident run, and the resident path is untouched.

## Impact

- `ds4_metal.m` (stream expert cache and its read pool), `ds4.c` (model
  descriptors, engine open), `docs/SSD_STREAMING.md`.
- Starts after `170-ssd-decode-handshake` is landed or dropped: both touch
  the per-layer load sequence, and S2's design depends on which one stands.
- No new flag. Each step gets one `DS4_*` kill switch for the A/B, removed in
  the final pass unless the measurement says the step is machine dependent.
