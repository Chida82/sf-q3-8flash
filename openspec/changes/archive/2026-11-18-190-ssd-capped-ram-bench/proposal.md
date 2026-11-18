# Proposal

## Why

SSD streaming has two uses, named by the owner on 2026-11-18:

1. **A smaller Mac**, 48 GB.
2. **This Mac, with the model held to a fixed share of its RAM**: Q4 at a
   footprint of 48 to 60 GiB, the request's KV included, while other work
   holds the rest. Development targets this one, and it assumes the rest of
   the RAM is taken: an expert that is not in the cache is read from the SSD.
   What the same footprint gives when nothing else runs is extra information.

Every streaming decision so far (`170`, `185`, `188`, the tables in
`docs/SSD_STREAMING.md`) was measured in one condition, emulated 48 GB:
`--simulate-used-memory` with an 80 GiB lock. That condition models neither
use:

- The lock takes most of the host's user wire limit (108.8 GiB), and the plan
  stays inside what is left of it (`qwen4_streaming_memory_admit`). At
  "48 GB" the plan is 19.5 GiB, where a 48 GB Mac would plan about 36 to 40.
  The expert cache comes out at 2.5 GiB on Q4 (4% of the routed experts) and
  3.4 GiB on Q2 (10%).
- The RAM the plan does not take, about 25 GiB, becomes file cache, and the
  file cache holds the experts the small cache evicts. It is the real expert
  cache of that condition.
- Lowering the lock does not help: for an emulated size X the plan is always
  about 20 GiB under the real one and about 25 GiB of file cache is left
  (design D2).

The measurements agree with this reading. A quarter of the cache cost Q2
decode 8.5% (`188`); reads that bypass the file cache cost 33% on Q2 and 41%
on Q4 (`185`); and at 2% to 10% of the experts fewer than 3% of the layer
calls find all their experts cached (step 0 below). sf-ds4-1flash, whose
streaming lessons this child wants to reuse, measures at a fixed 80-82 GB
cache that holds 53% of the experts with 92% of the layers all cached: the
regime of use 2, not the one measured here.

One more observation from 2026-11-18. With a virtual machine running, four
buffered streamed runs took free memory from 10.8 to 0.1 GiB in two seconds
each and pushed about 23 GiB of the VM into the compressor, until the memory
guard stopped the series. Buffered expert reads fill the file cache at the
drive's rate, and the neighbour pays.

## What Changes

- **A measurement switch for uncached expert reads.**
  `DS4_METAL_STREAM_EXPERT_UNCACHED_READS=1` reads routed experts past the
  file cache (the page-aligned reads `185` wrote and measured). It models
  "the rest of the RAM is taken" without locking any memory. The default
  stays buffered.
- **The capped-RAM bench condition.** No memory lock; the expert cache fixed
  with `--ssd-streaming-cache-experts` from the target footprint; uncached
  reads; long decodes with MTP, the service's configuration. Three
  footprints: 48, 54 and 60 GiB. Development runs at the middle one; a change
  is checked at the other two before it lands.
- **`ab_bench.py`** gains what that condition needs and lacks today (design
  D5).
- **The tables.** Step 0 (misses per layer call against the cache size, taken
  on 2026-11-18), the decode and prefill rates at the three footprints with
  the rest of the RAM taken and free, and the footprint each cache size
  costs at the service's context. They go to `docs/SSD_STREAMING.md`, with a
  corrected account of what emulated 48 GB measures.
- **Use 1 as a closing check**, between two ends (design D8).
- **The order of the next changes**, read from the tables (design D9):
  `191-ssd-decode-layer-round-trip`, `189-ssd-handshake-gated`, and the
  candidates taken from sf-ds4-1flash.

Output does not change: the switch moves bytes by another route into the
same buffers, and it is off by default.

## Impact

- `ds4_metal.m` (the uncached descriptor and its read, about 95 lines from
  `dc50997`), `tests/test_qwen4_ssd_experts.c`, `speed-bench/ab_bench.py`,
  `docs/SSD_STREAMING.md`.
- `189-ssd-handshake-gated`: its protocol (design D2 there) is replaced by
  this bench; it starts after this change.
- `186-ssd-memory-pressure`: unchanged; the capped condition is where its
  pressure test will run.
- No new command-line flag. No behaviour change without the switch.
