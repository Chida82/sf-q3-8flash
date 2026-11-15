# Design

## Context

Exact sampling (`--mtp-exact-sampling`, stored in the misleadingly named
`dspark_exact_sampling`) accepts a draft with probability `p(draft)` and
otherwise samples from the residual distribution. That keeps the output
distribution equal to plain sampling. #1185 keeps the acceptance rule and
changes the timing:
- the next token is sampled inside the cycle;
- the residual sample opens the next verify;
- acceptance is applied position by position, which permits depth 3.

Greedy decoding takes a different branch, which the commit does not change,
by its author's account.

## Decisions

### D1. Rewrite onto the child's chain

The child drafts through `qwen4_session_drafts`, with `30`'s primed predictor
and `82`'s exact verify rows. Upstream's base had neither. The port keeps the
child's drafting and verify code and moves only three things:
- where the next token is sampled (held for `ds4_session_sample` at the same
  position, sampler and RNG state);
- how a rejected draft's residual sample continues;
- the per-position acceptance at depth 3.

`82`'s verify rows stay exact at depth 3, so greedy identity is unaffected by
construction. The identity check proves it.

### D2. Distribution check

A new `tests/test_qwen4_exact_sampling_dist.py --model M --a TREE --b TREE`.
It needs no model for `--help`. It runs a fixed prompt at temperature 1.0 with
`--mtp --mtp-exact-sampling` for N seeds on each build, collects the first K
generated token ids per run, and compares the two builds' empirical
distributions of each of the first K positions with a paired permutation test.
It fails when p < 0.01 at any position.

**Open question:** how #1185 measured p = 0.57 (prompt, statistic, pairing).
If the PR's test can be read (`git fetch upstream pull/1185/head`), match its
procedure so the two results compare. Otherwise use the procedure above and
say so.

The RNG sequence changes with the port (the next token is drawn one call
earlier), so per-seed outputs are expected to differ between builds. Only the
distributions must agree, which is why there is no token gate at temperature
> 0.

### D3. Speed is measured outside the harness

`ab_bench.py` and `sf-q3-8flash-bench` decode greedily, and the bench has no
sampling option. The sampled measurement is a scratch script:
- CLI runs of the harness's code and prose prompts, `--temp 1.0 --seed S
  --mtp --mtp-exact-sampling -n 256`, in ABBA pairs between `../sf-q3-8flash-prev`
  and `.`;
- decode t/s read from the CLI's timing line;
- pooled bootstrap 95% CI per kind, at the default depth and at
  `DS4_QWEN4_MTP_DEPTH=3` set inline.

The config's keep rule applies to that pooled CI. The harness runs once, with
`--bitwise` on all kinds, as the guard for greedy decoding, and gives the
record row.

### D4. Spec

The depth requirement changes: exact sampling no longer stays at depth 2. A
new requirement states the distribution property, with D2's check as its
scenario.

## Risks / Trade-offs

- **The gain was measured on a GGUF with Q8_0 down projections**, not on the
  child's Q2/Q4 packs. The forced-depth-3 figure may not carry over. D3
  measures it here; a neutral result drops the change.
- **Depth 3 at temperature > 0 widens the verify batch** on a path that has
  run only at depth 2. `82`'s verify-row exactness holds at depth 3 for greedy
  decoding. For sampled decoding, D2 is the only gate.
- **A sampler state carried across calls** (the held token) must be dropped
  on rewind, snapshot restore and session reset. A unit test covers all
  three with a held token pending.
