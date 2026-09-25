# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `$SCR` is the session scratch dir; this change's files go in
`$SCR/c60/` (copy `$SCR/c50/pool.py` there). `X` is the pathspec `-- .
':!openspec'`. Before each harness or section-time run, wait until the thermal
state is Nominal and the GPU is below 55 °C. Nothing else heavy may be
resident while a model runs, and no `metal/*.metal` edit while one runs from
the tree.

"The step review" (design D8): read `git diff <previous snapshot> X` and every
function it touches in full; record findings in `$SCR/c60/review.md` as *fix
now* or *refine later* with site and reason; apply the *fix now* ones and
re-run the step checks.

"The step checks" (design D6):

- `make -j8` with no warnings;
- `make test -j8`, whose output names the suites;
- `make test-qwen4-kernels`, ending in `all qwen4 kernel tests passed`, with
  `grep 'hash='` of its output equal to `$SCR/c60/hash-base.txt` (from S0 on);
- `make test-qwen4-q2`, printing `all Qwen MoE decode specialization tests
  passed`.

"The section times": `DS4_QWEN4_TIMING=2 ./sf-q3-8flash -m <Q4> --temp 0
--nothink -n 8 -p "$(head -c 12000 speed-bench/promessi_sposi.txt)"
--prefill-chunk 2048`, then the same with `--prefill-chunk 512`; record the
per-chunk lines (mean over the full chunks) in `$SCR/c60/steps.txt`.

"The verdict" (design D7): pool the step's runs with `python3 $SCR/c60/pool.py
$SCR/c60 <kind> <dirs>` and `--prefill <frontier>` for 8192, 8704 and 10752
(plain) and 2048 (mtp-code, mtp-prose), plus plain decode; keep or drop by D7;
if kept, snapshot `T_n` and move `../sf-q3-8flash-prev` to it (`git -C
../sf-q3-8flash-prev restore --source=T_n --staged --worktree -- .`, then
`make -j8` there); if dropped, `git restore --source=<previous kept snapshot>
--staged --worktree X`; record the figures in `$SCR/c60/steps.txt`.

## 1. Branch and references

- [x] 1.1 From `main`, with only this change's `openspec/` artifacts modified, `git config rerere.enabled true` and `git switch -c perf/60-q4-expert-prefill`. Verify `git status --short --branch`.
- [x] 1.2 Situation 0: `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout. Verify `PARITY OK (10 prompts)`; on a speed trip alone, re-run once after a cool-down before asking.
- [x] 1.3 Snapshots: `git add -A X`, `T_0=$(git write-tree)` in `$SCR/c60/steps.txt`; `git worktree add --detach ../sf-q3-8flash-prev main` and `git worktree add --detach ../sf-q3-8flash-start 91f225a`. Verify both build `sf-q3-8flash-bench`.

## 2. Step S0: prefill MoE cuts and the bit pin

