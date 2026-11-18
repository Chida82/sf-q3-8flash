# Proposal

## Why

`190`'s uncached reads (and `195`'s, if it makes them a real mode under
memory pressure) cannot read an expert straight into its cache slot: the
kernel bypasses the file cache only for page-aligned file offsets, lengths
and destinations, and expert rows start on 32-byte boundaries in the GGUF.
So each read fills a per-thread page-aligned bounce buffer with the
enclosing pages and copies the expert out (`ds4_gpu_stream_expert_pread_uncached`).
On Q4 that is a 2.59 MiB copy per missed expert on the path the GPU waits
for, plus up to two extra pages read per tensor.

A slot can instead receive the enclosing pages directly: if each slot keeps
one page of slack before and after the expert, the read lands page-aligned
and the expert's GPU address is the slot's address plus the offset of the
expert within its first page (a multiple of 32, which every kernel already
accepts through the cache's address table).

## What Changes

- **Step 0.** With a scratch timer around the copy, at 54 GiB capped and
  RAM taken: the copy's share of each miss layer's wait and of decode.
  Close if under 1% of decode, or if `195` keeps buffered reads as the only
  production mode (then this serves the bench alone and is not worth it).
- **S1.** Uncached reads go straight into slots sized with one page of slack
  on each side; the address table points at the expert inside. Owned
  staging buffers keep the bounce path.

Output does not change: the same bytes at the addresses the kernels read.

## Impact

- `ds4_metal.m` (slab slot size and the address of an entry, the uncached
  read), `tests/test_qwen4_ssd_experts.c`, the memory plan (slots grow by
  two pages: 32 KiB of 2.59 MiB on Q4, 1.2%).
- Starts after `195` decides whether uncached reads are a production mode.
