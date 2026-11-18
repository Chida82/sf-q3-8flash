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

### D5. Outcome (2026-11-18): S1 dropped, S2 stopped after step 0

**How it was measured.** A direct read still copies a page that is already
in the page cache, so in an A B B A schedule the uncached side reads what
`main`'s runs left there: the first Q2 run, taken that way, read decode +0.4%
and prefill +19% to +63%, and measured nothing of S1. Every figure below
starts each run of both sides with the GGUF's pages dropped from the page
cache (a scratch tool: `mmap` plus `msync(MS_INVALIDATE)`; 25 GiB of the Q2
pack were cached after one `main` run). Emulated 48 GB, windows with no
other workload, tokens identical, bootstrap 95% CI of the median pair ratio.

**S1, uncached reads: dropped.** A second descriptor with `F_NOCACHE`, the
enclosing pages read into a per-thread aligned buffer and the rows copied
out (expert rows are 32-byte aligned in the GGUF, so no read is in place).

| Pack, pairs | Plain decode, `main` -> S1 | Prefill 8192 | +512 | +2048 |
|---|---|---|---|---|
| Q2, 8 | 30.2 -> 20.3 t/s, **-33.3% [-34.0%, -31.3%]** | +0.6% [+0.4%, +1.5%] | -31.5% [-32.8%, -28.5%] | -22.9% [-23.3%, -20.7%] |
| Q4, 2 (information) | 18.9 -> 11.2 t/s, -41.0% | +0.2% | -25.5% | -7.9% |

The target metric lies wholly below zero. The reason is the opposite of this
design's premise: at emulated 48 GB the spare RAM does exist. The plan
takes 19.4 GiB (Q2) and the process holds about 10.6 of them; the kernel
keeps about 25 GiB of the pack in the page cache, and an expert evicted from
the 3.4 GiB Metal cache comes back from there at memory speed. Uncached
reads give that second-level cache up. Peak footprint is the same on both
sides (the page cache is not the process's): 90.6 GiB with 80 locked on Q2,
89.4 on Q4. The MTP kinds were not run: the target metric had decided.

`F_RDADVISE` (D1) needed no measurement: the helper is never called on the
Qwen path (`readahead_calls=0` in the stream timing summary).

**S2 step 0: one predictor passes D2.** Routing traces of plain decode
(192 tokens, 48 layers) on prose and code, recorded with the cache's state
before each load. `covered` is the share of misses the predictor named;
`w/s` is wasted early reads over covered ones.

| Trace (cached experts) | Misses per token, of 480 | 1. previous token | 2. co-occurrence, top 10 | 3. next router, top 6 | top 10 |
|---|---|---|---|---|---|
| Q2 prose (2464) | 108.5 | 20.1%, w/s 3.26 | 7.3%, 2.11 | 32.0%, 0.84 | 50.4%, 1.54 |
| Q2 code | 256.8 | 17.5%, 4.18 | 17.1%, 2.47 | 33.2%, 0.84 | 47.6%, 1.36 |
| Q4 prose (978) | 222.2 | 28.8%, 2.25 | 12.5%, 1.91 | 38.1%, 0.45 | 56.4%, 0.88 |
| Q4 code | 340.4 | 22.0%, 3.31 | 21.9%, 2.43 | 35.9%, 0.68 | 50.1%, 1.11 |

Predictors 1 and 2 fail on every trace. Predictor 3, the next layer's router
on this layer's FFN input, passes with its top 6 everywhere, and with its
top 10 on Q4 prose. Its top 10 holds 67% of the routed ids on prose and 53%
on code.

**S2 was not built.** A scratch probe took the cheapest form of the idea:
predictor 3 computed on the CPU, and `F_RDADVISE` on the predicted experts
the Metal cache lacks, so the read starts one layer early into the page
cache. Against the same prediction work with the hint left out, plain decode
read -0.8% (-1.5% .. +0.4%, 4 pairs) on Q2 with the top 6, and -5.8% and
-3.6% (2 pairs) on Q4 with the top 10. Likely reasons, from the figures and not from a
profile: most missed experts are already in the page cache; a layer waits
for the slowest of its parallel reads, so naming a third of the misses
rarely removes the wait; and on Q4 the wasted reads compete with the real
ones. Reading ahead into cache slots, as D2 describes, also
hides the copy out of the page cache, but costs a slot per wasted read in a
cache that holds two (Q4) to five (Q2) tokens of experts; it was not built
for lack of time and is left to a new proposal, with these tables.

What the traces also show, for that proposal and for D4:
- 17-29% of misses are on an expert routed for the same layer one token
  earlier, and 37-49% within eight tokens: hotness-then-LRU evicts freshly
  loaded entries first. That is the evidence D4 said was missing.
- The streamed rate at this size is bounded less by the read path than by
  the cache size: the plan leaves the page cache more of the pack than it
  gives the Metal cache. `186-ssd-memory-pressure` owns that question.

The S1 code is commit `dc50997` on the local branch
`perf/185-ssd-expert-read-path`; the trace patch, the probe and the scoring
script are the branch's last commit.

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