- [x] 2.1 Add the `moe_mid` and `moe_down` cuts to the tile branch of `qwen4_graph_moe` (design D2), and one sentence on them to the `DS4_QWEN4_TIMING=2` paragraph of `docs/METAL.md`. Verify the step checks pass (hash comparison not yet).
- [x] 2.2 Give `test_moe_mm_tiles_exact` a T parameter and add the T 75 calls next to the T 641 ones (design D2). Verify its count check reads 75/38/37/0 and the `hash=` lines print for both T at levels 1..5.
- [x] 2.3 Save `make test-qwen4-kernels 2>&1 | grep 'hash='` to `$SCR/c60/hash-base.txt`; run it twice more and verify the three outputs are identical (the pin must be deterministic).
- [x] 2.4 With the model: greedy output of the section-times run equals a run without `DS4_QWEN4_TIMING`; the chunk lines show `moe_mid` and `moe_down`. Record them as the baseline breakdown.
- [x] 2.5 The step review against `T_0`.
- [x] 2.6 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c60/ab-s0`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 2.7 The verdict, tool-step rule. If kept, `T_S0`.

## 3. Step O5a: Q4_K words held across K steps

- [x] 3.1 In both tile kernels, hold the Q4_K header and quant words across K steps (design D3); other types keep the per-step load. Verify the step checks pass, including the hash pin.
- [x] 3.2 The step review; the section times.
- [x] 3.3 `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c60/ab-o5a`. Verify `PASS (tokens; bitwise)`.
- [x] 3.4 The verdict.

## 4. Step O5b: MXFP4 aligned word loads

- [x] 4.1 In `qwen4_load_raw16` type 39, aligned word loads for every block but the row's last (design D3). Verify the step checks pass, including the hash pin.
- [x] 4.2 The step review; the section times.
- [x] 4.3 `ab_bench.py ... --out $SCR/c60/ab-o5b`. Verify `PASS (tokens; bitwise)`.
- [x] 4.4 The verdict.

## 5. Step O6: double-buffered A/B tiles

- [x] 5.1 Double-buffer A and B in both tile kernels with one barrier per K step, and resize the host threadgroup memory (design D4); COMP mid keeps one buffer through a template parameter if 32 KB does not fit. Verify the step checks pass, including the hash pin at all levels, and that every tile pipeline still reports 128 max threads per threadgroup.
- [x] 5.2 The step review; the section times.
- [x] 5.3 `ab_bench.py ... --out $SCR/c60/ab-o6`. Verify `PASS (tokens; bitwise)`.
- [x] 5.4 The verdict.

## 6. Step O7: tile width by tokens per expert

- [x] 6.1 Probe (design D5): the kernel tests with `DS4_QWEN4_MOE_TAILS=0` against `hash-base.txt`, and the achieved bandwidth of `moe_mid`/`moe_down` at chunk 512 and 2048 from the section times. Record both in `$SCR/c60/steps.txt`. If the hashes differ or the tiles are bandwidth-bound, record O7 as dropped with the numbers and go to 7.
- [x] 6.2 Add the 16- and 8-token instances and the host width choice (design D5). Verify the step checks pass, including the hash pin, and add T 75 at width 16 and 8 through the env override to the pin.
- [x] 6.3 The step review; the section times.
- [x] 6.4 `ab_bench.py ... --out $SCR/c60/ab-o7`. Verify `PASS (tokens; bitwise)`.
- [x] 6.5 The verdict.

## 7. Review and refine (design D8)

- [x] 7.1 Read the whole region in full and write the "final pass" section of `$SCR/c60/review.md`, each finding *take* or *leave* with its reason, settling D8's questions.
- [x] 7.2 Apply the *take* findings. Verify the step checks pass and `rg` finds no reference to anything removed.
- [x] 7.3 (The refinement was a comment only, so the shader code is unchanged: checks and pin re-run, no A/B.) `ab_bench.py ... --out $SCR/c60/ab-refine` against the last kept step. Verify `PASS (tokens; bitwise)` and no metric's pooled CI wholly below 0; a finding that fails is reverted and marked *leave (measured)*.
- [x] 7.4 Snapshot `T_refine`, or record "no refinement".

## 8. Registry, closing

- [x] 8.1 `docs/upstream-prs.md`: the #864 cell, the `496b153` line and the #1056 summary with each step's outcome (design D9). Verify `rg -n '60-q4-expert-prefill|`60`' docs/upstream-prs.md` shows no line that still reads as an unmeasured plan.
- [x] 8.2 End checks: `python3 tests/test_qwen4_mtp_limits.py --model <Q4>` and `tools/parity-check.sh sf-q3-8flash <Q4>`. Verify each passes.
- [x] 8.3 Change result: bring `../sf-q3-8flash-prev` to `main` and run `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c60/ab-final`. Verify `PASS (tokens; bitwise)`; record the figures with the first and last section times.
- [x] 8.4 Record row: `ab_bench.py --a ../sf-q3-8flash-start --b . --out $SCR/c60/ab-record`; append its `record row:` to Segment 1 with step `perf/60-q4-expert-prefill` and B-commit `this row's commit`.
- [x] 8.5 Final snapshot. Verify `openspec validate 60-q4-expert-prefill --strict` passes and `git diff --cached --stat main` lists only the files the steps touched.
- [x] 8.6 Report to the user in Italian: each step's verdict with figures and section times, the review's findings, the change result and record row, the decisions taken. Do not commit; on request land one signed commit on `main` (design D1) and remove the two worktrees.

## 9. Post-review fixes

- [x] 9.1 `test_moe_mm_tiles_exact` asserts level 2 equal to level 1 and level 4 equal to level 3 byte for byte, and runs at T 161 too (remainders 33/17/16). Verify the kernel tests pass and every hash line equals the one the same test prints on a worktree of `main`.
- [x] 9.2 Restore upstream's per-kernel `tails:` comments; name the 16/8 tails on the `narrow` line. Correct the S0 enum comment and `docs/METAL.md`: for T <= 8 `moe_mid`/`moe_down` include the shared expert's slot, and the grouped path is not split.
- [x] 9.3 `docs/upstream-prs.md`: the `496b153` line gives O7's GPU-time effect instead of its prefill 8192 step median.
- [x] 9.4 `$SCR/c60/pool.py` leaves out the pairs the harness drops; recompute the step CIs in `$SCR/c60/steps.txt` and verify no verdict changes.

