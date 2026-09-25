# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `$SCR` is the session scratch dir. `X` is the pathspec
`-- . ':!openspec'` (design D3). Before each harness invocation,
wait until the thermal state is Nominal and the GPU is below 55 °C (preflight
refuses otherwise). Nothing else heavy may be resident while a model runs.

"The step review" (design D11) means:

1. Read `git diff <previous snapshot> X` and every function it touches in
   full.
2. Add each finding to `$SCR/review.md` as *fix now* or *refine later*, with
   its site and reason.
3. Apply the *fix now* findings in the step and re-run the step's checks.

## 1. Branch and references

- [x] 1.1 From `main`, with only this change's `openspec/` artifacts modified, run `git config rerere.enabled true` and `git switch -c perf/30-mtp-cycle`. Verify `git status --short --branch` shows the new branch and changes under `openspec/changes/30-mtp-cycle/` only.
- [x] 1.2 Situation 0: from the StarForge checkout run `tools/parity-check.sh sf-q3-8flash <Q4>`. Verify it prints `PARITY OK (10 prompts)`. If not, stop and ask: `main` is not a valid reference.
- [x] 1.3 Start row (design D7): `git worktree add --detach ../sf-q3-8flash-start 91f225a`, then `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-start --b ../sf-q3-8flash-start`. Verify exit 0, paste its `record row:` as the first row of Segment 1 in `speed-bench/perf-record.md`, and make the "Start commit" line name `91f225a`.
- [x] 1.4 Snapshots (design D3): `git add -A X`, and record `T_0=$(git write-tree)` in `$SCR/mtp-steps.txt` (the start row). Run `git worktree add --detach ../sf-q3-8flash-prev main`. Verify `git diff --cached --stat` lists only `speed-bench/perf-record.md`, and that `make -C ../sf-q3-8flash-prev -j8 sf-q3-8flash-bench` builds.

## 2. Step 1: priming (`acce8da`)

