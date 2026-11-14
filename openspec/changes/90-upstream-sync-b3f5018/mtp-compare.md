# MTP: upstream b3f5018 against the child (E4, 2026-11-14)

## What differs

| | Upstream `b3f5018` | Child (old `main` `765e9a5`, and this sync) |
|---|---|---|
| Verify rows | batched rows (2/1 split in `qwen4_graph_attention_core_rows`); not the single-token arithmetic | `82`: every verify row computes exactly as single-token decode, so greedy MTP output equals plain output by construction |
| Predictor history over the prompt | resident default (`cd1c550`): empty, the predictor starts cold; `DS4_QWEN4_MTP_PREFILL=on` runs the whole nextn layer over the prompt (upstream measured 7.53 s against 6.47 s for a 7,809-token prompt) | `30`: primed during prefill, cache writes only (`qwen4_graph_mtp_prime`); the last prompt row runs at the first decode |
| Snapshot payload | v3 (carries the tail state) | v2 |
| `--mtp-exact-sampling` | yes, depth pinned to 2 at temperature > 0 | yes, same; `150` proposes #1185's rework |

## Run

Q4, M5 Max, one run each, strictly sequential, `--ctx 16384 --temp 0 --nothink`.
Prompts: the 12 of `tests/test_qwen4_mtp_identity.py` plus two long ones
(about 2,500 tokens each): copy 9,000 characters of `rax.c`, continue 9,000
characters of `promessi_sposi.txt`. Each tree ran plain and `--mtp` at depth
auto, 2 and 3; upstream also with `DS4_QWEN4_MTP_PREFILL=on`. The Q2 download
was running alongside (about 36 MB/s of disk writes) and the GPU ran hot, so
single prompts move by several percent between runs; the means are the
evidence, not the rows.

Geometric means of decode t/s, and of the per-prompt MTP/plain ratio:

| Set | Tree | plain | MTP auto | ×plain | MTP 2 | MTP 3 |
|---|---|---|---|---|---|---|
| 12 short | upstream | 57.1 | 71.0 | 1.24 | 68.8 | 68.8 |
| | old main | 55.4 | 72.0 | 1.30 | 70.4 | 68.8 |
| | sync | 56.1 | 72.7 | 1.30 | 70.6 | 68.8 |
| 2 long | upstream | 57.1 | 73.3 | 1.28 | 73.9 | 71.6 |
| | upstream, prefill on | | 79.9 | 1.40 | | |
| | old main | 55.0 | 81.9 | 1.49 | 77.3 | 80.0 |
| | sync | 57.3 | 81.7 | 1.43 | 76.8 | 80.6 |

Upstream with prefill on, 12 short: 71.7 (×1.26).

Identity: the child's MTP output equals its plain output on all 14 prompts at
every depth, old main and sync alike. **Upstream's does not**: on the long prose
prompt (Italian continuation, about 2,500 tokens) its MTP output leaves its plain output at every depth and in both prefill
modes, on Q4, where the child's design was believed to matter only on Q2.

## Reading

- Without MTP the sync runs at upstream's speed (it is upstream's decode path,
  #1238 included): about +1.7% over old main here, +3..5% in the bench sweep
  (`proposal.md`).
- With MTP the child is ahead: on short prompts it gains ×1.30 against
  upstream's ×1.24, on long prompts ×1.43..1.49 against ×1.28 (×1.40 with
  upstream's prefill on). In absolute terms the sync's MTP decode is +2% over
  upstream's on short prompts and +11% on long ones; against upstream with
  prefill on, +2% on long ones, without the prefill cost upstream measured
  for it.
- The long-prompt gap is the priming: a primed predictor drafts well from the
  first token; a cold one learns the context only as tokens are generated.
- Depth: auto is the best or tied everywhere; fixed depth 3 loses on short
  answers. Nothing here argues for changing the policy.
- Two short prompts lose with MTP in every tree (the one-number JSON answer,
  the one-word capital): a handful of output tokens, so the first-cycle cost
  is not amortized. The child's MTP ran at 45 t/s against 67 for upstream on
  the one-word prompt, in a 10% run-spread regime; worth one look in a later
  MTP change, not a sync blocker.
