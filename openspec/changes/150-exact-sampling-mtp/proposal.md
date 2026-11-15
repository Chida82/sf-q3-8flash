# Proposal

## Why

With `--mtp --mtp-exact-sampling` at temperature > 0, the MTP cycle drafts
the next token from the argmax parent, but the caller then samples the real
next token from the same logits. Whenever that sample is not the argmax, the
pending draft is thrown away and the step runs without speculation. A rejected
draft also costs a separate one-row forward to replay its residual sample, and
exact sampling is pinned to depth 2 (`mtp-speculation`, "Draft depth follows
recent acceptance").

#1185 (`777f4e3`, one commit, about 220 lines in `ds4.c`) changes the cycle:
- it draws the next token itself, with the same sampler and RNG, one call
  earlier, and holds it for `ds4_session_sample`;
- it opens the next verify with a rejected draft's residual sample instead of
  replaying it alone;
- it applies exact acceptance position by position, which allows the depth
  2/3 policy.

The author's figures, measured on M5 Max, temperature 1.0, a Q8_0-down GGUF on
base `0aaea5a`, not reproduced here:
- undrafted cycles 663 -> 329 of about 2950;
- greedy output byte-identical on 3 prompts at both depths;
- a paired permutation test over 1500 8-digit samples, p = 0.57;
- decode +1.3..+3.4% with the default depth policy, and at
  `DS4_QWEN4_MTP_DEPTH=3` +11% on code and +15% on list-style output, with
  prose unchanged.

The commit removes upstream's `qwen4_session_draft`. The child no longer has
that function: `30` folded its copies into `qwen4_session_drafts` (with
`1cd83e3`), so the port is a rewrite onto that helper, not a cherry-pick. The exact test procedure behind p = 0.57 (prompt, which
statistic, how the pairs were formed) was not read in the review. It is an
open question for design D2.

## What Changes

- Port `777f4e3` onto the synced tree, rewritten onto the child's predictor
  chain: `qwen4_session_drafts`, `30`'s priming and `82`'s exact verify
  rows.
- Exact sampling at temperature > 0 uses the automatic depth and honours
  `DS4_QWEN4_MTP_DEPTH`.
- A sampled-decode measurement, which the A/B harness does not have (its
  kinds are greedy): CLI runs at temperature 1.0 with
  `--mtp --mtp-exact-sampling`, in ABBA pairs, on the harness's code and
  prose prompts, at the default and the forced depth 3 (design D3).
- A distribution check: the old build's sampled tokens and the new build's
  must come from the same distribution (design D2).

Greedy decoding and non-exact sampling must not change: the harness runs
`--bitwise` on every kind as the guard, and the MTP identity check at every
depth.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `mtp-speculation`: exact sampling at nonzero temperature follows the depth
  policy instead of staying at depth 2, and a requirement states that exact
  sampling keeps the target distribution.

## Impact

- `ds4.c` (Qwen speculative cycle, `ds4_session_sample` hand-off),
  possibly `ds4_cli.c`/`ds4_server.c`: `--mtp-exact-sampling` sets
  `dspark_exact_sampling`, a name that lies (AGENTS.md).
- `tests/` gets the distribution check script. `speed-bench/perf-record.md`
  gets the record row. `docs/SPECULATIVE_DECODING.md` describes exact
  sampling depth. `docs/upstream-prs.md`.
- Runs after `90` (the MTP core is the sync's largest conflict zone) and after
  `110`, if `110` changes the turn boundary of the speculative cycle.