- [x] 2.1 `git cherry-pick -n acce8da`. Resolve the batched speculative entry per design D2 (the PR's tail-flush loop, keeping `if (!ds4_gpu_end_commands()) ok = false;`), and pass `1u` as the row count in the stage and combine calls of `qwen4_batch_mtp_drafts`. Verify `rg -n '^(<<<<<<<|>>>>>>>)' ds4.c ds4_gpu.h ds4_metal.m metal tests` prints nothing and `make -j8` prints no warnings.
- [x] 2.2 Model-less and fast checks (design D6). Verify:
  - `make test -j8` passes, and its output names the suites (AGENTS.md rule 19);
  - `make test-qwen4-kernels` ends in `all qwen4 kernel tests passed`;
  - `python3 tests/test_qwen4_mtp_limits.py --model <Q4>` exits 0.
- [x] 2.3 The step review against `T_0`. Verify `$SCR/review.md` has a "step 1" section in which every finding has a class and a reason, and that 2.2 still passes after the *fix now* edits.
- [x] 2.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code,mtp-prose`. Verify exit 0 and keep the summary in `$SCR/step1.txt`.
- [x] 2.5 Bitwise probe (design D6): `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code --bitwise --preheat 0 --budget 60`. It passes on exit 3, or on exit 1 whose message names `frontier_002048.decode.logits.json`. A message naming the prefill dump fails the step.
- [x] 2.6 Verdict (design D5, with step 1's 5% prefill allowance).
  - If the step is dropped, stop the change and report with the figures (design Risks).
  - If it is kept: `git add -A X`, record `T_1=$(git write-tree)` and the verdict in `$SCR/mtp-steps.txt`, and run `git -C ../sf-q3-8flash-prev restore --source=T_1 --staged --worktree -- .`.

  Verify `git -C ../sf-q3-8flash-prev diff --cached --stat main` equals `git diff --cached --stat main`.

## 3. Step 2: three-row geometry (`be4cec8`)

- [x] 3.1 `git cherry-pick -n be4cec8`. Verify it applies without conflicts, `make -j8` prints no warnings, and the checks of 2.2 pass.
- [x] 3.2 The step review against `T_1`, as in 2.3.
- [x] 3.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code --env DS4_QWEN4_MTP_DEPTH=3`. Verify exit 0, and that the summary shows k3 cycles for both builds.
- [x] 3.4 Verdict (design D5).
  - If kept: snapshot `T_2` and move `../sf-q3-8flash-prev` to it, as in 2.6.
  - If dropped: restore the previous kept snapshot (`T_1` here) with `git restore --source=T_1 --staged --worktree X`, and record the figures.

## 4. Step 3: depth policy (`926ee12`)

- [x] 4.1 `git cherry-pick -n 926ee12`, then delete the second `qwen4_ema` definition so that one remains, the earlier one in `ds4.c` (design D2). Verify `rg -c 'static float qwen4_ema' ds4.c` prints 1, `make -j8` prints no warnings, and the checks of 2.2 pass.
- [x] 4.2 The step review against the previous kept snapshot, as in 2.3.
- [x] 4.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code,mtp-prose`. Verify exit 0.
- [x] 4.4 Verdict (design D5). The spec requires prose MTP decode not below A beyond its noise floor. Snapshot `T_3`, or restore, as in 3.4.

## 5. Step 4: GPU embedding gather (`0a89a04`)

- [x] 5.1 `git cherry-pick -n 0a89a04`, then:
  - resolve the two name-only conflicts with `qwen4_graph_begin_commands_if_needed`;
  - rewrite `qwen4_batch_mtp_drafts` to write the N ids to `mtp_next`, then make one `qwen4_mtp_stage` call and one combine over N rows (design D2, as the PR head `1ab00b5` does, without its `head_rows`).

  Verify `rg -n 'glm_graph_begin_commands_if_needed|qwen4_ref_row\(m, w->token_embd, \(uint64_t\)ids' ds4.c` prints nothing, `make -j8` prints no warnings, and the checks of 2.2 pass.
- [x] 5.2 The step review against the previous kept snapshot, as in 2.3.
- [x] 5.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code,mtp-prose --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)`, and tokens per cycle equal (ratio 1.000, range [1.000, 1.000]) on both kinds.
- [x] 5.4 Verdict (design D5, neutral keeps). Snapshot `T_4`, or restore, as in 3.4.

## 6. Step 5: chained second draft (`1cd83e3`)

- [x] 6.1 `git cherry-pick -n 1cd83e3`. Resolve the name-only conflicts as in 5.1, and pass `NULL` as the new argmax row-list argument in `qwen4_batch_mtp_drafts`. Verify `rg -n 'qwen4_graph_mtp_chain_step' ds4.c` prints nothing, `make -j8` prints no warnings, and the checks of 2.2 pass.
- [x] 6.2 The step review against the previous kept snapshot, as in 2.3.
- [x] 6.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code --env DS4_QWEN4_MTP_DEPTH=3 --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)` and tokens per cycle equal.
- [x] 6.4 Verdict (design D5). Snapshot `T_5`, or restore, as in 3.4.

## 7. Step 6: cache-only priming (optional, design D9)

- [x] 7.1 Read step 1's prefill 2048 ratio from `$SCR/step1.txt`. If both MTP kinds are at 0.97 or above, record "not attempted" with the figure in `$SCR/mtp-steps.txt`, mark 7.2-7.5 done as not applicable, and go to section 8.
- [x] 7.2 In the priming loop, stop the nextn layer after its cache writes for history rows: the attention input mix, then K, V and indexer-K with their norm, RoPE and cache writes, through the same calls the full path makes. The tail row keeps the full pass. Verify `make -j8` prints no warnings and the checks of 2.2 pass.
- [x] 7.3 The step review against the previous kept snapshot, as in 2.3. This code is the child's own, so the review holds it to the same bar as the ported steps.
- [x] 7.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code --budget 600 --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)` and tokens per cycle equal, and read the prefill 2048 ratio.
- [x] 7.5 Verdict (design D5, target: prefill 2048 with `--mtp`). Snapshot `T_6`, or restore, as in 3.4.

## 8. Review and refine the ported code (design D11)

- [x] 8.1 Read the whole MTP region as it now stands, not only the diffs:
  - the predictor pass and the priming/tail functions;
  - the spec cycle and the depth policy;
  - the batched predictor and the batched speculative entry;
  - the stage/combine/argmax wrappers in `ds4_metal.m` and their kernels in `metal/qwen4.metal`;
  - their cases in `tests/test_qwen4_kernels.c`.

  Judge it against the D11 criteria, and add to `$SCR/review.md` a "final pass" section with every finding (the *refine later* ones from the step reviews included), each marked *take* or *leave* with its reason. Verify every function of the region appears in the section, with findings or "none".
- [x] 8.2 Apply the *take* findings. Verify:
  - `make -j8` prints no warnings and the checks of 2.2 pass;
  - `rg` finds no remaining reference to any helper, field or environment variable the pass removed;
  - `$SCR/review.md` names every file the pass touched.
