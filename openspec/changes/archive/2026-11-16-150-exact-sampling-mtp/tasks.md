# Tasks

Starts from `main` with `90` landed (and `110`, if it changed the speculative
cycle). `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c150/`. Model
runs are strictly sequential, each started at the Nominal thermal state.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `make test-qwen4-kernels`; `python3 tests/test_ab_bench.py`,
ending in `OK`.

## 1. Branch and references

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/150-exact-sampling-mtp`. `git fetch upstream pull/1185/head`; save `git show 777f4e3` to `$SCR/c150/`. Read the PR body and any test it carries for the procedure behind p = 0.57 (design D2, open question), and record what was found.
  Done (branch made by the caller). The PR carries no test and no test script; its body says only "1500 paired 8-digit samples show no distribution difference (paired permutation p = 0.57)". The prompt, statistic and pairing are not given, so `3.3` uses design D2's procedure on an 8-digit prompt with a seed-paired permutation test, which is the closest reading.
- [x] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it. Write the segment start row first if the current segment has none after `90`.
  Done with the caller's read-only built tree `.claude/worktrees/prev-main` (main `ceccded`, code equal to `a1e754e`) in place of `../sf-q3-8flash-prev`. Segment 1 has its start row (`91f225a`, worktree `.claude/worktrees/seg1-91f225a`), so no new one.

## 2. Step S1: the port (design D1)

- [x] 2.1 Rewrite `777f4e3` onto `qwen4_session_drafts`, keeping `30`'s priming and `82`'s verify rows. Exact sampling takes the depth policy and `DS4_QWEN4_MTP_DEPTH`.
- [x] 2.2 Drop the held next token on rewind, snapshot restore and reset. Add a model-backed `ds4_test` entry that holds a token, rewinds one position, and checks that the next sample comes from the rewound logits.
  `ds4_test --session-exact-held` (needs `DS4_TEST_GLM_MTP` and `DS4_TEST_MTP_EXACT`): a held token is returned without touching the RNG; after a rewind by one plus a different token back to the held length, a snapshot restore, and a resync to the held length with a different last token, the next sample advances the RNG and equals `ds4_sample_logits` on the current logits. Removing the rewind or the sync drop makes it fail (checked); the snapshot case is covered by the position check as well as the drop. The drop also sits in `ds4_session_invalidate`, `ds4_session_load_payload` and `ds4_session_set_logits`.
- [x] 2.3 Run the step checks, then the step review.

## 3. Correctness gates

- [x] 3.1 `python3 tests/test_qwen4_mtp_identity.py --model <Q4>`: every prompt and depth identical (greedy unchanged).
  PASS: 0 of 36 MTP runs differ from plain.
- [x] 3.2 `python3 tests/test_qwen4_mtp_limits.py --model <Q4>` passes.
  PASS one-row, two-rows-depth-three, unfused.
- [x] 3.3 Write `tests/test_qwen4_exact_sampling_dist.py` (design D2). Verify that `--help` exits 0 without a model. Run it on `../sf-q3-8flash-prev` against `.`: no position with p < 0.01. Record N, K and the p values.
  `--depth 3` (the new path; prev pins exact sampling to depth 2 regardless), prompt "Write a random 8-digit number. Reply with the number only.", N = 500 seeds per build, K = 8 digits, 2000 paired permutations: p = 1.000, 1.000, 0.955, 0.729, 0.687, 0.953, 0.049, 0.344 (positions 0-1 are near-deterministic for this model). PASS, min p 0.049 >= 0.01.
- [x] 3.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q4> --bitwise --budget 600`: `PASS (tokens; bitwise)` on every kind.
  PASS (tokens; bitwise), 20 pairs; every headline metric within -0.1..+0.1%.

## 4. Sampled speed (design D3)

- [x] 4.1 ABBA CLI pairs at temperature 1.0 with `--mtp --mtp-exact-sampling`, code and prose prompts, default depth: pooled bootstrap 95% CI of decode t/s per kind. Record in `$SCR/c150/steps.txt`.
  Prompts: the first 6500 bytes of `rax.c` and 7000 of `promessi_sposi.txt` with a continue instruction, `--nothink -n 384`, seeds paired per half-quad (A s, B s, B s+1, A s+1), 12 quads per kind, start at Nominal. Code: A 67.56, B 70.72 t/s, +4.89% (95% CI +1.56..+7.87%). Prose: A 55.72, B 57.20 t/s, +2.67% (CI +1.26..+4.13%).
- [x] 4.2 The same at `DS4_QWEN4_MTP_DEPTH=3`, set inline.
  8 quads. Code +18.61% (CI +13.31..+23.65%), prose -11.87% (CI -14.88..-9.08%): the pin is for code, the automatic policy keeps prose at depth 2. A trace at the pin shows 30 of 55 cycles committing three tokens on code.
- [x] 4.3 Keep the change if, at the default depth, one kind's CI lies above zero and no kind's lies wholly below zero. A neutral result drops it: it adds lines.
  Kept: both kinds' CIs lie above zero at the default depth.

## 5. Review and closing

- [x] 5.1 Final pass over the touched region; measure refinements like a step.
  No refinement beyond the port: the one-row replay of a residual sample is gone with upstream's change; the extra drop sites are correctness, not speed.
- [x] 5.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. Then `ab_bench.py` against the current segment's start; append the row with step `perf/150-exact-sampling-mtp`. Add 4.1's sampled figures to the commit message, since the harness has no sampled kind.
  Parity: every prompt token-identical to upstream `b3f5018`; speed within 2% on 9 prompts, prompt 5 (one-number answer, run spread 18-20%) -12.4% median of 5. `prev-main` (main, without this change) fails the same prompt the same way (-13.0%), so it is not this change; left as an open point for the owner. Segment row against `91f225a`: PASS (tokens), 24 pairs, appended.
- [x] 5.3 `docs/SPECULATIVE_DECODING.md`: exact sampling follows the depth policy. `docs/upstream-prs.md`: `777f4e3` to `adopt -> 150-exact-sampling-mtp` with the figures, or `drop` with them.
- [x] 5.4 `openspec validate 150-exact-sampling-mtp --strict` passes.
- [x] 5.5 Report to the user in Italian. Commit only when the owner asks: one signed commit, with the PR author as `Co-authored-by`.
  `tests/model_gates.sh` with the mmproj and the `orbit`/`maple` fixtures: all PASS on Q4 and on Q2; `--session-exact-held` and `--session-rewind-resample` with `DS4_TEST_MTP_EXACT=1` OK on both.
  The owner pre-authorised landing on green gates: one signed commit on the branch, not merged into `main`.
