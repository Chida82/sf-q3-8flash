# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `<Q2>` is
`~/.cache/huggingface/hub/models--antirez--qwen3.8-flash-next-gguf/snapshots/d600fe1a43d2e1cdcadb85144ce3142f66f9eefe/Qwen3.8-Flash-Next-Q2.gguf`,
expanded to an absolute path. `$SCR` is the session scratch dir; this change's
files go in `$SCR/c70/`. `X` is the pathspec `-- . ':!openspec'`.

**Model runs are strictly sequential.** Nothing else runs beside one: no other
model run, no test, no build. Before each run, wait until the thermal state is
Nominal and the GPU is below 55 °C. Never edit `metal/*.metal` while a model
runs from the tree.

"The step checks" (design D9) means:
- `make -j8` with no warnings;
- `make test -j8`, whose output names the suites;
- `make test-qwen4-kernels`, ending in `all qwen4 kernel tests passed` with
  every byte-exact line present;
- `make test-qwen4-q2`, printing `all Qwen MoE decode specialization tests
  passed`;
- `make test-mxfp4-metal`;
- `python3 tests/test_ab_bench.py`, ending in `OK`.

"The step review": read `git diff <previous snapshot> X` and every function it
touches in full, record findings in `$SCR/c70/review.md` as *fix now* or
*refine later*, and apply the *fix now* ones.

"The section verdict (targets, model, shapes)":
- run `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . --sections
  <targets> -m <model> --bitwise --budget 600 --out $SCR/c70/<step>`;
- kept when the normalized CI lies below 1 at one of the named shapes and above
  1 at none; one repeat pooled with `ab_pool.py` if inconclusive;
- if kept, run the guard: `ab_bench.py --a ../sf-q3-8flash-prev --b . -m <model>
  --bitwise --budget 600 --out $SCR/c70/<step>-guard`, PASS and no metric's CI
  wholly below 0;
- then snapshot `T_<step>` and bring `../sf-q3-8flash-prev` to it (`git -C
  ../sf-q3-8flash-prev restore --source=T_<step> --staged --worktree -- .`,
  `make -j8` there);
- if dropped, `git restore --source=<previous kept snapshot> --staged --worktree
  X`;
- record the figures in `$SCR/c70/steps.txt`.

## 1. Branch and references

- [x] 1.1 From `main`, with only this change's `openspec/` artifacts modified, `git config rerere.enabled true` and `git switch -c perf/70-q2-kernels-m5`. Verify `git status --short --branch`.
- [x] 1.2 Situation 0, one after the other: `tools/parity-check.sh sf-q3-8flash <Q4>`, then `tools/parity-check.sh sf-q3-8flash <Q2>`, from the StarForge checkout. Verify both print `PARITY OK`; on a speed trip alone, re-run once after a cool-down.
- [x] 1.3 Snapshot `T_0` in `$SCR/c70/steps.txt`. Create three worktrees:
  - `git worktree add --detach ../sf-q3-8flash-prev main`;
  - `../sf-q3-8flash-start 91f225a`;
  - `../sf-q3-8flash-known 53dcad6`, then restored to `50`'s S0 tree `d5dc38b37e9af4e27e925e01f18c6be2921a59a1` (`git -C ../sf-q3-8flash-known restore --source=d5dc38b… --staged --worktree -- .`).

  Verify each builds `sf-q3-8flash-bench`.

## 2. Step S0: decode shape, rule, Q2 start row

- [x] 2.1 In `speed-bench/ab_bench.py`, parse the T=1 decode lines into a `decode` shape for the plain kind (design D2), with a missing line as a run failure. Verify with a unit test.
- [x] 2.2 Extend `tests/test_ab_bench.py` with the three cases of design D2, and the README section-time paragraph with the decode shape and its unit (µs per pass). Verify `python3 tests/test_ab_bench.py` prints `OK` with the new tests.
- [x] 2.3 In `openspec/config.yaml`, make the GPU-time rule cover decode kernel steps (design D2). Verify `openspec instructions apply --change 70-q2-kernels-m5 --json` returns the new wording in `context`.
- [x] 2.4 The step checks, then the step review against `T_0`.
- [x] 2.5 Validation (a), A/A: `ab_bench.py --a ../sf-q3-8flash-prev --b ../sf-q3-8flash-prev --sections moe_mid,moe_down --budget 600 --out $SCR/c70/aa`. Verify every shape's CI contains 1. Record the decode half-width.
- [x] 2.6 Validation (b), known effect: `--a ../sf-q3-8flash-known --b ../sf-q3-8flash-prev --sections moe_mid,moe_down --budget 600 --out $SCR/c70/known`. Verify the decode CI lies below 1, near 0.92. The prefill shapes may read inconclusive (design D2), so exit 3 is accepted.
- [x] 2.7 Q2 start row: `ab_bench.py --a ../sf-q3-8flash-start --b ../sf-q3-8flash-start -m <Q2> --budget 600 --out $SCR/c70/q2-start`. Append its `record row:` to Segment 1, with the step cell `start (A/A, Q2)`.
- [x] 2.8 The verdict, tool-step rule: kept if 2.2, 2.5 and 2.6 pass. Snapshot `T_S0`. `../sf-q3-8flash-prev` stays at `main`.

## 3. Step P1 (Q4): shared Q8 down slot in row pairs

