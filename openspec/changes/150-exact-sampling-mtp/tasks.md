# Tasks

Starts from `main` with `90` landed (and `110`, if it changed the speculative
cycle). `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c150/`. Model
runs are strictly sequential, each started at the Nominal thermal state.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `make test-qwen4-kernels`; `python3 tests/test_ab_bench.py`,
ending in `OK`.

## 1. Branch and references

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/150-exact-sampling-mtp`. `git fetch upstream pull/1185/head`; save `git show 777f4e3` to `$SCR/c150/`. Read the PR body and any test it carries for the procedure behind p = 0.57 (design D2, open question), and record what was found.
- [ ] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it. Write the segment start row first if the current segment has none after `90`.

## 2. Step S1: the port (design D1)

- [ ] 2.1 Rewrite `777f4e3` onto `qwen4_session_drafts`, keeping `30`'s priming and `82`'s verify rows. Exact sampling takes the depth policy and `DS4_QWEN4_MTP_DEPTH`.
- [ ] 2.2 Drop the held next token on rewind, snapshot restore and reset. Add a model-backed `ds4_test` entry that holds a token, rewinds one position, and checks that the next sample comes from the rewound logits.
- [ ] 2.3 Run the step checks, then the step review.

## 3. Correctness gates

- [ ] 3.1 `python3 tests/test_qwen4_mtp_identity.py --model <Q4>`: every prompt and depth identical (greedy unchanged).
- [ ] 3.2 `python3 tests/test_qwen4_mtp_limits.py --model <Q4>` passes.
- [ ] 3.3 Write `tests/test_qwen4_exact_sampling_dist.py` (design D2). Verify that `--help` exits 0 without a model. Run it on `../sf-q3-8flash-prev` against `.`: no position with p < 0.01. Record N, K and the p values.
- [ ] 3.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q4> --bitwise --budget 600`: `PASS (tokens; bitwise)` on every kind.

## 4. Sampled speed (design D3)

- [ ] 4.1 ABBA CLI pairs at temperature 1.0 with `--mtp --mtp-exact-sampling`, code and prose prompts, default depth: pooled bootstrap 95% CI of decode t/s per kind. Record in `$SCR/c150/steps.txt`.
- [ ] 4.2 The same at `DS4_QWEN4_MTP_DEPTH=3`, set inline.
- [ ] 4.3 Keep the change if, at the default depth, one kind's CI lies above zero and no kind's lies wholly below zero. A neutral result drops it: it adds lines.

## 5. Review and closing

- [ ] 5.1 Final pass over the touched region; measure refinements like a step.
- [ ] 5.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. Then `ab_bench.py` against the current segment's start; append the row with step `perf/150-exact-sampling-mtp`. Add 4.1's sampled figures to the commit message, since the harness has no sampled kind.
- [ ] 5.3 `docs/SPECULATIVE_DECODING.md`: exact sampling follows the depth policy. `docs/upstream-prs.md`: `777f4e3` to `adopt -> 150-exact-sampling-mtp` with the figures, or `drop` with them.
- [ ] 5.4 `openspec validate 150-exact-sampling-mtp --strict` passes.
- [ ] 5.5 Report to the user in Italian. Commit only when the owner asks: one signed commit, with the PR author as `Co-authored-by`.
