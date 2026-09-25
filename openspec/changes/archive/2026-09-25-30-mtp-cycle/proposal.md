# Proposal

## Why

Built-in MTP (`--mtp`) is the largest decode lever. PR #1062 (open, head
`1ab00b5`) was measured on the same hardware and model as this child (M5 Max
128 GB, Q4), and 5 of its code commits that matter here are not in main. Two
reasons they help, from reading the code:

- **The predictor starts blind.** The MTP (nextn) layer's attention cache is
  empty across the prompt and only fills with generated tokens, so the first
  draft's acceptance p1 stays low.
- **The cycle is expensive.** The PR's figures (1.60 tokens/cycle at 56.6 tok/s)
  imply about 28 ms per cycle, roughly 1.5× a plain token if plain decode is
  near 54 tok/s. Verifying 2-3 rows should cost little more than one, since the
  weights are read once. [inferred; the harness from `20-perf-bench-harness`
  measures the real split]

This is also the first performance change since the harness landed, so it
writes the start row of the performance record.

## What Changes

0. **Start row.** An A/A run on a worktree of `91f225a` (the `main` commit on
   which `20-perf-bench-harness` landed) writes the first row of Segment 1 in
   `speed-bench/perf-record.md`.

Then port, in this order. Each step is measured against the previous one and
kept only if the harness shows a gain:

1. `acce8da` **Prime the predictor during prefill.** The nextn layer runs over
   the prompt rows inside each prefill chunk's submission. The last row is
   parked until its successor is known.
   - The tail flush in the batched speculative entry is ported by hand, because
     upstream rewrote that block in `548cdaf`.
   - The batched predictor's stage/combine calls (`e2cba0b`) get the new row
     count argument.
2. `be4cec8` **Three-row predictor on the decode kernel geometry.** It uses the
   split decode attention instead of the prefill attention.
3. `926ee12` **Depth policy from measured acceptance and cycle cost.** It
   chooses depth 3 when `(1+p1+p1·p2)/c3 > (1+p1)/c2`. (Dropped on
   measurement: -8.9% on code; the window policy stays. See the registry.) The copy of `qwen4_ema`
   that upstream `3077786` already added is kept; the PR's second copy is not
   added.
4. `0a89a04` **The GPU gathers the predictor's next-token embeddings.** This
   removes a host dequant/upload and the 80 MiB priming arena.
   - Its conflicts are name-only: the child already calls the helper
     `qwen4_graph_begin_commands_if_needed`.
   - The batched predictor from `e2cba0b` gathers on the host. It is rewritten
     onto the id buffer and one batched stage call.
5. `1cd83e3` **Chain the second draft inside the same submission.** This saves
   one GPU->CPU readback and one submission per depth-3 cycle. Its conflicts are
   also name-only; the batched predictor's argmax takes the new row-list
   argument.
6. Optional, only if step 1's prefill cost is measurable: **cache-only
   priming**, the idea of #1056 `b86c8ae`. Prompt rows fill only the nextn
   K/V/indexer caches (no Q projection, attention output or MoE). It uses the
   child's existing kernels and must leave the drafts unchanged.

A trial port of steps 1-5 on a scratch clone applies with only the conflicts
above, builds without warnings, and passes `make test-qwen4-kernels`.

The ported code is not taken as final. Each step gets a short review before
it is measured, fixing only what would make the step wrong. After the last
step, a full review of the MTP region rewrites what can be written better:
- in the child's style;
- with dead toggles and duplication removed;
- with missed speed recovered.

Those refinements must leave the drafts and every logit bit-identical, and
are measured and committed as a step of their own.

Dropped:

- `822de06` conflicts, and helps only a batched server with one active slot.
- `4d8b5dd` has no effect by default.
- `1ab00b5` is already in the child.
- `a6ad636` (replay diagnostics) is not ported: as written it needs SSD
  streaming, and the draft-identity gate of steps 4-6 covers the same risk.

Every adopted or dropped commit gets its verdict line in
`docs/upstream-prs.md` updated in the same branch. `docs/SPECULATIVE_DECODING.md`
describes the priming and the depth rule.

Claimed by the PR on M5 Max, Q4, one stream (single runs; the PR notes 5-15%
thermal drift):

| Step | Code | Prose |
|---|---|---|
| after `acce8da` | 56.6 -> 65.1 tok/s (1.60 -> 1.94 tokens/cycle) | 56.2 -> 58.0 tok/s |
| depth 3 after `be4cec8` | 81.5 vs 78.1 tok/s at depth 2 | — |
| after `1cd83e3` | 82.0 tok/s | — |

MTP-mode prefill costs about 3.4%: 1315 -> 1270 tok/s.

Inferred combined effect: +15-30% on code and +3-8% on prose. The gain fades as
the generated text grows long relative to the prompt. Plain (non-MTP) decode
and prefill are untouched.

## Capabilities

### New Capabilities
- `mtp-speculation`: the built-in MTP contract.
  - Greedy output with `--mtp` is identical to plain greedy (single session and
    batched).
  - Plain mode is unaffected.
  - The predictor is primed over text prompts.
  - Draft depth follows recent acceptance (the existing window policy), and
    can be pinned.
  - Session payloads and disk-KV checkpoints stay compatible in both
    directions.

### Modified Capabilities
None. `perf-harness` is used, not changed.

## Impact

- `ds4.c`:
  - prefill forward and `qwen4_graph_stage_inputs` (priming hook)
  - new priming and tail-flush functions
  - `qwen4_graph_mtp_steps`; `qwen4_graph_mtp_chain_step` is removed by `1cd83e3`
  - `ds4_session_qwen4_spec_cycle`, `qwen4_spec_depth`
  - `qwen4_batch_mtp_drafts`, `ds4_sessions_eval_batch_speculative_argmax`
  - graph allocation (`mtp_next`, `mtp_tail`)
- `ds4_gpu.h`, `ds4_metal.m`, `metal/qwen4.metal`: the stage kernel takes a row
  count and gathers embeddings by id; the combine kernel takes a row count; the
  argmax maps a gathered head's rows.
- `tests/test_qwen4_kernels.c`: stage/combine/argmax cases follow the new
  signatures.
- `docs/upstream-prs.md`, `docs/SPECULATIVE_DECODING.md`,
  `speed-bench/perf-record.md`.
- Size, measured by the trial port of steps 1-5: 5 files, about +430/-350 lines.
- Payloads grow by the nextn layer's KV over the prompt (about 1/13 of the
  attention KV), because that cache now covers it. The format is unchanged.
- Multimodal prompts are not primed (image rows have no token), so their
  acceptance stays as today.
- Sampled (non-exact) MTP may produce different text, because the drafts change.
  Exact and greedy modes are unaffected.
- Sync: if upstream later merges #1062, the first sync conflicts in these
  regions and rerere cannot replay it. The registry records which commits the
  child took.
