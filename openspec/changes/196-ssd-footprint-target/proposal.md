# Proposal

## Why

The owner's second use sets a memory footprint, 48 to 60 GiB for Q4 "the
request's KV included", not a cache size. Today the engine plans the cache
from the worst case: the KV and graph buffers of the whole allocated
context (`--ctx 262144` in the service) are counted at open, and the cache
gets the rest. In `190`'s opens at the service's context, a run that used
2048 of 262,144 tokens peaked about 12 GiB under its plan (41.1 GiB at a
53.4 GiB plan): the context's pages that were never touched.

Most requests use a small part of the context. At 54 GiB those 12 GiB are
about 4,700 slots, half again the cache (`190` step 0: decode on code rises
by about 0.9 tokens/s per GiB in this range). Holding them in the cache
while the context is short, and handing them back as it grows, keeps the
footprint the owner set and puts it to use.

## What Changes

- **Step 0.** The process footprint against the context actually used, at
  the service's allocation (262,144 tokens, MTP): at 2K, 16K, 64K, 128K
  and 256K tokens, which buffers are touched when, and how fast the
  footprint grows per token. Close if the untouched share at typical
  lengths (up to 64K) is under 4 GiB.
- **S1, a footprint option**: `--ssd-streaming-footprint NGB`. At open the
  cache is sized from N minus the memory the context holds at that moment,
  plus a margin for the next chunk. Before each prefill chunk the engine
  checks the footprint it will reach and, if it would pass N, shrinks the
  cache first, with `186`'s shrink. It never grows the cache past the
  plan of an equivalent `--ssd-streaming-cache-experts`, and never below
  `186`'s floor; if the context alone would pass N, the request fails with
  the figures, as admission does today.
- The existing options keep their meaning.

Output does not change: cache contents decide only which experts are
resident.

## Impact

- `ds4.c` (admission, the prefill loop's check), `ds4_metal.m` (shrink,
  from `186`), `ds4_server.c` and `ds4_cli.c` (the option), `sfctl/`'s
  configuration only through `199`, `docs/SSD_STREAMING.md`.
- Builds on `186`'s shrink; starts after `186` and `190`.
