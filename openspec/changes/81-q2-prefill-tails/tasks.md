# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `<Q2>` is
`~/.cache/huggingface/hub/models--antirez--qwen3.8-flash-next-gguf/snapshots/d600fe1a43d2e1cdcadb85144ce3142f66f9eefe/Qwen3.8-Flash-Next-Q2.gguf`,
expanded to an absolute path. `$SCR` is the session scratch dir, and this
change's files go in `$SCR/c81/`. `X` is the pathspec `-- . ':!openspec'`.

**Model runs are strictly sequential.** Nothing runs beside one: no other model
run, no test and no build. Before each run, wait until the thermal state is
Nominal. Give every run a fresh `--out` directory. Never edit `metal/*.metal`,
and never rebuild a tree, while a model runs from it.

"The step checks":
- `make -j8`, with no warnings;
- `make test -j8`, whose output names the suites;
- `make test-qwen4-kernels`, ending in `all qwen4 kernel tests passed`;
- `make test-qwen4-q2`;
- `python3 tests/test_ab_bench.py`, ending in `OK`.

## 1. Branch and references

- [ ] 1.1 Verify that `70-q2-kernels-m5` is on `main`. With only this change's `openspec/` artifacts modified, run `git config rerere.enabled true`, then `git switch -c perf/81-q2-prefill-tails`.
- [ ] 1.2 Situation 0, one after the other, from the StarForge checkout: `tools/parity-check.sh sf-q3-8flash <Q2>`, then the same with `<Q4>`. Verify that both print `PARITY OK`.
- [ ] 1.3 Snapshot `T_0` in `$SCR/c81/steps.txt`. Create the worktrees:
  - `git worktree add --detach ../sf-q3-8flash-prev main`;
  - `git worktree add --detach ../sf-q3-8flash-start 91f225a`.

  Verify that each builds `sf-q3-8flash-bench`.

## 2. Step S0: generation-length override

- [ ] 2.1 Add `--gen N` to `speed-bench/ab_bench.py` (design D1).
  - It passes `-n N` for every kind and names the override in the summary header.
  - It prints no record row, with a line saying why.
  - It refuses N outside 16..4096 with exit 2.

  Verify that `ab_bench.py --a . --b . --gen 8` exits 2.
- [ ] 2.2 Extend `tests/test_ab_bench.py` with the spec scenarios: the command carries `-n`, the row is suppressed, the range is refused. Add the option to the README's usage section. Verify that `python3 tests/test_ab_bench.py` prints `OK`.
- [ ] 2.3 Run the step checks, then the step review against `T_0`.
- [ ] 2.4 Noise floor at length 512: `ab_bench.py --a ../sf-q3-8flash-prev --b ../sf-q3-8flash-prev --kinds mtp-code --gen 512 -m <Q2> --budget 600 --out $SCR/c81/aa512`. Verify that the decode CI contains 0, and record its half-width.
- [ ] 2.5 Verdict under the tool-step rule: S0 is kept if 2.2 and 2.4 pass. Snapshot `T_S0`.

## 3. D1: fixed or per token (design D2)

- [ ] 3.1 Apply the gate of design D4 as a probe. Verify that `make test-qwen4-kernels` passes, with `Q2 tiles` hashes equal to `70`'s and three `byte-exact mid/down nax=2` lines.
- [ ] 3.2 Run `ab_bench.py --a ../sf-q3-8flash-prev --b . --kinds mtp-code -m <Q2> --bitwise --budget 600 --out $SCR/c81/d-mc64`.
- [ ] 3.3 Run the same with `--gen 512 --out $SCR/c81/d-mc512`.
- [ ] 3.4 Run `--kinds plain --gen 256 --out $SCR/c81/d-p256`, then one repeat `d-p256b`.
- [ ] 3.5 Pool each kind with `ab_pool.py`, then classify each kind as fixed, per token or inconclusive (design D2). Record the figures, and the per-phase cost implied at each length, in `steps.txt`. If inconclusive, repeat once and pool; if still inconclusive, take it as per token.

## 4. D3: the source

- [ ] 4.1 Probe: create the tail pipelines at engine open. Run MTP-code at the default length, then at the length from 3.5 that showed the loss best. Record the result.
- [ ] 4.2 Probe: tails on the mid side only, then on the down side only. Run MTP-code at the default length for each. Record the result.
- [ ] 4.3 Run `DS4_METAL_CB_TIMES=1` on one run without the tails and one with them, of `sf-q3-8flash-bench` MTP-code on `<Q2>`, one after the other. Compare the command-buffer times of the first decode cycles and of the steady cycles. Record the result.
- [ ] 4.4 If a probe removed the loss, write it as a candidate fix and check that its output is identical. Otherwise remove every probe (`git restore --source=<3.1 snapshot>`).

## 5. D2: the decision (design D5)

- [ ] 5.1 **Outcome (b)**, a fix exists: keep the gate and the fix. Run the full guard, `ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q2> --bitwise --budget 600`, plus one MTP-code repeat pooled in. The step is kept under the existing rule: nothing wholly below zero.
- [ ] 5.2 **Outcome (a)**, the cost is fixed and at most a tenth of the saving at +512: add the trade-off clause to `openspec/config.yaml`, keep the gate, and run the guard of 5.1. Record the loss.
- [ ] 5.3 **Outcome (c)**, per token and nothing removes it: stop and report the figures to the owner, using the proposal's break-even table filled with the new numbers. Then do what the owner chooses: either (c1) the clause and the gate, as in 5.2, or (c2) no gate, with `DS4_QWEN4_MOE_TAILS=1` documented in `speed-bench/README.md` and in the M5 notes as the prefill-first setting.
- [ ] 5.4 Snapshot the kept tree. Run the step review. Record the outcome in `steps.txt`.

## 6. Review and refine

- [ ] 6.1 Final pass over the harness option, `qwen4_moe_mm_tails` and any fix, following design D7. Verify that `rg` finds no probe knob or probe comment.
- [ ] 6.2 Apply the *take* findings, and measure them as their kind requires.

## 7. Registry and closing

- [ ] 7.1 Update the `496b153` line in `docs/upstream-prs.md` with this change's outcome and figures. Verify that `rg -n '`81`' docs/upstream-prs.md` shows no unmeasured plan.
- [ ] 7.2 Run the end checks, one after the other: parity with `<Q2>`, then with `<Q4>`, then `tests/test_qwen4_mtp_limits.py --model <Q2>`, then with `<Q4>`. If no file the binaries build from changed, only the tool did, and 1.2 covers the rest; record that.
- [ ] 7.3 Change result: `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --budget 600` with `<Q2>`, then with `<Q4>`. Then the record rows against `../sf-q3-8flash-start`, both packs, appended to Segment 1 with step `perf/81-q2-prefill-tails` and B-commit `this row's commit`.
- [ ] 7.4 Final snapshot. Verify that `openspec validate 81-q2-prefill-tails --strict` passes.
- [ ] 7.5 Report to the user in Italian:
  - each step's verdict with its figures;
  - the fixed-or-per-token finding;
  - the source, if found;
  - the outcome;
  - the change results and record rows;
  - the decisions taken.

  Do not commit. On request, land one signed commit on `main` and remove the worktrees.
