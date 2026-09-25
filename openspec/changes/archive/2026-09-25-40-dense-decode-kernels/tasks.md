# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `$SCR` is the session scratch dir. `X` is the pathspec
`-- . ':!openspec'`. Before each harness invocation, wait until the thermal
state is Nominal and the GPU is below 55 °C. Nothing else heavy may be resident
while a model runs.

"The step review" (design D5) means:

1. Read `git diff <previous snapshot> X` and every function it touches in
   full.
2. Record the findings in `$SCR/review.md` as *fix now* or *refine later*,
   with their site and reason.
3. Apply the *fix now* findings in the step and re-run its checks.

"The step checks" (design D3) means:

- `make -j8` with no warnings;
- `make test -j8`, whose output names the suites;
- `make test-qwen4-kernels`, ending in `all qwen4 kernel tests passed`;
- from step 1 on, `make test-metal-q8-reduction test-metal-q8-gemv-reference`,
  both ending in `PASS`.

## 1. Branch and references

- [x] 1.1 From `main`, with only this change's `openspec/` artifacts modified, run `git config rerere.enabled true` and `git switch -c perf/40-dense-decode-kernels`. Verify `git status --short --branch` shows the new branch.
- [x] 1.2 Situation 0: `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout. Verify `PARITY OK (10 prompts)`; if the only failure is a speed trip, re-run once after a cool-down before stopping to ask.
- [x] 1.3 Snapshots: `git add -A X`, then record `T_0=$(git write-tree)` in `$SCR/q8-steps.txt`. Run `git worktree add --detach ../sf-q3-8flash-prev main` and `git worktree add --detach ../sf-q3-8flash-start 91f225a`. Verify both build `sf-q3-8flash-bench`.

## 2. Step 1: Q8 loads and reduction (`a50fecc` + `04c0867`)

- [x] 2.1 `git cherry-pick -n a50fecc`, then `git cherry-pick -n 04c0867`. Resolve the Makefile and `.gitignore` per design D2: add the two oracle targets (the GEMV oracle built with `$(filter-out -ffast-math,$(OBJCFLAGS))`), their help lines, `clean` entries and ignore lines. Verify `rg -n '^(<<<<<<<|>>>>>>>)' Makefile .gitignore metal tests` prints nothing, `grep -c '^test:' Makefile` prints 1, and the step checks pass.
- [x] 2.2 The step review against `T_0`. Verify `$SCR/review.md` has a "step 1" section.
- [x] 2.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 2.4 Verdict (design D4, neutral keeps). Snapshot `T_1` and move `../sf-q3-8flash-prev` to it (`git -C ../sf-q3-8flash-prev restore --source=T_1 --staged --worktree -- .`). Record the figures in `$SCR/q8-steps.txt`.

## 3. Step 2: four-row Q8 matvec on M5 (`9bff1ca`)

- [x] 3.1 `git cherry-pick -n 9bff1ca`. Resolve per design D2:
  - drop the hunk for the removed `..._decode_mpp_model_view_tensor`;
  - widen the gate to M5 (`|| ds4_gpu_device_is_m5_apple_silicon()`);
  - call `test_qwen4_q8_decode_rows` from the child's `main`.

  Verify the kernel test prints the four-row dispatch case, and the step checks pass.
- [x] 3.2 The step review against `T_1`.
- [x] 3.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 3.4 Verdict (design D4). If kept: snapshot `T_2` and move `../sf-q3-8flash-prev` to it. If dropped: `git restore --source=T_1 --staged --worktree X`, and record the figures.

## 4. Step 3: HC gate-mix reuse for one token on M5 (`cdfc0d5` HC part)

- [x] 4.1 Port `kernel_qwen4_hc_gate_mix_f16_reuse` from `cdfc0d5` with the F16 loop pinned as in `028b43f`, its enum/name entries, and the M5 single-token selection (F16, rank 320, not pair). Add the byte-exact test case of design D2. Verify the new case prints `byte-exact` against both existing F16 kernels, and the step checks pass.
- [x] 4.2 The step review against the previous kept snapshot.
- [x] 4.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)`.
- [x] 4.4 Verdict (design D4). Snapshot `T_3`, or restore the previous kept snapshot, and record the figures.

## 5. Step 4: 16 SIMD groups for the HC pair on M5 (optional)

- [x] 5.1 If the session has room for one more harness run, make the pair kernel's default 16 SIMD groups on M5 as well as M3 Ultra. Run `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code,mtp-prose --bitwise`, and keep it on a gain (design D4); otherwise record "not attempted". Verify the outcome is in `$SCR/q8-steps.txt`, with a snapshot `T_4` if the step was kept.

## 6. Review and refine (design D5)

- [x] 6.1 Read the whole region in full and write the "final pass" section of `$SCR/review.md`:
  - the Q8 matvec family in `metal/dense.metal`;
  - the Q8 dispatch in `ds4_metal.m`;
  - the HC gate-mix kernels and their selection;
  - the oracles and the kernel test cases.

  Mark each finding *take* or *leave* with its reason, settling at least the four questions in design D5.
- [x] 6.2 Apply the *take* findings. Verify the step checks pass, and that `rg` finds no reference left to anything the pass removed.
- [x] 6.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise`, against the last kept step. Verify exit 0 with `PASS (tokens; bitwise)` and no throughput metric below its floor. A finding that fails is reverted and marked *leave (measured)*.
- [x] 6.4 Snapshot `T_refine` and draft its commit message, or record "no refinement".

## 7. Registry, docs, closing

- [x] 7.1 Update the lines of `a50fecc`, `04c0867`, `9bff1ca`, `cdfc0d5`, `bbbc012` and `028b43f` in `docs/upstream-prs.md` with their verdicts and figures, and the #1056 summary cell. Add a line to `docs/METAL.md` for each new M5 default, if that file lists kernel defaults. Verify `rg -n '40-dense-decode-kernels' docs/upstream-prs.md` shows no line that still reads as an unmeasured plan.
- [x] 7.2 End checks: `make test-qwen4-q2`, `python3 tests/test_qwen4_mtp_limits.py --model <Q4>`, and `tools/parity-check.sh sf-q3-8flash <Q4>`. Verify each passes; for parity, re-run once after a cool-down if the only failure is a speed trip.
- [x] 7.3 Change result: bring `../sf-q3-8flash-prev` to `main` (`git -C ../sf-q3-8flash-prev restore --source=main --staged --worktree -- .`), then run `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise`. Verify exit 0 with `PASS (tokens; bitwise)`, and record the figures.
- [x] 7.4 Record row: `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-start --b .`. Verify exit 0, and append its `record row:` to Segment 1 with the `step` cell `perf/40-dense-decode-kernels` and a `pending commit` B-commit cell.
- [x] 7.5 Final snapshot `T_final` (`git add -A X`, then `git write-tree`). Verify `openspec validate 40-dense-decode-kernels --strict` passes, and that `git diff --cached --stat main` lists only the files the steps and the pass touched.
- [x] 7.6 Report to the user in Italian: each step's verdict with figures, the review's findings, the change result and the record row, and the decisions taken. Do not commit. When the user asks, replay each snapshot in order as a signed commit (`git restore --source=<T> --staged --worktree X`, then `git commit`, with the upstream author for ported steps). Before the last commit, set the record row's B-commit cell to the refinement commit's short SHA. The last commit also runs `git add openspec`. Then remove the two worktrees.
