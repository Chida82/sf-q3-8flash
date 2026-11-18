# Design

## Context

A Qwen MTP cycle verifies 2 or 3 rows (`ds4.c:34550-34718`). The depth
follows recent first-draft acceptance (`qwen4_spec_depth`, `ds4.c:34483`).
Rollback is a recurrent-state snapshot after row 0 and row 1
(`ds4.c:27501-27516`), which is what bounds the depth at 3. Every verify row
computes as single-token decode (change `82`), so an accepted row is
bit-identical to plain decoding.

## Decisions

### D1. Step 0: is there anything to gain

Input: token ids of real agent turns (the checkpoint-replay conversations
under `speed-bench/`, plus transcripts the owner provides), tokenized with
the vocabulary exported once in a GPU window. No model is opened by the
measurement itself.

For each output position, look up the longest earlier occurrence of the last
k tokens (k from 2 to 8) in prompt plus output so far, and compare what
followed it with what the model really produced. Report, per workload (file
edits, tool calls, prose answers):
- the share of output tokens preceded by a match of length k or more;
- oracle acceptance of the first, second and third looked-up token;
- the histogram of how many consecutive looked-up tokens were right.

Stop rule: if, on the edit and tool-call workloads, fewer than 15% of output
tokens have a match whose first two looked-up tokens are both right, the
change is closed as "measured, not needed", like `133`. The predictor
already drafts the first token well; lookup pays only when it gets two or
three right where the predictor's second draft accepts at about 0.6.

### D2. S1: where the lookup goes

- Port `7e6ab2f` onto the child's cycle. The child's MTP fields differ from
  upstream's (`mtp_prime_row`, `mtp_prime_pos`, `mtp_prime_pending` replace
  `mtp_tail_*`); read every field the commit touches before merging a hunk.
- The lookup index is built over the session's token history and extended as
  tokens commit. Its memory and build time are recorded; Splash's automaton
  costs 89 bytes per token, and the port must not be far above that at a
  100K-token context.
- Choice between sources per cycle: a lookup match at or above the minimum
  length drafts the cycle; otherwise the predictor does. The minimum length
  comes from step 0's table, not from a guess. The depth policy keeps its
  own acceptance window per source, so a failing lookup does not disengage
  depth 3 for the predictor and the reverse.
- The predictor's state must stay current through a cycle it did not draft,
  or the next predictor cycle drafts from a stale state. The port keeps
  whatever the upstream commit does for this and adds a test.
- Kill switch for the A/B: `DS4_QWEN4_MTP_LOOKUP=0`.

### D3. Sampling

Exact sampling accepts a draft with a probability that depends on the
draft's proposal distribution. A looked-up token is a point proposal. If the
upstream commit handles that case correctly it is kept and checked with the
existing exact-sampling test; if it does not, lookup is off whenever
`--mtp-exact-sampling` runs at nonzero temperature, and the spec says so.

### D4. Gates and measurement

- Identity: the model gates' MTP-against-plain checks, on Q2 and Q4, with
  lookup on, plus the same over REPL turns. A model-less test covers the
  index: matches found, extension as tokens commit, rewind.
- Measurement: `ab_bench.py`, lookup off against on, kinds `mtp-code`,
  `mtp-prose` and the new copy-heavy kind (an edit request whose answer
  repeats most of a file from the prompt).
- Kept when the copy-heavy kind's pooled decode CI lies above zero and no
  kind's lies wholly below zero. Committed tokens per cycle are reported per
  kind and per source.

### D5. The follow-up this change prepares

If step 0's histogram shows that runs of four or more correct looked-up
tokens are common on edits, verify chains longer than three rows are the
next gain. They need rollback without a full state copy per row. That is a
separate proposal, written only with that evidence.

### D6. Step 0 as measured (2026-11-18)

**No real agent turns were available.** The server's disk-KV checkpoints on
this machine (331 files; read only, counts only) are single-turn chats with
reasoning: no tool call in any of them. The edit and tool-call workloads of
D1 are therefore not measured on real data. Two sources stand in, and the
second is synthetic, which D1 warns overstates copying:
- A: those 312 real chat turns (257K output tokens, 45K after `</think>`);
- B: one `speed-bench/agent_reuse.py` run on Q4: a tool loop over a prose
  document (9 tool-call turns, 734 output tokens, 360 after `</think>`).

The oracle is `speed-bench/lookup_oracle.py`.

Share of output tokens where the last k tokens occurred earlier and the tokens
after their last occurrence match the next two the model produced; and, given
such a match, how often the first, and the first two, are right:

| k | A, all tokens | A, after `</think>` | A, first / first two | B tool calls, all | B, after `</think>` | B, first / first two |
|---|---|---|---|---|---|---|
| 2 | 22.0% | 27.6% | 54% / 36% | 30.0% | 43.3% | 57% / 44% |
| 3 | 19.4% | 25.3% | 66% / 47% | 35.1% | 58.6% | 80% / 65% |
| 4 | 16.5% | 23.1% | 72% / 55% | 31.2% | 52.8% | 83% / 69% |
| 5 | 13.9% | 20.2% | 76% / 60% | 27.7% | 47.2% | 85% / 72% |
| 6 | 11.7% | 16.9% | 78% / 63% | 24.1% | 41.9% | 87% / 73% |
| 8 | 8.0% | 11.6% | 79% / 64% | 17.4% | 32.2% | 87% / 72% |

