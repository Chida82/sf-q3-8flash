# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `$SCR` is the session scratch dir, and this change's files go in
`$SCR/c50/`. `X` is the pathspec `-- . ':!openspec'`. Before each harness or
section-time run, wait until the thermal state is Nominal and the GPU is below 55 °C.
Nothing else heavy may be resident while a model runs.

"The step review" (design D5) means:

1. Read `git diff <previous snapshot> X` and every function it touches in
   full.
2. Record the findings in `$SCR/c50/review.md` as *fix now* or *refine
   later*, with their site and reason.
3. Apply the *fix now* findings in the step and re-run its checks.

"The step checks" (design D3) means:

- `make -j8` with no warnings;
- `make test -j8`, whose output names the suites;
- `make test-qwen4-kernels`, ending in `all qwen4 kernel tests passed`;
- `make test-qwen4-q2`, printing `all Qwen MoE decode specialization tests
  passed`.

"The section times" (design D1, from S0 on) means:

1. In the working tree, run `DS4_QWEN4_TIMING=2 ./sf-q3-8flash -m <Q4> --temp 0
   --nothink -n 128 -p "Write a short story about a lighthouse keeper who finds
   a message in a bottle."`.
2. Record the T = 1 summary lines (mean GPU µs per token for each group, one
   per 50 passes) in `$SCR/c50/steps.txt`.

"The verdict" (design D4) means:

- pool the step's A/B runs with `python3 $SCR/c50/pool.py $SCR/c50 <kind> <dirs>`
  for plain, mtp-code and mtp-prose;
- keep or drop by D4's rule;
- if kept, snapshot `T_n` and move `../sf-q3-8flash-prev` to it
  (`git -C ../sf-q3-8flash-prev restore --source=T_n --staged --worktree -- .`,
  then `make -j8` there);
- if dropped, `git restore --source=<previous kept snapshot> --staged --worktree X`;
- record the figures in `$SCR/c50/steps.txt`.

## 1. Branch and references

- [x] 1.1 From `main`, with only this change's `openspec/` artifacts modified, run `git config rerere.enabled true` and `git switch -c perf/50-q4-expert-decode`. Verify `git status --short --branch` shows the new branch.
- [x] 1.2 Situation 0: `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout. Verify `PARITY OK (10 prompts)`; if the only failure is a speed trip, re-run once after a cool-down before stopping to ask.
- [x] 1.3 Snapshots:
  - `git add -A X`, then record `T_0=$(git write-tree)` in `$SCR/c50/steps.txt`;
  - `git worktree add --detach ../sf-q3-8flash-prev main` and `git worktree add --detach ../sf-q3-8flash-start 91f225a`.

  Verify both worktrees build `sf-q3-8flash-bench`.

## 2. Step S0: GPU section times

- [x] 2.1 Implement the section profiler of design D2:
  - `ds4_gpu_take_gpu_seconds()` in `ds4_metal.m`/`ds4_gpu.h`, fed by an always-on GPU-span total in `ds4_gpu_wait_command_buffer`, which `DS4_METAL_GPU_BUSY_PROFILE` keeps printing from;
  - `QWEN4_PROF` turned into a cut over `g->prof`, run for every T;
  - the `moe_mid`, `moe_down` and `head` cuts;
  - the T > 8 per-chunk line in GPU ms, and the T <= 8 per-T summary every 50 passes.

  Verify the step checks pass.
- [x] 2.2 Verify with the model:
  - the greedy output of the section-times run matches a run without `DS4_QWEN4_TIMING`;
  - its T = 1 `moe_mid`, `moe_down` and `head` means are within 5% of 2640, 1435 and 1149.7 µs;
  - a run with a prompt over 64 tokens still prints the per-chunk prefill line.

  Record the whole T = 1 line in `$SCR/c50/steps.txt` as the baseline breakdown.
- [x] 2.3 Add `DS4_QWEN4_TIMING=2` to the inline diagnostics in `docs/METAL.md`, one sentence on what the summary reports.
- [x] 2.4 The step review against `T_0`. Verify `$SCR/c50/review.md` has a "step S0" section.
- [x] 2.5 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-s0`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 2.6 The verdict, by the tool-step rule: no metric's pooled CI wholly below 0. If kept, the snapshot is `T_S0`.

## 3. Step O2: per-token Q4_K gate/up through the decode-batch pass

- [x] 3.1 In `metal/qwen4.metal`, change `qwen4_moe_mid_q4k_pass` to take the pairs' input rows and output rows (design D2).
  - Build them in `kernel_qwen4_moe_mid_q4k_grouped` from its list.
  - Make `kernel_qwen4_moe_mid_q4k<NR>` call the pass with NJ 1 for routed slots, and delete its own block loop.
  - Keep the shared slot and the invalid-expert branch where they are.

  Verify the step checks pass, in particular `test_q4k_ordered_exact` (all NR/NSG, shared and unshared, F 640/641) and `test_moe_grouped`.
