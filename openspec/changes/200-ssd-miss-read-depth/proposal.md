# Proposal

## Why

A decode miss is read by the stream read pool as one `pread` per expert
tensor (gate, up, down), on at most 9 threads
(`ds4_gpu_stream_expert_pread_thread_limit`, `DS4_METAL_STREAMING_EXPERT_PREAD_THREADS`,
capped at 18). On Q4 an expert is 2.59 MiB, so a decode layer that misses
1.5-1.9 experts (`190` step 0 at 40% of the experts) issues 4-6 reads of
about 0.86 MiB: a queue depth of 4-6 on a drive that reaches its bandwidth
only at much higher depth. In the capped, RAM-taken condition a load
waited 1.04 ms on average (plain decode on code, 40% of the experts), while
sf-ds4-1flash measured this Mac's internal SSD at 12.8-13.7 GB/s for
random 1-4 MiB reads at 4 threads and at 12.3 GB/s for 48 pieces of 816 KiB on 18
threads (its `docs/ssd.md`): 2.6-4.9 MiB is 0.2-0.4 ms of transfer.

sf-ds4-1flash took +16% decode from splitting each expert read into four
16 KiB-aligned pieces on its pool (`40`, upstream #621 `8f5a7458`), and later
found a split neutral on a different path (`260` S1a). Here the miss is the
dominant wait only in the owner's condition, where nothing serves it from
memory; that is why the question is open now.

## What Changes

- **Step 0.** At 54 GiB, capped and RAM taken, plain and MTP: the pool at
  9 and 18 threads (environment only), and a scratch split of each tensor
  read into 2, 4 and 8 page-aligned pieces. Per run: load wait, decode
  rate. Close if no setting improves decode by 2% (pooled CI above zero).
- **S1.** The chosen depth: a default thread count, a split, or both,
  applied to row-path misses; prefill keeps its own settings unless the
  table shows the same gain there.

Output does not change: the same bytes reach the same buffers.

## Impact

- `ds4_metal.m` (the read pool and its task split), `docs/SSD_STREAMING.md`.
- Starts after `190`. Interacts with `194` (read-ahead adds reads to the same
  pool) and `195` (the read mode); measured against what has landed.
