# Design

## Context

The stream expert cache has one global budget. Its per-layer cap
(`ds4_gpu_stream_expert_cache_effective_cap`) is the layer's expert count, so
`ds4_gpu_stream_expert_cache_prune_layer` never evicts for Qwen (the proposal
named it; task 2.1 found otherwise). A Qwen row call that misses with the
cache full plans its victims once, over every cached entry of every layer
(`ds4_gpu_stream_expert_cache_plan_reuse`), and falls back to the scalar scan
`ds4_gpu_stream_expert_cache_take_reusable`. The other scans that read the
hotness table (`prune_layer`, `prune_global`, `take_reusable_batch`,
`release_mlock_margin`) serve the DeepSeek graph's loaders and the seed
calls, which no Qwen session runs. In-flight entries and the ids routed for
the current layer are never taken. `e->last_used` is a use counter; route hotness is per (layer,
expert), incremented on every selection, hit or miss, and halved every
`DS4_METAL_STREAM_EXPERT_HOTNESS_DECAY_TOKENS` (16) decode tokens.

## Decisions

### D1. The rule

As proposed: an entry is "recent" when it was used within the last W decode
tokens; the scan picks the best non-recent victim by the existing order, and
only if every candidate is recent does it fall back to the existing order
over all of them.

As built, after step 0 and two measured windows (D5): the window is one
full pass over the layers, not W tokens. During a row call (decode and MTP
verify, up to three rows) an entry is recent when this pass used it, or when
the previous pass used it in a layer this pass has not reached again; a
recent entry ranks after every older one, and each class keeps the existing
order (route hotness, then oldest use). If every candidate is recent the
order is the existing one over all of them, so the budget always holds. A
prefill chunk and every caller outside the row path rank by hotness alone,
as before.

Recency is read from a per-entry stamp of the pass counter
(`g_stream_expert_cache_decode_tokens`), taken where `last_used` is updated,
and from the entry's layer against the layer of the row call in progress.
`last_used` itself counts uses, not passes, so it cannot serve.

There is no W and no switch. `DS4_METAL_STREAM_EXPERT_RECENT_TOKENS=<W>`
existed while the token windows were measured and went with them.

### D2. Choosing W

Step 0 replays `185`'s four routing traces through a model of the cache (the
same caps, the same order) for W in {0, 1, 2, 4, 8, 16} and counts misses per
token. It needs no model run. The smallest W within 2% of the best miss count
on all four traces is taken. If no W lowers misses by at least 10% on at
least three traces, the change is closed as "measured, not needed".

The replay must first reproduce the recorded miss counts at W = 0 (108, 257,
222, 340 per token); a replay that does not is wrong and decides nothing.

### D3. Keep or drop

`ab_bench.py` at emulated 48 GB, `main` against the change, Q2 then Q4, plain
and MTP kinds, at least 8 pairs per kind, each run of both sides starting
with the GGUF's pages evicted from the page cache (the protocol `185`
established; without it the two sides share the cache and the figure is not
clean).
- Target metric: streamed plain decode. Kept when its pooled CI lies above
  zero and no other metric's lies wholly below zero.
- The same measurement is repeated once without evicting the page cache, as
  information: it is the state a long-running server is in.
- Runs that overlapped a foreign load do not ground a drop.

### D4. Cache-size curve (information for `186`)

With the kept code (or `main` if dropped): streamed plain decode on Q2 at
emulated 48 GB at three `--ssd-streaming-cache-experts` sizes at and below
the plan, 4 pairs each. Recorded in `docs/SSD_STREAMING.md` only if it shows
a clear slope; otherwise in the commit message.

### D5. Outcome (2026-11-18): kept, with a window of one pass

**Step 0.** `185`'s traces had been deleted with its scratch, so the four
traces were recorded again (plain kind, emulated 48 GB, 192 decode tokens of
48 layers, prose and code), with the whole cache (entries, hotness, use
counters) dumped at the start of each decode segment. The plan follows the
memory free at launch: the cache held 2223-2230 experts on Q2 and 772 on Q4
that hour (`185` had 2464 and 978), so the baseline misses are higher than
`185`'s 108.5 / 256.8 / 222.2 / 340.4. The replay starts each segment from
the recorded cache and applies the row path's order. At W = 0 its cache
equals the recorded one before every one of the 9216 loads of each trace.

Misses per decode token, of 480 routed:

