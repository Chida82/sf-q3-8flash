# Proposal

## Why

Built-in MTP drafts one or two tokens per cycle from the model's own
predictor and commits 1.91-2.46 tokens per cycle (`speed-bench/perf-record.md`).
Agent output is often a copy: an edit repeats most of the file it was shown,
a tool call repeats paths and identifiers, an answer quotes the question. For
those tokens the best draft is already in the context, and the predictor is
not needed to find it.

Prompt-lookup drafting proposes the tokens that followed the last earlier
occurrence of the current suffix. Verification decides acceptance exactly as
for a predictor draft, so greedy output cannot change.

Two sources describe it for this model:
- Upstream commit `7e6ab2f`, "Draft Qwen3.8 MTP cycles from prompt lookups"
  (+429 lines in `ds4.c`), in the open PR #1179 (head `79c914c`, WIP, no
  description). `docs/upstream-prs.md` lists it as open and unverified.
- Splash 1.7.0 (incoai/splash, Apache-2.0) does the same with a suffix
  automaton over prompt plus output: matches of 3 or more tokens, up to 15
  proposed, 89 bytes per token. It gives no figure for lookup alone on this
  model; on another model the first token of a 3-token match was accepted
  55% of the time. No Splash code is copied.

Neither source has a figure for this model and these packs. This change
measures the potential first, offline, and builds only if it is there.

Performance under the intake criteria.

## What Changes

- **Step 0, offline measurement.** On recorded agent transcripts, count how
  many output tokens a lookup would have drafted correctly, by match length
  and by workload. No engine change. The change stops here if the share is
  too small (design D1).
- **S1, lookup drafts inside the existing cycle.** Port `7e6ab2f`: when the
  context holds a long enough match, the cycle's draft rows carry the looked
  up tokens; otherwise the predictor drafts as today. The verify width stays
  at today's depth 2 or 3.
- A copy-heavy bench kind, so the gain and its absence elsewhere are both
  measured.

Greedy output must stay token-identical to plain decoding, with and without
lookup. Exact sampling at nonzero temperature keeps drafting from the
predictor only, unless the port shows its acceptance rule holds for a lookup
draft (design D3).

Not in this change: verify chains longer than three rows. They need a way to
roll back recurrent state that does not copy it per row (Splash keeps a
per-row tape for GDN). Step 0 records the match-length histogram that says
whether that follow-up is worth proposing.

## Impact

- `ds4.c` (MTP cycle, session state), `ds4_bench.c` and `speed-bench/` (the
  new kind), `tests/`, `docs/upstream-prs.md`, the `mtp-speculation` spec.
- Independent of the SSD changes.
