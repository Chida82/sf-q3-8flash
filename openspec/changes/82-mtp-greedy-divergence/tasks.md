# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `<Q2>` is
`~/.cache/huggingface/hub/models--antirez--qwen3.8-flash-next-gguf/snapshots/d600fe1a43d2e1cdcadb85144ce3142f66f9eefe/Qwen3.8-Flash-Next-Q2.gguf`,
expanded to an absolute path. `$SCR` is `~/.sf/q3-8flash/scratch`, and this
change's files go in `$SCR/c82/`. The case is upstream's networking prompt at
256 tokens (proposal.md).

**Model runs are strictly sequential.** Nothing runs beside one: no other model
run, no test and no build. Before each run, wait until the thermal state is
Nominal. Never rebuild a tree while a model runs from it.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `make test-qwen4-kernels`, ending in
`all qwen4 kernel tests passed`; `python3 tests/test_ab_bench.py`, ending in
`OK`.

## 1. Branch and references

- [ ] 1.1 Verify that `81-q2-prefill-tails` is on `main`. Run `git config rerere.enabled true`, then `git switch -c fix/82-mtp-greedy-divergence`.
- [ ] 1.2 Create the worktrees `../sf-q3-8flash-prev` at `main` and `../sf-q3-8flash-start` at `91f225a`, and build each.
- [ ] 1.3 Reproduce: run the case with and without `--mtp` on `.` and on `../sf-q3-8flash-start`. Verify the md5s from proposal.md: `4512c50b…` for plain on both trees and for MTP on the start tree, `0cdc9f3b…` for MTP on this tree.

## 2. Step S0: the identity check (design D1)

- [ ] 2.1 Write `tests/test_qwen4_mtp_identity.py` with the default prompt set, `--depths` and `--prompts`. Its `--help` and a run with a missing model must need no model. Verify `python3 tests/test_qwen4_mtp_identity.py --help` exits 0.
- [ ] 2.2 Add it to the development loop in `AGENTS.md` and to `docs/TESTING.md`.
- [ ] 2.3 Run the step checks, then the step review.
- [ ] 2.4 Run it on `<Q2>`, then `<Q4>`, on this tree. Verify that it reports the networking case as `DIFF` on Q2 and exits 1. Record every `DIFF` (pack, prompt, depth, first differing word) in `$SCR/c82/steps.txt`.
- [ ] 2.5 Run it on `<Q2>`, then `<Q4>`, on `../sf-q3-8flash-start`, with a copy of the script. Record which `DIFF`s already existed before priming.

## 3. D1b: depth data (design D6)

- [ ] 3.1 From S0's runs (2.4), tabulate the diverging prompts per pack and depth (2, 3, auto).
- [ ] 3.2 For `<Q2>`, then `<Q4>`: one A/A run with `--kinds plain`, then one with `--kinds mtp-code,mtp-prose` for each of `--env DS4_QWEN4_MTP_DEPTH=2`, `--env DS4_QWEN4_MTP_DEPTH=3` and no env (auto), each with `--budget 600` and a fresh `--out`. Record decode, tokens per cycle and the GPU clock median of each run in `steps.txt`.
- [ ] 3.3 Build design D6's table, one row per pack and depth, for the report.

## 4. D2 and D3: localization and cause

- [ ] 4.1 Add the probe of design D2 (env-gated, marked `PROBE-82`). Run the case in plain and in MTP mode. Diff the logs and record the first diverging position `p`, the verify batch shape there, and the top-2 margin in each mode.
- [ ] 4.2 **H2:** compare the target's last-row logits after prefill in both modes. Record identical or not.
- [ ] 4.3 **H1:** read the verify call site and record which graph entry scores the batch. Build a `DS4_QWEN4_FT_LIST` line from the plain run's token ids up to `p`. Run it at `DS4_QWEN4_GPU_CHUNK` 1, 2 and 3, and compare the dumps with `cmp`. If they differ, find the section, as design D3 describes.
- [ ] 4.4 **H3**, only if 4.2 and 4.3 read identical: dump the target logits at `p` in both modes, then narrow the cause with a pinned depth and the priming-tail probe knob.
- [ ] 4.5 Record the cause, with its evidence, in `steps.txt`.

## 5. D4: fix or decision

- [ ] 5.1 If a fix exists within design D4's rule, write it. Remove every probe (`rg PROBE-82` finds nothing). Run the step checks.
- [ ] 5.2 Run S0 on `<Q2>`, then `<Q4>`. Verify that both exit 0.
- [ ] 5.3 Run `ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q2> --bitwise --budget 600`, then the same with `<Q4>`. Verify `PASS (tokens; bitwise)` on plain, and that no MTP metric's pooled CI lies wholly below zero. Repeat the MTP kinds once if needed, then pool.
- [ ] 5.4 If H1 has no fix at zero cost: stop and report the three options of design D4 to the owner, each with its figures. Carry out the owner's choice, and record the choice in this file.

## 6. Review and closing

- [ ] 6.1 Final pass over the touched region, following design D5. Apply the findings, and measure them as their kind requires.
- [ ] 6.2 Run one after the other: parity with `<Q2>`, then with `<Q4>`, from the StarForge checkout; then `tests/test_qwen4_mtp_limits.py` on each pack.
- [ ] 6.3 If code outside `tests/` changed, add record rows against `../sf-q3-8flash-start` for both packs to Segment 1, with step `fix/82-mtp-greedy-divergence`.
- [ ] 6.4 Update the exception note in the README's "Quality and performance" section, and the `acce8da` and #1062 lines of `docs/upstream-prs.md`.
- [ ] 6.5 Verify that `openspec validate 82-mtp-greedy-divergence --strict` passes.
- [ ] 6.6 Report to the user in Italian:
  - the extent that S0 found;
  - the depth table of design D6 (before, and after the fix if any), for the owner's decision on a depth rule;
  - the first diverging token and its margin;
  - the cause;
  - the fix or the decision;
  - the figures;
  - the decisions taken.

  Do not commit. On request, land one signed commit on `main`, with the upstream author of `acce8da` as `Co-authored-by` if the fix touches its code.
