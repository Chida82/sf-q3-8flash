# Design

## Context

The stream expert cache has a per-layer cap
(`ds4_gpu_stream_expert_cache_effective_cap`). When a layer holds more
entries than its cap, `ds4_gpu_stream_expert_cache_prune_layer`
(`ds4_metal.m:14119`) removes victims one at a time. Other eviction sites
read the same hotness table (`rg 'route_hotness\[' ds4_metal.m`); task 2.1
finds which of them choose victims. In-flight entries and the ids protected for the current layer are
never taken. `e->last_used` is a use counter; route hotness is per (layer,
expert), incremented on every selection, hit or miss, and halved every
`DS4_METAL_STREAM_EXPERT_HOTNESS_DECAY_TOKENS` (16) decode tokens.

## Decisions

### D1. The rule

An entry is "recent" when it was used within the last W decode tokens. The
scan picks the best non-recent victim by the existing order. Only if every
candidate is recent does it fall back to the existing order over all of
them, so the cap is always honoured and the scan always terminates.

Recency is read from a per-entry token stamp taken where `last_used` is
updated. `last_used` itself counts uses, not tokens, so it cannot serve.

W = 0 disables the rule and is the kill switch for the A/B:
`DS4_METAL_STREAM_EXPERT_RECENT_TOKENS=<W>`.

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

## Risks / Trade-offs

- **Prefill.** A prefill chunk selects many experts per layer and is not a
  sequence of decode tokens. The rule keys on decode tokens, so prefill
  eviction is unchanged; the A/B's prefill metrics check that.
- **A hot expert can now be evicted in place of a fresh one.** That is the
  intent, and the trace replay is what says whether it pays.
- **The traces are 192 tokens.** Short, and plain decode only. The A/B on
  MTP kinds is the check that the rule does not hurt verify rows, whose
  selections differ.