- [x] 3.1 Add `qwen4_moe_shared_q8_rows` and call it from `kernel_qwen4_moe_down_mxfp4_pf`'s shared branch for `st == 8` (design D3). Verify the step checks pass, in particular the MV_EXACT prefetched-vs-plain cases with the shared slot.
- [x] 3.2 The step review.
- [x] 3.3 The section verdict (`moe_down`, `<Q4>`, decode).

## 4. Step P2 (Q4): MXFP4 staging through an exact half form

- [x] 4.1 Variant (a), the half table (design D4). Verify the step checks pass, including `make test-mxfp4-metal`, the byte-exact tile lines, and tile-test hashes equal to `main`'s.
- [x] 4.2 The section verdict (`moe_down`, `<Q4>`, prefill shapes) for (a) against the previous kept step. Record the figures, then restore the previous kept snapshot.
- [x] 4.3 Variant (b), the half-scale form (design D4). Run the same checks and section verdict.
- [x] 4.4 Keep the better variant if it passes the rule, restoring its tree; otherwise drop P2. The step review of the kept variant. Record the choice in `steps.txt`.

## 5. Step Q1 (Q2): remainder tails for 16/10 on M5

- [x] 5.1 Extend `test_moe_mm_tiles_iq2` with the level-2-against-level-1 byte-exact check and the padded 640/768 shape at T 161 and 641 (design D5). Run the test on `main` first and record its hashes as the pin. Verify it passes on `main`.
- [x] 5.2 Add 16/10 on M5 to `qwen4_moe_mm_tails`. Verify the step checks pass and every tile-test hash equals the pin.
- [x] 5.3 The step review.
- [x] 5.4 The section verdict (`moe_mid,moe_down`, `<Q2>`, prefill shapes).

## 6. Step Q2 (Q2): decode specialization for 16/10 on M5

- [x] 6.1 Add 16/10 on M5 to `qwen4_moe_mv_specialize` (design D6). Verify the step checks pass, including the MV_EXACT geometry cases for 16/10.
- [x] 6.2 The step review.
- [x] 6.3 The section verdict (`moe_mid,moe_down`, `<Q2>`, decode).

## 7. Step Q3 (Q2): IQ2 gate/up decode kernel

- [x] 7.1 Add `kernel_qwen4_moe_mid_iq2<NR>` (NR 1 and 2), its names and its M5 selection for type 16 (design D7). Add its byte-exact test against the generic kernel. Verify the step checks pass. If the test fails even with pinned contraction, restore the previous kept snapshot and record Q3 as dropped.
- [x] 7.2 The step review.
- [x] 7.3 The section verdict (`moe_mid`, `<Q2>`, decode).

## 8. Step Q4 (Q2): Q2_K down decode kernel

- [x] 8.1 Add `kernel_qwen4_moe_down_q2k` with P1's helper for the shared slot, its name and its M5 selection for type 10 (design D8). Add its byte-exact tests at 768/640→2560 and 256/672. Verify the step checks pass. If P1 was dropped, take the helper as part of this step.
- [x] 8.2 The step review.
- [x] 8.3 The section verdict (`moe_down`, `<Q2>`, decode).

## 9. Review and refine (design D9)

- [x] 9.1 Read the whole region in full and write the "final pass" section of `$SCR/c70/review.md`, each finding *take* or *leave* with its reason. Settle whether Q2's gate is still needed after Q3/Q4.
- [x] 9.2 Apply the *take* findings. Verify the step checks pass and `rg` finds no reference to anything removed.
- [x] 9.3 Measure the refinement as its kind requires: a section verdict for kernel code, the unit tests for harness code, nothing for comments. A finding that fails is reverted and marked *leave (measured)*.

## 10. Registry, closing

- [x] 10.1 `docs/upstream-prs.md`: the lines for `cdfc0d5`, `13c53d9`, `9a8462a`, `5cbdb6e`, `a37fd7f`, `496b153`, `11811b9` and #864. Each gets its outcome (taken with its figures, measured and dropped, or not taken with the reason in proposal.md). Verify `rg -n '`70`' docs/upstream-prs.md` shows no unmeasured plan.
- [x] 10.2 End checks, one after the other: parity with `<Q4>`, then with `<Q2>`; `tests/test_qwen4_mtp_limits.py --model <Q4>`, then `--model <Q2>`. Verify each passes.
- [x] 10.3 Change result: bring `../sf-q3-8flash-prev` to `main`. Run `ab_bench.py --bitwise --budget 600` against it with `<Q4>`, then with `<Q2>`. Verify both `PASS (tokens; bitwise)`.
- [x] 10.4 Record rows: `ab_bench.py --a ../sf-q3-8flash-start --b . --budget 600` with `<Q4>`, then with `<Q2>`. Append both rows to Segment 1 with step `perf/70-q2-kernels-m5` and B-commit `this row's commit`.
- [x] 10.5 Final snapshot. Verify `openspec validate 70-q2-kernels-m5 --strict` passes and `git diff --cached --stat main` lists only the files the steps touched.
- [x] 10.6 Report to the user in Italian:
  - each step's verdict with its figures;
  - the noise floors;
  - the review's findings;
  - the change results and record rows for both packs;
  - the decisions taken.

  Do not commit. On request, land one signed commit on `main` and remove the three worktrees.