| Rule | Q2 prose | Q2 code | Q4 prose | Q4 code |
|---|---|---|---|---|
| `main` (recorded = replayed) | 129.15 | 276.51 | 244.42 | 355.98 |
| D1 as proposed, W = 1 | 119.19 | 260.33 | 224.51 | 334.11 |
| W = 2 | 106.92 | 234.62 | 204.29 | 314.41 |
| W = 4 | 102.08 | 219.31 | 215.45 | 314.20 |
| W = 8 | 99.23 | 215.33 | 224.60 | 326.76 |
| W = 16 | 101.94 | 225.36 | 233.66 | 340.47 |
| graded window, W = 8 | 98.20 | 216.26 | 209.35 | 316.97 |
| one pass (built) | 105.59, -18.2% | 233.40, -15.6% | 190.53, -22.0% | 299.24, -15.9% |

D2's stop rule did not apply (W = 2 and W = 4 lower misses by over 10% on
all four traces), but its choice rule had no answer: no W is within 2% of
the best on all four. The Q2 cache holds 4.6 tokens of experts and wants
W = 8, the Q4 cache 1.6 and wants W = 2; past the cache size every candidate
is recent and D1 falls back to the old order. A graded window (the least
recent pass inside the window goes first) removes that cliff and was built
first, with W = 8.

**Two token windows failed D3 on the resumed prefill.** Emulated 48 GB,
`main` against the branch, every run of both sides starting with the pack's
pages dropped from the page cache, windows with no other workload, tokens
identical, bootstrap 95% CI of the median pair ratio:

| Window | Pack, pairs | Plain decode | Prefill 8192 | +512 | +2048 |
|---|---|---|---|---|---|
| graded, W = 8 | Q2, 11 | +0.97% [+0.49%, +1.17%] | +0.08% [-0.41%, +0.45%] | **-3.16% [-3.89%, -1.86%]** | +2.06% [+0.69%, +2.99%] |
| graded, W = 2 | Q2, 15 | +1.77% [+1.16%, +2.95%] | -0.06% [-0.21%, +0.28%] | -0.40% [-0.85%, +0.76%] | +0.47% [-0.74%, +2.22%] |
| graded, W = 2 | Q4, 10 | +1.44% [+0.95%, +2.12%] | +0.05% [-0.19%, +0.12%] | **-1.28% [-2.15%, -0.52%]** | +0.81% [+0.36%, +0.99%] |

Prefill misses do not change (Q2 prose: 45785 against 45900 over the three
prefills), so the loss is not in the reads. What changes is which experts
the prefill finds cached. Hotness keeps the experts that carry most of a
chunk's pairs, and a prefill computes its cached experts while the rest
load. A window that takes the whole cache evicts them: in the replay the
share of route hotness the cache holds when the first decode segment ends
falls from 68.1% to 51.8% on Q2 prose with W = 8, and from 44.9% to 27.1% on
Q4 prose with any W of 2 or more (66.2% on Q2 with W = 2, which passed).
This is inferred from the replay and the two failures, not profiled.

**One pass.** The replay of a window measured in cache uses has a sharp
threshold at exactly one pass over the layers: 0.9 of a pass is no better
than `main` (worse on three traces), 1.0 gives nearly everything, more gives little on Q2 and costs the
hot set on Q4. That is the finding `185` reported, read the right way round:
17-29% of misses were on an expert the same layer had routed one token
earlier. The rule as built spares what this pass used and what the previous
pass used in layers not reached again. Held hotness at the first segment's
end: 67.2% on Q2 prose (68.1% on `main`), 36.0% on Q4 prose (44.9%).

Measured, same protocol (the plain kind's prefills run at an 8192-token
chunk on a 10.8K context; the MTP kinds at a 2K context, where the plan
gives a larger cache):

| Pack, pairs | Plain decode, `main` -> change | Prefill 8192 | +512 | +2048 |
|---|---|---|---|---|
| Q2, 15 | 30.43 -> 30.89 t/s, **+1.59% [+1.44%, +1.95%]** | +0.02% [-0.18%, +0.13%] | +0.64% [-0.07%, +1.15%] | +0.12% [-0.38%, +1.14%] |
| Q4, 12 | 18.83 -> 19.52 t/s, **+3.53% [+2.62%, +4.24%]** | +0.13% [-0.21%, +0.25%] | +0.47% [-0.25%, +0.95%] | +0.29% [-0.14%, +0.48%] |