- [x] 8.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code,mtp-prose --bitwise`, where `../sf-q3-8flash-prev` is the last kept step. Verify:
  - exit 0 with `PASS (tokens; bitwise)`;
  - tokens per cycle equal;
  - no headline metric below 1 by more than its noise floor.

  A finding that fails this gate is reverted and marked *leave (measured)* in `$SCR/review.md`.
- [x] 8.4 Snapshot `T_refine` (`git add -A X`, then `git write-tree`), and draft its commit message: one line per refinement, with its reason. If the pass took nothing, record "no refinement" instead; no commit follows. Verify `$SCR/mtp-steps.txt` has the entry.

## 9. End-to-end correctness (design D6)

- [x] 9.1 `DS4_TEST_MODEL=<Q4> DS4_TEST_GLM_MTP=1 ./ds4_test`. Verify it exits 0 and that its output shows the session-rewind, qwen4-restore-reuse, prefill-checkpoint and snapshot tests running rather than `skipped`. Result: those four pass. The run exits 1 on five failures that are identical on the start commit `91f225a`: `long-context` ("Priya: got 9 expected 97"), `metal-short-prefill`, and three suites whose reference files are missing on this machine (`logprob-vectors`, `local-golden-vectors`, `metal-ssd-streaming-cache-pressure`).
- [x] 9.2 `make tests/test_qwen4_ngram_state && ./tests/test_qwen4_ngram_state <Q4>`. Verify exit 0.
- [x] 9.3 `make session-concurrency-bench && ./speed-bench/session_concurrency_bench -m <Q4> --spec --verify --concurrency 2 --ctx 4096`. Verify there is no `spec verify failed` line and the exit status is 0.
- [x] 9.4 `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>`. Verify exit 0.
- [x] 9.5 Make two PNGs in `$SCR` with `sips` from two different system icons, then run `python3 tests/test_qwen4_cli_vision.py --model <Q4> --vision gguf/mmproj-Qwen3.8-Flash-Next-Q8_0.gguf --image A.png --image B.png --out-dir $SCR/vision`. Verify `PASS ordinary` and `PASS mtp`, and that `cmp $SCR/vision/ordinary.stdout $SCR/vision/mtp.stdout` succeeds. Result: both PASS, but ordinary and MTP differ from the second turn on, identically on `91f225a` (pre-existing; design Risks). The final tree's MTP and ordinary outputs are byte-identical to the start's, which is the revised spec scenario.
- [x] 9.6 Cross-build checkpoint check (design D8), in both directions. Each build's server answers two turns of a ~3k-token `--mtp` conversation with a disk-KV directory and shuts down; then each build answers the third turn from each directory. Verify that every read reuses the checkpoint and that a cross read answers byte for byte like the same-build read. Record the hashes in `$SCR/mtp-steps.txt`. Result: all four reads have 3151 cached tokens and hash `73048eb385889f4f`.

## 10. Registry and docs (design D10)

- [x] 10.1 In `docs/upstream-prs.md`:
  - update the lines of `acce8da`, `be4cec8`, `926ee12`, `0a89a04`, `1cd83e3`, `b86c8ae` and `a6ad636` with the verdicts and figures from `$SCR/mtp-steps.txt`;
  - update the #1062 summary cell and "Last review" if needed.

  Verify `rg -n '30-mtp-cycle' docs/upstream-prs.md` shows no line that still reads as an unmeasured plan.
- [x] 10.2 In `docs/SPECULATIVE_DECODING.md`, replace "adaptively uses depth two or three" with the priming (text prompts only) and the measured depth rule. Keep the `DS4_QWEN4_MTP_DEPTH` pin and the test commands. Verify the file names neither DSpark nor an external support model.

## 11. Closing

- [x] 11.1 From the StarForge checkout, `tools/parity-check.sh sf-q3-8flash <Q4>`. Verify `PARITY OK (10 prompts)`, including the `--mtp` prompt. Result: the first run had all 10 prompts token-identical but tripped on prompt 5's speed (-15.8% median, 17% run spread; upstream's own speed on it moved from 53.9 to 45.6 t/s). The rerun after a cool-down printed `PARITY OK (10 prompts)`, with prompt 5 at +2.0%.
- [x] 11.2 Plain bit-identity (design D7): `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-start --b . --kinds plain --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)` and plain ratios within the noise floor.
- [x] 11.3 Final record row (design D7): `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-start --b .`. Verify exit 0, and append its `record row:` to Segment 1 with the `step` cell `perf/30-mtp-cycle`.
- [x] 11.4 Final snapshot: `git add -A X`, then record `T_final=$(git write-tree)` (registry, docs, final row). Verify:
  - `openspec validate 30-mtp-cycle --strict` passes;
  - `git diff --cached --stat main` lists only `ds4.c`, `ds4_gpu.h`, `ds4_metal.m`, `metal/qwen4.metal`, `tests/test_qwen4_kernels.c`, the two docs, `speed-bench/perf-record.md`, and any file the final pass named in `$SCR/review.md`.
- [x] 11.5 Report to the user in Italian: each step's verdict with figures, the review findings taken and left, the start and final record rows, and the decisions taken. Do not commit.

  When the user asks, replay as signed commits per design D1/D3: for `T_0`, each kept `T_k`, `T_refine` (if any) and `T_final`, in that order, run `git restore --source=<T> --staged --worktree X` and `git commit`. Before the last commit, replace the `pending commit` cell of the final record row with the short SHA of the refinement commit, which holds the measured code. The last commit also runs `git add openspec`. Then remove the `../sf-q3-8flash-prev` and `../sf-q3-8flash-start` worktrees.
