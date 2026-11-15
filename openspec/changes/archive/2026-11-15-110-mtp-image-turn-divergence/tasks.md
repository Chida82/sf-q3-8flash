# Tasks

Starts from `main` with `90-upstream-sync-b3f5018` landed (run on `ee30cc4`,
after 95, 101, 140, 97 and the server changes 131, 132, 160, 130).
- `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `<MMPROJ>` is its vision
  projector, linked by `./download.sh vision`. `<Q2>` is
  `gguf/Qwen3.8-Flash-Next-Q2.gguf`.
- `<IMG1>` and `<IMG2>` are the AirDrop and AlertStop system icons converted
  to PNG with `sips` (1024x1024), kept in `$SCR/c110/`. `$SCR` is the
  session scratchpad.

**Model runs are strictly sequential.** Nothing runs beside one: no other
model run, no test and no build. Wait until the thermal state is Nominal
before each run. Every binary runs with its own tree as the working
directory: `ds4_metal.m` compiles `metal/*.metal` from there (97's trap).

"The step checks" are design D5's.

## 1. Branch and reproduction

- [x] 1.1 Branch `fix/110-mtp-image-turn-divergence` in the worktree `.claude/worktrees/110-mtp-image` (rerere already on). Main checkout as `prev`, the existing `seg1-91f225a` worktree as `start` (run read-only, cwd there).
- [x] 1.2 Reproduced on `ee30cc4`, Q4: both modes PASS; `ordinary` and `mtp` differ from turn 3 (second image turn), first line "has a subtle vertical gradient" / "has a vertical gradient", and in turn 4. `r1` and `r2` match each other in each mode: deterministic. Per-turn prefill: ordinary 1048 26 1039 26, mtp 1048 26 **1038** 26.

## 2. S0: the comparison check (design D1)

- [x] 2.1 `--compare` added. The REPL marks no turns on stdout, so the script sends `/power` (prints the value, changes nothing) before the first turn and after each one, splits on it, and prints `SAME`/`DIFF turn N, line L` with both lines. `--help` exits 0 without a model; `compare_turns` checked offline on equal, differing and short inputs. On the case it reports `DIFF turn 3, line 5` and `DIFF turn 4, line 3`.
- [x] 2.2 Step checks: `make -j8` no warnings; `make test -j8` (server OK, ds4 tests ok, sampling OK, layer_pack 97/97, prompt prefix, sfctl, ds4-eval self-tests); `tests/test_ab_bench.py` 30 OK.
- [x] 2.3 Text-only conversation, landed as `--text-turns` (four turns, no `/read`), two runs: SAME 1-3, `DIFF turn 4` ("Zest upon the air." / "Zest in every drop."), deterministic. Prefill ordinary 34 25 28 21, mtp 34 25 **27 137**. H1: images are not needed.
- [x] 2.4 Before the fix (Q4), first diverging turn: depth 2 image 3, text none (prefill still shifted: mtp 27 20 against 28 21); depth 3 image 3, text 4 (mtp 34 **64** 28 **137**: two full replays); `91f225a` image 3, text none (mtp 27 20). In every run the MTP prefill sizes depart from plain at a turn boundary, and every `DIFF` follows such a boundary.

## 3. Localization and cause (design D2, D3)

- [x] 3.1 Probe (`PROBE-110`, env-gated, in the REPL turn start and both stop checks; removed). Text conversation, auto depth. Plain ends every turn on a sampled stop with session pos = transcript length (39, 76, 116, 160). MTP, turn 2: `<|im_end|>` accepted as draft at j=1 of a 2-row verify, session pos 77, transcript 76. Turn 3 prefills 27 rows, plain 28. MTP, turn 3: depth-3 block `[x, <|im_end|>, d2]` fully accepted, session pos 118, transcript 116. Turn 4: common prefix 117 < 118, so the whole 137-token transcript is re-prefilled from 0 with a new chunk schedule, and turn 4 diverges.
- [x] 3.2 H1 per boundary: plain always reuses, and its closing rows end before the stop token (the next prefill chunk computes it). MTP reuses with the stop token's row already computed by the verify pass (one-row shift of the next chunk), or replays everything when the verify also committed a draft after the stop.
- [x] 3.3 H4: not run (2.3 read `DIFF`, and the fix below removes every `DIFF`).
- [x] 3.4 H2: not run, same reason.
- [x] 3.5 H3: not run, same reason.
- [x] 3.6 Cause, recorded in `$SCR/c110/steps.txt`: the REPL's MTP loop breaks on a stop token found inside a verify block but leaves the session where the verify left it, with the stop token committed (and, at depth 3, a draft after it). Plain decode never evaluates the stop token. The server already rewinds such blocks (`speculative boundary rewind`); the REPL did not. This is a real difference in the evaluated tokens, so D4 says fix it.

## 4. Fix or decision (design D4)

- [x] 4.1 `ds4_cli.c` `run_chat_turn`: count the kept tokens of a verify block. If fewer than the block, `ds4_session_rewind` to the kept frontier. The rewind lands on the verify snapshot (`snap_pos` = block start + 1, `snap2_pos` = + 2), so nothing is recomputed; plain decode's branch is untouched. `rg PROBE-110` finds nothing. Step checks as in 2.2, all green.
- [x] 4.2 S0 after the fix, Q4, image case and `--text-turns`, at auto, 2 and 3: SAME on every turn, exit 0, per-turn prefill sizes equal in both modes (1048 26 1039 26; 34 25 28 21). Plain stdout byte-equal to before the fix in both conversations; only MTP moved, onto plain. `tests/model_gates.sh` on Q4: all PASS (mtp-identity 36/36 SAME, mtp-limits, mtp-turns, ds4_test, vision `--compare` on orbit/maple, host-paths).
- [x] 4.3 `ab_bench --a <main checkout at 76eec2a> --b . --bitwise -m <Q4> --budget 600`: `PASS (tokens; bitwise)`, 24 pairs, thermal Nominal. Every metric within noise: plain decode -0.0%, prefill 8192/+512/+2048 +0.5/+0.3/-0.1%, MTP code decode +0.0%, prose +0.1%, tokens/cycle unchanged. The bench does not link the REPL, so it sees no changed code.
- [x] 4.4 Not needed: the fix is free and bit-identical.

## 5. Review and closing

- [x] 5.1 Final pass: the rewind runs only in the speculative branch. Distributed and CPU sessions return one token per call, so for them kept equals the block. A rewind that misses a snapshot falls back to a replay at the next sync, which is no worse than before. The one-shot generation loop has no next turn and stays as it is. The docs claim of no recomputation was checked against `snap_pos`/`snap2_pos` and the accept path, which leaves the snapshots valid.
- [x] 5.2 Parity from the StarForge checkout (`SF_CHILD_DIR` = this worktree, Q4): `PARITY OK (10 prompts)`.
- [x] 5.3 Record row against segment 1's start (`seg1-91f225a`, `--kinds plain,mtp-code`, Q4, 20 pairs, PASS tokens): plain decode 57.6 (+5.8%), MTP code decode 90.0 (+25.8%), tokens/cycle 2.46 (+34.6%). Added to `speed-bench/perf-record.md`.
- [x] 5.4 S0 in `docs/TESTING.md` (commands and a paragraph), `docs/SPECULATIVE_DECODING.md` (turn-boundary rule), the `AGENTS.md` model-gate line, and `tests/model_gates.sh`: new `mtp-turns` gate (`--text-turns --compare`); the vision gate gains `--compare`.
- [x] 5.5 Q2 (`gguf/Qwen3.8-Flash-Next-Q2.gguf`): `tests/model_gates.sh` all PASS (mtp-identity 36/36 SAME); S0 image case and `--text-turns` at auto, 2 and 3: SAME every turn, prefill sizes equal.
- [x] 5.6 `openspec validate 110-mtp-image-turn-divergence --strict` passes.
- [x] 5.7 Report to the user in Italian. Do not commit. On request, land one signed commit on `main` (message draft: `$SCR/msg110.txt`).
  (2026-11-15: landed under the owner's standing permission to commit and merge when every gate is green.)

**State at the GPU stop (2026-11-15, owner notice).** Every model run had
already finished: 1.1-5.6 are done, with no GPU step left. The worktree is
uncommitted, and its binaries are current (`sf-q3-8flash` built after the
last `ds4_cli.c` edit; only docs, tasks and `perf-record.md` changed since).
`grep PROBE ds4_cli.c ds4.c` finds nothing. Remaining: only 5.7 (the report,
then a signed commit on request). If the owner wants a re-check after
rebasing on `main` (which gained `76eec2a`, docs only), run, one at a time:
`tests/model_gates.sh <Q4> --mmproj <abs>/gguf/mmproj-Qwen3.8-Flash-Next-Q8_0.gguf --image tests/vision-fixtures/qwen38/orbit.png --image tests/vision-fixtures/qwen38/maple.png`,
and `python3 tests/test_qwen4_cli_vision.py --model <Q4> --vision <MMPROJ> --image <IMG1> --image <IMG2> --compare`.
