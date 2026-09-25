# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `$SCR` is the session scratch dir; this change's files go in
`$SCR/c61/`. `X` is the pathspec `-- . ':!openspec'`.

Before each model run, wait until the thermal state is Nominal and the GPU is
below 55 °C, with nothing else heavy resident. Never edit `metal/*.metal`
while a model runs from the tree.

"The step checks" (design D5) means:
- `make -j8` with no warnings;
- `make test -j8`, whose output names the suites;
- `make test-qwen4-kernels`, ending in `all qwen4 kernel tests passed` and
  printing a `byte-exact mid/down vs nax=` line for every tile-test T;
- `make test-qwen4-q2`, printing `all Qwen MoE decode specialization tests
  passed`;
- `python3 tests/test_ab_bench.py`, ending in `OK`.

"The step review" (design D6): read `git diff <previous snapshot> X` and every
function it touches in full, record findings in `$SCR/c61/review.md` as *fix
now* or *refine later*, and apply the *fix now* ones.

## 1. Branch and references

- [x] 1.1 Verify `60-q4-expert-prefill` is on `main` (`git log --oneline -1 main` shows its commit). With only this change's `openspec/` artifacts modified, `git config rerere.enabled true` and `git switch -c perf/61-q4-prefill-48-token-tiles`. Verify `git status --short --branch`.
- [x] 1.2 Situation 0: `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout. Verify `PARITY OK (10 prompts)`; re-run once after a cool-down if the only failure is a speed trip.
- [x] 1.3 Snapshot `T_0` (`git add -A X`, `git write-tree`) in `$SCR/c61/steps.txt`, and create three worktrees: `git worktree add --detach ../sf-q3-8flash-prev main`, `../sf-q3-8flash-start 91f225a` and `../sf-q3-8flash-base 53dcad6`, then restored to `60`'s `T_S0` tree (`$SCR/c60/steps.txt`), which has the tiled-path profiler cuts and none of `60`'s kernel steps. Verify each builds `sf-q3-8flash-bench`.

## 2. Step S0: section-time mode and the pooling tool

- [x] 2.1 Add `--sections <groups>` to `speed-bench/ab_bench.py` (design D2): profiler on for both builds, a group-name check (exit 2), chunk-line parsing keyed by (pos, T) with a missing chunk or `ok=0` as a run failure, the normalized and whole-chunk pair ratios with the bootstrap CI, `sections.csv`, and the sections table in the summary; plain as the default kind in this mode. Verify `python3 speed-bench/ab_bench.py --a . --b . --sections nope` exits 2 naming `nope`.
- [x] 2.2 Move `$SCR/c60/pool.py` to `speed-bench/ab_pool.py` with a `--sections <shape>` form over `sections.csv` (design D2). Verify it reproduces `60`'s recorded pooled CI for O5a prefill 8704 (`+0.82..+3.50`) from `$SCR/c60/ab-o5a`.
- [x] 2.3 Extend `tests/test_ab_bench.py` with the five cases of design D2. Verify `python3 tests/test_ab_bench.py` prints `OK` with the new test names.
- [x] 2.4 Add a "Section-time mode" paragraph and `ab_pool.py` to `speed-bench/README.md` (design D7). Verify it names the flag, the metric and the keep rule it serves.
- [x] 2.5 The step checks, then the step review against `T_0`.
- [x] 2.6 Validation (a), the A/A run: `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b ../sf-q3-8flash-prev --sections moe_mid,moe_down --budget 600 --out $SCR/c61/aa`. Verify exit 0 and every shape's CI contains 1. Record each half-width in `steps.txt` as the noise floor.
- [x] 2.7 Validation (b), the known effect: the same with `--a ../sf-q3-8flash-base --b ../sf-q3-8flash-prev --out $SCR/c61/known`. Verify every shape's CI lies below 1, and that the 2048-token shape agrees with `60`'s section times (routed MoE about -10%).
- [x] 2.8 The verdict, tool-step rule: kept if 2.3, 2.6 and 2.7 pass. Snapshot `T_S0`. `../sf-q3-8flash-prev` stays at `main`, whose binaries S0 does not change.

## 3. Step O9: the 48-token half tile

- [x] 3.1 Probe: add the two `<48, half, false>` instances, their enum entries and names, the remainder rule and the generalized staging guard (design D3), with the host dispatches. Build and run `make test-qwen4-kernels`. If the pipeline fails to compile, or any `byte-exact mid/down vs nax=` check fails, restore `T_S0`, record O9 as dropped with the reason in `steps.txt`, and go to 4.
- [x] 3.2 Add the tile-test shape T 119 and update the call-site comment to name each shape's tiles (design D3). Verify the step checks pass with byte-exact lines for T 641, 75, 119 and 161.
- [x] 3.3 The step review against `T_S0`.
- [x] 3.4 Section-time A/B: `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --sections moe_mid,moe_down --bitwise --budget 600 --out $SCR/c61/o9`. Verify exit 0 with `PASS (tokens; bitwise)`. On an inconclusive result repeat once to `$SCR/c61/o9b` and pool with `ab_pool.py`.
- [x] 3.5 (Not run: O9 was already dropped by 3.4, and the guard only matters for a kept step.) Guard: `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --budget 600 --out $SCR/c61/o9-guard`. Verify `PASS (tokens; bitwise)` and, with `ab_pool.py`, no metric's CI wholly below 0.
- [x] 3.6 The verdict (design D4): kept if the normalized CI lies below 1 at one shape and above 1 at none, and 3.5 passes. Otherwise restore `T_S0`. Record the figures in `steps.txt`; if kept, snapshot `T_O9`.

## 4. Review and refine (design D6)

- [x] 4.1 Read the whole region in full and write the "final pass" section of `$SCR/c61/review.md`, each finding *take* or *leave* with its reason, settling D6's question.
- [x] 4.2 Apply the *take* findings. Verify the step checks pass and `rg` finds no reference left to anything removed.
- [x] 4.3 Measure the refinement as its kind requires (design D4): a section-time A/B for kernel code, `python3 tests/test_ab_bench.py` for harness code, nothing for comments. Verify output identity (`--bitwise` or the kernel test). A finding that fails is reverted and marked *leave (measured)*.

## 5. Registry, closing

- [x] 5.1 `docs/upstream-prs.md`: add O9's outcome (taken with its section-time figures, or dropped with the reason) to the `496b153` line. Verify `rg -n '`61`' docs/upstream-prs.md` shows no unmeasured plan.
- [x] 5.2 (Not run: with O9 dropped, every file the child's binaries build from is identical to `main` — `git diff --cached --stat main -- . ':!speed-bench' ':!tests/test_ab_bench.py' ':!openspec'` is empty — so the start parity of 1.2 covers them and an A/B or record row would measure `main` against itself.) End checks: `python3 tests/test_qwen4_mtp_limits.py --model <Q4>` and `tools/parity-check.sh sf-q3-8flash <Q4>`. Verify each passes.
- [x] 5.3 (Not run: with O9 dropped, every file the child's binaries build from is identical to `main` — `git diff --cached --stat main -- . ':!speed-bench' ':!tests/test_ab_bench.py' ':!openspec'` is empty — so the start parity of 1.2 covers them and an A/B or record row would measure `main` against itself.) Change result: `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --budget 600 --out $SCR/c61/final`. Verify `PASS (tokens; bitwise)`. If O9 was kept, add a section-time run against `main` (`--out $SCR/c61/final-sections`).
- [x] 5.4 (Not run: with O9 dropped, every file the child's binaries build from is identical to `main` — `git diff --cached --stat main -- . ':!speed-bench' ':!tests/test_ab_bench.py' ':!openspec'` is empty — so the start parity of 1.2 covers them and an A/B or record row would measure `main` against itself.) Record row: `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-start --b . --budget 600 --out $SCR/c61/record`. Append its `record row:` to Segment 1 with step `perf/61-q4-prefill-48-token-tiles` and B-commit `this row's commit`.
- [x] 5.5 Final snapshot. Verify `openspec validate 61-q4-prefill-48-token-tiles --strict` passes, and that `git diff --cached --stat main` lists only the files the steps touched.
- [x] 5.6 Report to the user in Italian: each step's verdict with figures, the validation runs' noise floor, the review's findings, the change result, the record row and the decisions taken. Do not commit. On request, land one signed commit on `main` and remove the three worktrees.
