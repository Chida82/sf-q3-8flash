# Design

## Context

Streamed Qwen keeps 6.32 GiB mapped and reads routed experts into a bounded
cache of owned Metal buffers (`docs/SSD_STREAMING.md`). Eviction is by decayed
route hotness, then LRU. The expert cache is sized once at engine open.

## Decisions

### D1. S1: a second, uncached descriptor for expert reads

- Open it beside `g_model_fd` at engine open when `--ssd-streaming` is on;
  close it with the engine. Mapped static weights keep using the first one.
- `F_NOCACHE` reads need page-aligned offsets and lengths to stay on the
  direct path. Read the enclosing page range into the staging buffer and copy
  out the expert's rows, or read in place when the destination is aligned.
  The byte range handed to the kernels is the one read today.
- `ds4_gpu_stream_expert_readahead_range` (`F_RDADVISE`) fills the page cache,
  which an uncached descriptor does not read from. Measure S1 with it on and
  off; keep the faster, and delete the helper if it is off.
- Kill switch for the A/B: `DS4_METAL_STREAM_EXPERT_CACHED_READS=1` restores
  the buffered descriptor.

### D2. S2: predicting the next layer's experts

Three candidate predictors, tried in this order; the first that passes the
threshold below is built, and the step is dropped if none does:

1. **The previous token's routing for the same layer.** Free: the ids are
   already on the CPU.
2. **Layer L's routed ids as a hint for L+1**, through a table of observed
   co-occurrence built during the run. No GPU work.
3. **The next layer's router on this layer's input** (Splash's method). One
   small extra kernel dispatch per layer, read back with the ids that are
   read back anyway.

Step 0 measures all three offline from one recorded routing trace: for each
predictor, the share of next-layer misses it would have read early, and the
share of predicted experts never used (wasted reads). A predictor that covers
under 30% of misses, or wastes more reads than it saves, is not built.

Read-ahead uses the existing read pool. A predicted expert takes a free slot
or evicts by the existing policy, but never an entry that the current or the
next layer has protected. A wrong prediction costs one read and one slot; it
never changes which experts a layer computes with.

### D3. Keep or drop, per step

Measured with `ab_bench.py` at emulated 48 GB, Q2 and Q4, plain and MTP
kinds, the previous state against the step.
- Target metric: streamed plain decode. Kept when its pooled CI lies above
  zero and no other metric's lies wholly below zero.
- S1 also records peak footprint and the process's file-backed resident
  pages. A lower footprint with a neutral rate is enough to keep S1, because
  memory is what a streaming machine is short of.
- Runs that overlapped a foreign load (Docker) do not ground a drop.

### D4. What is not taken

- ARC replacement and elastic cache chunks: no evidence yet that hotness plus
  LRU is the bottleneck. `186-ssd-memory-pressure` covers shrinking.
- Splash's GPU-thread spin, tile layouts and bf16 activations: the first
  needs its own measurement, the others change arithmetic.

## Risks / Trade-offs

- **Uncached reads lose the page cache as a second-level cache.** An expert
  evicted from the Metal cache and needed again is read from disk, not from
  memory. On a machine with spare RAM that can be slower; D3 measures at
  emulated 48 GB, where the spare RAM does not exist.
- **Read-ahead competes with the current layer's reads** for the same SSD
  queue. The pool issues current-layer reads first.
- **Emulation keeps this Mac's SSD.** A smaller Mac with a slower disk gains
  more from read-ahead and less from raw throughput; the doc says so beside
  the figures.