The stop rule (under 15% on edits and tool calls) does not stop the change:
the synthetic tool calls read 24-35%, and even real chat prose reaches 22% at
k = 2. Precision flattens from k = 6, which is also upstream's minimum; that
is the minimum length taken.

For D5: given a match at k = 6, the run of correct looked-up tokens is 4 or
longer in 40% of the matches on A and 49% on B's tool calls (7.5% and 16% of
output tokens). Longer verify chains would have material to work on; whether
that holds on edits needs real edit transcripts.

### D7. S1 as built

Upstream's `7e6ab2f` is more than a lookup: it verifies blocks of up to 16
rows with a recurrent-state snapshot per row, and changes five kernels and
their wrappers for it. This proposal excludes chains longer than three rows,
so only the index is taken from it (`qwen4_lk_hash`, `qwen4_lk_index`,
`qwen4_lk_match`, as upstream wrote them, moved from the graph to the
session and out of the GPU block so the model-less test reaches them). The
window model, the per-row snapshots and the kernel changes are not ported.

Around the index the child's cycle is unchanged in shape:
- `qwen4_session_drafts` is the one place drafts are made. It asks the lookup
  for up to two tokens, runs the predictor as before (so its state and its
  own first draft are always current), and `qwen4_lk_choose` picks the
  source.
- Each source has an eight-verdict window scored on every verify, whichever
  source drafted the row: by the verify's verdict when it did, by the row's
  argmax otherwise. This replaces "a window per source that only its own
  cycles feed": feedback is complete, so a source that is not chosen can
  recover, and D2's per-source independence holds.
- The lookup is heard while six of its last eight were right. Same first
  token: the lookup's second token becomes the second draft at either depth,
  and the predictor's chained step is skipped. Different: the better window
  drafts, the predictor on a tie. A looked-up second draft that misses counts
  against the lookup.
- Batched sessions keep drafting from the predictor.

D3 is decided from the code: the exact-sampling rule accepts a draft with its
target probability and needs only that the draft be fixed before the row's
randomness is drawn. A looked-up token depends on tokens already drawn, so
the lookup stays on under `--mtp-exact-sampling`.

Tried and not kept: skipping the predictor's draft head as well when the
lookup's window is perfect. It read +1.3% beyond the lookup on the copy
prompt and leaves a command batch open across cycles.

### D8. Outcome: kept (2026-11-18)

`ab_bench.py`, `main` against the branch (which is lookup off against on, and
also prices the code where it does nothing), resident, tokens identical in
every run, bootstrap 95% CI of the median pair ratio:

| Kind | Q2 MTP decode | Q4 MTP decode | Tokens per cycle |
|---|---|---|---|
| `mtp-copy` | 101.5 -> 106.6 t/s, **+5.0% [+4.9%, +5.1%]**, 16 pairs | 97.6 -> 101.9 t/s, **+4.7% [+4.1%, +5.0%]**, 40 pairs | 2.72 -> 2.72 |
| `mtp-code` | +0.0% [-0.1%, +0.1%], 18 pairs | +0.5% [-0.2%, +1.9%], 24 pairs | unchanged (1.91, 2.46) |
| `mtp-prose` | +0.0% [-0.1%, +0.1%], 18 pairs | +0.0% [-0.8%, +0.4%], 22 pairs | unchanged (1.44, 1.49) |

D4 keeps the change: the copy kind lies above zero on both packs and no kind
lies below. Plain decode, which runs none of the changed code, read -0.1%
[-0.3%, +0.0%] on Q4 over 22 pairs with bitwise-identical logits.

Where the gain comes from (Q4, one run of each build with the cycle trace):
on the copy prompt the predictor already drafted two right tokens in 35 of
47 cycles, so the lookup does not add committed tokens there. It supplies
the second draft from the context, and the cycle drops the predictor's
chained step: 35 of the 47 cycles verified a looked-up second draft, and
every one accepted both. Three-token cycles went from 28.4 to 26.9 ms on Q2.
On the code prompt no cycle was drafted by the lookup within its 128 tokens,
and the cycle is the old one.

So at three rows the lookup is worth about 5% where the output copies, and
nothing elsewhere. The larger gain upstream aims at needs the longer verify
chains of D5; step 0's run lengths (D6) say the material is there on tool
calls, and real edit transcripts should decide it.

The index is 8 bytes per context token plus a table of 4-byte slots, two per
token rounded up to a power of two: 2.00 MiB at a 131072-token context, 16
bytes per token, against the 89 Splash reports. Building it over 100K tokens
takes 1.24 ms; after that a cycle costs 17.8 microseconds at that length
(extension, match, and the comparison that detects a rewind), about 0.07% of
a cycle.

Gates on the final code: `make test` and the harness test; the model gates on
Q4 and Q2, all `PASS`; `PARITY OK` (10 prompts); `ab_bench.py --bitwise`
against `main`, `PASS (tokens; bitwise)`; the exact-sampling session tests
(`--session-exact-held`, `--session-rewind-resample`); and the exact-sampling
distribution test on Q2 with a prompt that makes the lookup draft (an 8-digit
number written five times; four or five lookup cycles per sample): 150 seeds,
every sampled output identical to `main`'s, 106 distinct numbers.

## Risks / Trade-offs

- **A wrong lookup wastes a verify row** the predictor might have won. The
  per-source acceptance window turns the lookup off for a stretch after
  misses.
- **The upstream commit is WIP and undocumented.** It is read and reviewed
  as new code, hunk by hunk; nothing is taken on trust.
- **Transcripts decide step 0.** Synthetic prompts overstate copying. The
  workloads must be real agent turns.
