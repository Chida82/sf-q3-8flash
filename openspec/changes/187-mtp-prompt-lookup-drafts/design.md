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

## Risks / Trade-offs

- **A wrong lookup wastes a verify row** the predictor might have won. The
  per-source acceptance window turns the lookup off for a stretch after
  misses.
- **The upstream commit is WIP and undocumented.** It is read and reviewed
  as new code, hunk by hunk; nothing is taken on trust.
- **Transcripts decide step 0.** Synthetic prompts overstate copying. The
  workloads must be real agent turns.