- [x] 3.2 The step review against `T_S0`, the S0 snapshot. Verify `$SCR/c50/review.md` has a "step O2" section.
- [x] 3.3 The section times on the step's tree.
- [x] 3.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-o2`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 3.5 The verdict. O2 may be kept as neutral if its diff deletes more lines than it adds.

## 4. Step O3: MXFP4 down in row pairs on M5

- [x] 4.1 Make the grouped down pass's body a helper over one row pair, with the pairs' `mid` rows and output rows passed in (design D2).
  - Make `kernel_qwen4_moe_down_mxfp4_pf` walk its rows two at a time through it.
  - Make `qwen4_moe_mv_rows()` take the weight type and default to 2 for MXFP4 on M5.
  - Add `test_moe_types(&arena, 8, 6, 2560, 640, 3, 12u, 39u)` to the `DS4_TEST_QWEN4_MV_EXACT` list.

  Verify the step checks pass, and that `make test-qwen4-q2` prints the prefetched-vs-plain and NR/NSG lines for the new T = 3 case.
- [x] 4.2 The step review against the previous kept snapshot.
- [x] 4.3 The section times on the step's tree.
- [x] 4.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-o3`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 4.5 The verdict.
- [x] 4.6 O3b, only if O3 was kept: make `qwen4_moe_mv_groups()` default to 8 for MXFP4 on M5. Run the step checks, the section times and `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-o3b`, then give the verdict. Verify the outcome is in `$SCR/c50/steps.txt`.

## 5. Step O4: shared Q8 gate/up with one activation load

- [x] 5.1 Add `qwen4_moe_shared_q8_mid` with `13c53d9`'s loop (design D2) and call it from the Q4_K kernel's shared branch when `shared_type == 8`. Other types keep the two row dots. Verify the step checks pass, in particular `test_q4k_ordered_exact` with the shared slot at T 1 and 2.
- [x] 5.2 The step review against the previous kept snapshot.
- [x] 5.3 The section times on the step's tree.
- [x] 5.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-o4`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 5.5 The verdict.

## 6. Step O8: E2M1 values from their code bits

- [x] 6.1 Add `qwen4_e2m1(uint code)` (design D2) and use it in `QWEN4_MXFP4_PF_ACC_TO` in place of the table reads. Verify the step checks pass, in particular the prefetched-vs-plain MXFP4 cases (the plain kernel keeps the table) and `test_moe_grouped`.
- [x] 6.2 The step review against the previous kept snapshot.
- [x] 6.3 The section times on the step's tree.
- [x] 6.4 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-o8`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 6.5 The verdict.

## 7. Review and refine (design D5)

- [x] 7.1 Read the whole region in full and write the "final pass" section of `$SCR/c50/review.md`:
  - both passes and their helpers;
  - the per-token Q4_K and MXFP4 kernels;
  - `qwen4_moe_mv_rows`/`_groups`;
  - the shared helper, `qwen4_e2m1` and the added test case.

  Mark each finding *take* or *leave* with its reason, settling the questions in design D5. The dead `QWEN4_MXFP4_GROUPED_ROWS`/`_TAIL` macros are a *take*.
- [x] 7.2 Apply the *take* findings. Verify the step checks pass, and that `rg` finds no reference left to anything the pass removed.
- [x] 7.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-refine`, against the last kept step. Verify exit 0 with `PASS (tokens; bitwise)` and no decode metric's pooled CI wholly below 0. A finding that fails is reverted and marked *leave (measured)*.
- [x] 7.4 Snapshot `T_refine`, or record "no refinement".

## 8. Registry, closing

- [x] 8.1 In `docs/upstream-prs.md`:
  - update the `13c53d9` line: its shared Q8 loop is taken by `50` as a helper (or dropped, with O4's figures), and the IQ2 part stays with `70`;
  - update the #864 summary cell, which assigns "FP4 decode" to `50`, with O8's outcome.

  Verify `rg -n '50-q4-expert-decode|`50`' docs/upstream-prs.md` shows no line that still reads as an unmeasured plan.
- [x] 8.2 End checks: `python3 tests/test_qwen4_mtp_limits.py --model <Q4>` and `tools/parity-check.sh sf-q3-8flash <Q4>`. Verify each passes; for parity, re-run once after a cool-down if the only failure is a speed trip.
- [x] 8.3 Change result: bring `../sf-q3-8flash-prev` to `main` (`git -C ../sf-q3-8flash-prev restore --source=main --staged --worktree -- .`, then `make -j8` there). Run `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --out $SCR/c50/ab-final`. Verify exit 0 with `PASS (tokens; bitwise)`, and record the figures with the first and last section times.
- [x] 8.4 Record row: `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-start --b . --out $SCR/c50/ab-record`. Verify exit 0, and append its `record row:` to Segment 1 with the `step` cell `perf/50-q4-expert-decode` and the B-commit cell `this row's commit`.
- [x] 8.5 Final snapshot (`git add -A X`, then `git write-tree`). Verify `openspec validate 50-q4-expert-decode --strict` passes, and that `git diff --cached --stat main` lists only the files the steps and the pass touched.
- [x] 8.6 Report to the user in Italian:
  - each step's verdict with the A/B figures and section times;
  - the review's findings;
  - the change result and the record row;
  - the decisions taken.

  Do not commit. When the user asks, land one signed commit on `main` (design D1), with `Co-authored-by:` for `13c53d9`'s author if O4 was kept, and remove the two sibling worktrees.