| Pack, kind, pairs | MTP decode | Prefill 2048 |
|---|---|---|
| Q2, mtp-code, 12 | 38.97 -> 38.91 t/s, -0.10% [-0.51%, +0.18%] | +0.08% [-0.30%, +0.48%] |
| Q2, mtp-prose, 12 | 39.28 -> 39.25 t/s, -0.09% [-0.28%, +0.32%] | -0.24% [-0.43%, +0.14%] |
| Q4, mtp-code, 11 | 26.20 -> 26.19 t/s, -0.15% [-1.29%, +0.77%] | -0.14% [-0.31%, +0.16%] |
| Q4, mtp-prose, 8 | 28.09 -> 28.59 t/s, +1.83% [+1.56%, +2.40%] | -0.10% [-0.22%, +0.11%] |

Two runs of each side in the Q4 plain series show one stalled decode
segment (the machine's endpoint scanner was busy when checked); the median
and its interval absorb them.

The target metric lies above zero on both packs and no metric lies wholly
below it: kept by D3. Tokens are identical in every run, and tokens per MTP
cycle are equal. Peak of the memory-locked runs: 101.0 GiB wired, 2.4 GiB in
the compressor; the guard never fired and no container ran.

Misses per decode token on the model, from traces of the final code (the
cache held 2397-2430 experts on Q2 and 873 on Q4 at that hour; `main` is its
order replayed from the same recorded starts): Q2 prose 120.22 -> 98.64
(-17.9%), Q2 code 266.93 -> 226.09 (-15.3%), Q4 prose 233.94 -> 181.02
(-22.6%), Q4 code 348.58 -> 291.20 (-16.5%). The replay had said -18.2%,
-15.6%, -22.0% and -15.9%.

Without evicting the page cache (D3's informational run: Q2, plain, one
invocation, 6 pairs, 4 more dropped by the harness as the GPU frequency
swung across the thermal plateau): decode 28.18 -> 29.31 t/s, +3.27%
[+1.78%, +9.70%]; prefill 8192 -0.13% [-5.02%, +13.47%], +512 +1.99%
[-1.61%, +7.15%], +2048 +0.28% [-4.01%, +9.77%]. Same direction, wider
intervals.

**D4, the cache-size curve.** Run last, on the landed code: Q2, plain,
emulated 48 GB, same protocol, 2200 cache slots (the plan capped one of the
three baselines at 2064) against fewer, 4 pairs each, tokens identical:

| Cache slots | Plain decode | Prefill 8192 | +512 | +2048 |
|---|---|---|---|---|
| 1650 | -1.87% [-3.46%, -1.63%] | +0.3% | -0.2% | +3.1% |
| 1100 | -3.08% [-4.37%, -1.29%] | +2.8% | +1.8% | +4.6% |
| 550 | 30.7 -> 28.2 t/s, -8.55% [-9.15%, -7.34%] | +1.5% | +3.4% | +9.4% |

The prefill columns are medians of 4 pairs (ranges at 550: -0.3% .. +1.7%,
+3.2% .. +5.9%, +7.6% .. +10.9%). A clear slope, so it is in
`docs/SSD_STREAMING.md`. Decode loses 3% at half the cache and 8.5% at a
quarter, while the resumed prefill gains as the cache shrinks; why it gains
was not looked into. For `186`: the plan also follows the memory free at
launch, and across this night's runs it gave the Q2 plain kind between 2064
and 2608 cache slots and the Q4 one between 772 and 931 under the same
80 GB lock.

**Left for a later change.** The victim scan visits every cache slot at each
layer call that misses: 0.030 ms per scan in the plain traces, on `main` and
with this change, about 1.4 ms per decode token. With the larger MTP cache
it visits more live entries.

## Risks / Trade-offs

- **Prefill.** A prefill chunk selects many experts per layer and is not a
  sequence of decode tokens. The rule keys on decode tokens, so prefill
  eviction is unchanged; the A/B's prefill metrics check that. They did:
  the order inside a prefill is unchanged, but what decode leaves in the
  cache is not, and two windows were dropped for it (D5).
- **A hot expert can now be evicted in place of a fresh one.** That is the
  intent, and the trace replay is what says whether it pays.
- **The traces are 192 tokens.** Short, and plain decode only. The A/B on
  MTP kinds is the check that the rule does not hurt verify rows, whose
  selections differ.
