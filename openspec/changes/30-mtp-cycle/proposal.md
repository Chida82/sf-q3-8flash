# Proposal

## Why

Built-in MTP (`--mtp`) is the largest decode lever. PR #1062 (open, head
`1ab00b5`) was measured on the same hardware and model as this child (M5 Max
128 GB, Q4), and 8 of its code commits are not in main. Two reasons it helps,
from reading the code:

- **The predictor starts blind.** The MTP (nextn) layer's attention cache is
  empty across the prompt and only fills with generated tokens, so the first
  draft's acceptance p1 stays low.
- **The cycle is expensive.** The PR's figures (1.60 tokens/cycle at 56.6 tok/s)
  imply about 28 ms per cycle, roughly 1.5× a plain token if plain decode is
  near 54 tok/s. Verifying 2-3 rows should cost little more than one, since the
  weights are read once. [inferred; `20-perf-bench-harness` measures the real split]

## What Changes

Port, in this order, keeping each step only if the harness shows a gain:

1. `acce8da` **Prime the predictor during prefill.** The nextn layer runs over
   the prompt rows inside each prefill chunk's submission, and the last row is
   parked until its successor is known.
   - The tail flush in the batched speculative entry is hand-ported, because
     upstream rewrote that block in `548cdaf`.
   - The batched predictor's stage/combine call (`e2cba0b`) gets the new
     `n_tokens` argument.
   - Optional refinement, taken from #1056 `b86c8ae`: prompt rows fill only the
     K/V/indexer caches (no Q projection, attention output or MoE), which lowers
     the prefill cost.
2. `be4cec8` **Three-row catch-up on the decode kernel geometry** (split decode
   attention instead of prefill attention).
3. `926ee12` **Depth policy from measured acceptance and cycle cost.** Choose
   depth 3 when `(1+p1+p1·p2)/c3 > (1+p1)/c2`. The copy of `qwen4_ema` that
   upstream `3077786` already added is reused, not duplicated.
4. `0a89a04` **The GPU gathers the predictor's next-token embeddings.** This
   removes a host dequant/upload and the 80 MiB priming arena. Needs the
   `glm_graph_begin_commands_if_needed` -> `qwen4_graph_begin_commands_if_needed`
   rename and an id buffer for the batched predictor.
5. `1cd83e3` **Chain the second draft inside the same submission.** One
   GPU->CPU readback and one submission fewer per depth-3 cycle.

Dropped: `822de06` (conflicts, helps only one-slot batched server mode),
`4d8b5dd` (no effect by default), `1ab00b5` (already in the child).

Claimed by the PR on M5 Max, Q4, one stream (single runs; the PR notes 5-15%
thermal drift):

| Step | Code | Prose |
|---|---|---|
| after `acce8da` | 56.6 -> 65.1 tok/s (1.60 -> 1.94 tokens/cycle) | 56.2 -> 58.0 tok/s |
| depth 3 after `be4cec8` | 81.5 vs 78.1 tok/s at depth 2 | — |
| after `1cd83e3` | 82.0 tok/s | — |

MTP-mode prefill costs about 3.4%: 1315 -> 1270 tok/s.
Inferred combined effect: +15-30% on code, +3-8% on prose. The gain fades as the
generated text grows long relative to the prompt.

## Capabilities

### New Capabilities
- `mtp-speculation`: built-in MTP contract.
  - Greedy output with `--mtp` is identical to plain greedy.
  - Session payload and disk-KV checkpoints stay compatible in both directions.
  - The predictor is primed over prompt rows.
  - Draft depth follows measured acceptance and cost.

### Modified Capabilities
None.

## Impact

- `ds4.c`:
  - `qwen4_graph_mtp_steps`, `qwen4_graph_mtp_chain_step` (removed by `1cd83e3`)
  - `ds4_session_qwen4_spec_cycle`, `qwen4_spec_depth`
  - `qwen4_batch_mtp_drafts`, `ds4_sessions_eval_batch_speculative_argmax`
- `ds4_metal.m` and `metal/qwen4.metal`: stage/combine `n_tokens`, argmax
  signature.
- `tests/test_qwen4_mtp*`.
- Size: roughly +400/-200 lines.
- Payloads grow by about one layer of KV per prompt row (nextn KV now covers the
  prompt; about 1/13 of attention KV). The format is unchanged.
- Sampled (non-exact) MTP may produce different text, because drafts change.
  Exact and greedy modes are unaffected.
- Sync: if upstream later merges #1062, the first sync conflicts in these
  regions and rerere cannot replay it. Record adopted commits in
  `docs/upstream-prs.md`.
