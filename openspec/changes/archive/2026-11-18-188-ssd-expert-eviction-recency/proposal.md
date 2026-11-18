# Proposal

## Why

Change `185` recorded routing traces of streamed plain decode at emulated
48 GB (192 tokens, 48 layers, prose and code, both packs) and found, as a
side result, that the expert cache throws away what it is about to need:

- 17-29% of cache misses are on an expert that the same layer routed one
  token earlier, and 37-49% on one routed within the last eight tokens.
- Misses per token, of 480 routed experts: 108 (Q2 prose), 257 (Q2 code),
  222 (Q4 prose), 340 (Q4 code).

The cause is the victim order. `ds4_gpu_stream_expert_cache_prune_layer`
(`ds4_metal.m:14119`) evicts the entry with the lowest route hotness and
breaks ties by oldest use. Hotness accumulates over selections and halves
every 16 tokens. An expert loaded for the current token has been selected
once, so it has the lowest hotness in its layer and is the first victim when
the next token needs room, ahead of an expert that was selected many times a
while ago and has not been used since.

Every such miss is a read (from the page cache at this size, from disk on a
smaller machine) and a staged copy with the GPU waiting. Streamed decode is
the slow side of `--ssd-streaming` (30 t/s against 57 resident on Q2), and
the owner named streaming as a next focus.

Performance under the intake criteria.

## What Changes

- The victim scan skips entries used within the last few decode tokens while
  an older candidate exists. Among the remaining candidates the order stays
  lowest hotness, then oldest use.
- The window is chosen by measurement from the traces `185` kept, then
  confirmed with the A/B (design D2).
- The stream timing summary reports how many victims the recency rule
  redirected.

Output must not change: the cache decides which experts are read again, not
what a layer computes. Token ids of a streamed run stay identical to the
resident run, and the resident path is untouched.

Not in this change: the size of the expert cache against the page cache at
small RAM (`185` found the plan leaves the page cache more of the pack than
the Metal cache holds). That changes the memory plan and belongs with `186`;
this change only records the decode rate at three cache sizes below the plan
as input for it.

## Impact

- `ds4_metal.m` (the eviction scan and its counters),
  `tests/test_qwen4_ssd_experts.c`, `docs/SSD_STREAMING.md`.
- The traces and the scoring tools are on the local branch
  `perf/185-ssd-expert-read-path` (`1a4b6fc`, `scratch-185/`).
