# Tasks

Starts from `main` with `90-upstream-sync-b3f5018` landed.
- `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `<MMPROJ>` is its vision
  projector, linked by `./download.sh vision`.
- `<IMG1>` and `<IMG2>` are the AirDrop and AlertStop system icons converted
  to PNG with `sips`, kept in `$SCR/c110/`. `$SCR` is
  `~/.sf/q3-8flash/scratch`.

**Model runs are strictly sequential.** Nothing runs beside one: no other
model run, no test and no build. Wait until the thermal state is Nominal
before each run.

"The step checks" are design D5's.

## 1. Branch and reproduction

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c fix/110-mtp-image-turn-divergence`. Create `../sf-q3-8flash-prev` at `main` and `../sf-q3-8flash-start` at `91f225a`, and build both.
- [ ] 1.2 Reproduce on this tree: `python3 tests/test_qwen4_cli_vision.py --model <Q4> --vision <MMPROJ> --image <IMG1> --image <IMG2> --out-dir $SCR/c110/r1`, twice (`r1`, `r2`). Record whether `ordinary.stdout` and `mtp.stdout` differ, from which turn, and whether `r1` and `r2` match each other in each mode. If the outputs no longer differ after `90`, record that, run step 2 to keep the check, and close.

## 2. S0: the comparison check (design D1)

- [ ] 2.1 Add `--compare` to `tests/test_qwen4_cli_vision.py`. Verify that `--help` exits 0 without a model, and that a run over `r1`'s saved outputs, through a small offline mode or a unit function, reports `DIFF` at the turn found in 1.2.
- [ ] 2.2 Run the step checks, then the step review.
- [ ] 2.3 Write `$SCR/c110/text_turns.txt`: four text user turns, no `/read`. Run it in both modes with the same flags through the REPL. Record `SAME` or `DIFF` per turn (H1, design D3 step 1).
- [ ] 2.4 Run S0 at `DS4_QWEN4_MTP_DEPTH=2` and `=3` inline, and once on `../sf-q3-8flash-start` with a copy of the script. Record the first diverging turn for each run in `$SCR/c110/steps.txt`.

## 3. Localization and cause (design D2, D3)

- [ ] 3.1 Add the probe of design D2 (env-gated, marked `PROBE-110`). Run the case and, if 2.3 diverged, the text-only conversation, in both modes. Diff the logs, and record the first position where the row path or the turn-boundary state differs.
- [ ] 3.2 H1: from 3.1's turn-boundary lines, record per boundary whether sync reused or replayed, and which path computed the closing rows in each mode.
- [ ] 3.3 H4, only if 2.3 read `SAME`: read the verify call site and record the graph entry it uses. Run the `DS4_QWEN4_FAKE_IMAGE` plus `DS4_QWEN4_FT_LIST` dumps at `DS4_QWEN4_GPU_CHUNK` 1, 2 and 3, and compare them with `cmp`.
- [ ] 3.4 H2, if 3.3 reads equal: dump the target's last-row logits after the second image chunk's prefill in both modes, and record whether they are equal.
- [ ] 3.5 H3, if 3.4 reads equal: compare the restored `mrope_delta`, `pos` and `ple_prev` after rejected drafts with plain decode's values at pinned depths 2 and 3.
- [ ] 3.6 Record the cause, with its evidence, in `steps.txt`.

## 4. Fix or decision (design D4)

- [ ] 4.1 If a fix exists within design D4's rule, write it. Remove every probe (`rg PROBE-110` finds nothing). Run the step checks.
- [ ] 4.2 Run S0 on the case and on the text-only conversation. Verify that both exit 0. Run `python3 tests/test_qwen4_mtp_identity.py --model <Q4>` and `python3 tests/test_qwen4_mtp_limits.py --model <Q4>`.
- [ ] 4.3 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q4> --bitwise --budget 600`. Verify `PASS (tokens; bitwise)` on plain, and that no MTP metric's pooled CI lies wholly below zero. Repeat the MTP kinds once if inconclusive, then pool.
- [ ] 4.4 If no fix exists at zero cost: stop and report design D4's options to the owner, each with its figures. Carry out the owner's choice and record it here.

## 5. Review and closing

- [ ] 5.1 Final pass over the touched region (design D5). Apply the findings and measure them as their kind requires.
- [ ] 5.2 Parity from the StarForge checkout: `tools/parity-check.sh sf-q3-8flash <Q4>`, then `PARITY OK`.
- [ ] 5.3 If code outside `tests/` changed, add a record row against the current segment's start to `speed-bench/perf-record.md`, with step `fix/110-mtp-image-turn-divergence`.
- [ ] 5.4 Add S0 to the development loop in `AGENTS.md` and to `docs/TESTING.md`. If H1 was confirmed, add the text-only case to the same script.
- [ ] 5.5 Q2: list S0 on the Q2 pack as pending the owner's approval of the download, unless it was approved and run.
- [ ] 5.6 `openspec validate 110-mtp-image-turn-divergence --strict` passes.
- [ ] 5.7 Report to the user in Italian: the extent, the first diverging state, the cause, the fix or the decision, the figures, and the decisions taken. Do not commit. On request, land one signed commit on `main`.
