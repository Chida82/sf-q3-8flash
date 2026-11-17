# Tasks

Starts from `main` with `90` and `120` landed. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`; `$SCR` is `~/.sf/q3-8flash/scratch`, and this
change's files go in `$SCR/c170/`. Model runs are strictly sequential, each at
the Nominal thermal state. **Never emulate used memory on a resident run.**

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `tests/test_qwen4_ssd_experts`, reading its pass line.

## 1. Branch and references

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/170-ssd-decode-handshake`. `git fetch upstream pull/1328/head`; save the six commits' diffs to `$SCR/c170/`. Verify that the PR head is still `2d48e3b`, or record the new commits. *(2026-11-16: head still `2d48e3b`; diffs in `$SCR/c170/1-6-*.diff` and `all.diff`.)*
- [x] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it. *(Replaced by the existing read-only reference worktree `.claude/worktrees/prev-main`, which is at `ceccded`: before the GPU gates it must be moved to `main` (`de4d6f6`, which adds change 150 in `ds4.c`) and rebuilt. Wherever these tasks say `../sf-q3-8flash-prev`, use that worktree.)* *(2026-11-17: `prev-main` moved to `main` `20db558` and rebuilt; the branch merged with it.)*
- [x] 1.3 Design D2 and D3 by reading: record in `$SCR/c170/notes.txt` how an invalid id is handled, and where slab allocation happens relative to admission. *(Done; conclusions copied into design D2, D3, D4 and Risks.)*

## 2. Step S1: the port (design D1)

- [x] 2.1 Port the six commits as one unit, without the early-commit switch. Keep one copy of the slot-return logic shared with `120`. *(120's `ds4_gpu_stream_expert_give_back_buffers` is the one copy; #1328's `ds4_gpu_stream_expert_return_load_reservations` is not ported. The doc lines wait for 5.3, after the keep/drop decision.)*
- [x] 2.2 Add the invalid-id test (design D2) and a failed-load / cancelled-request test for the handshake. Run the step checks. *(Both tests written in `tests/test_qwen4_ssd_experts.c`; `make -j8` and the test binary build with no warnings; `make test -j8` passes (CPU-only suites). `tests/test_qwen4_ssd_experts` needs Metal: its run is pending the GPU.)* *(2026-11-17, Metal: exit 0, 103 `PASS` lines, no `FAIL`; the handshake cases report "via the decode handshake", with the failed read, the invalid ids and the cancel-and-retry.)*
- [x] 2.3 Step review: the diff and every function it touches. *(Found and fixed: the experts failing to encode after the release wait skipped the release and hung the next drain.)*

**Outcome (2026-11-18): dropped at 4.2.** The port is correct (unit tests, token
gates, resident bitwise, footprint) and at par with upstream's, but streamed
plain decode at emulated 48 GB is 2.7% slower on Q2, D4's target metric.

## 3. Correctness and memory gates

- [x] 3.1 Resident unchanged: `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --budget 600`, `PASS (tokens; bitwise)`. *(2026-11-17, Q4, 23 pairs: `PASS (tokens; bitwise)`; plain decode +0.7% (-2.7..+3.5), no range wholly below zero.)*
- [x] 3.2 Streamed equals resident: `ab_bench.py --a . --b . --b-bench-arg --ssd-streaming`, token gate PASS on plain and MTP kinds. *(2026-11-17: Q4 `PASS (tokens)`, all three kinds token-checked; Q2, where the handshake runs, `PASS (tokens)` on plain and both MTP kinds.)*
- [x] 3.3 Streamed at emulated 48 GB on the B side only: token gate PASS against resident. Record the peak footprint against the admitted budget (design D3). *(2026-11-17, Q2 only: `PASS (tokens)`, all three kinds token-checked against resident. Footprint, one plain run per build under `/usr/bin/time -l`: branch 19.28 GiB planned (2412 cached experts, 3.35 GiB), peak footprint 90.27 GiB = 80 locked + 10.27; `main` 19.30 GiB planned, 90.28 GiB. The up-front slabs do not raise the peak; both stay 9 GiB under lock + plan. Q4 not run: dropped at 4.2.)*

## 4. Measurement (design D4)

- [x] 4.1 `ab_bench.py --a ../sf-q3-8flash-prev --b . --bench-arg --ssd-streaming --bench-arg --simulate-used-memory <X>`, emulating 48 GB, plain and MTP kinds. Pool; keep the change by D4's rule. Record the figures in `$SCR/c170/steps.txt`. *(Q2, `80GB` locked, three runs in windows with no other workload, tokens PASS, pooled bootstrap 95% CI of the median pair ratio, 8 pairs per kind: plain decode 29.2 -> 28.5 t/s, **-2.7% [-2.9%, -2.1%]** (cache 3.35 GiB at the kind's 10.8K context); plain prefill 8192 -0.3% [-0.8%, +0.1%], +512 +1.3% [-3.1%, +3.7%], +2048 -0.2% [-0.7%, +0.9%]; mtp-code decode 37.4 -> 38.9, +4.0% [+3.5%, +4.3%]; mtp-prose decode 37.9 -> 38.1, +3.5% [-2.8%, +5.0%]; MTP prefill within their CIs. Aside, by hand A B B A, plain at a 2048-token context, where the plan holds 9.5 GiB of experts: 33.36 -> 34.77, +3.9% [+3.3%, +5.3%], 8 pairs. Q4 not run: dropped at 4.2.)*
- [x] 4.1b For information, best effort, at most 45 minutes (owner, 2026-11-17): upstream's PR head `2d48e3b` against this branch, Q2, streamed at emulated 48 GB, plain decode (MTP kinds if cheap); the PR head against its base if time allows. *(Done in 25 minutes, by hand A B B A since upstream's bench has no `--frontiers`; 8 pairs each, one 8192 frontier + 64 tokens. Upstream's admission plans on `hw.memsize` and ignores the emulated lock (it would plan all 34 GiB of experts on top of 80 locked), so both sides ran with `--ssd-streaming-cache-experts 2400`, the child's own plan. PR head against this branch: 25.34 against 25.88 t/s steady, the child +2.1% [+2.0%, +2.6%], same text: the port is at par. PR base `b3f5018` against PR head: 25.63 against 25.06, the head **-2.2% [-2.7%, -1.8%]**: the original loses what the port loses here.)*
- [x] 4.2 If neutral or worse by D4's rule on the emulated figures: drop the change, restore `main`'s files, record the figures. *(**Dropped.** D4's target metric, streamed plain decode at emulated 48 GB on Q2, has its pooled CI wholly below zero. `main`'s files restored (`Makefile`, `ds4_metal.m`, `metal/qwen4.metal`, the two tests; the two `.inc` files removed). The port, with the child's release fix, is commit `dd8db0d` on the local branch `perf/170-ssd-decode-handshake`, which is kept.)*

## 5. Review and closing

- [ ] 5.1 Final pass: no dead code in the `.inc` files; decide on `DS4_QWEN4_STREAM_HANDSHAKE`; measure refinements like a step. Not run: dropped at 4.2. (Read before the decision: the switch `DS4_QWEN4_STREAM_HANDSHAKE` would have stayed, the tests use it to reach the ordinary path.)
- [ ] 5.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. A resident `ab_bench.py` run against the current segment's start; append its row with step `perf/170-ssd-decode-handshake`. Put the streamed figures in the commit message. Not run: dropped at 4.2.
- [x] 5.3 `docs/SSD_STREAMING.md` (the handshake, its switch, the up-front slabs) and `docs/upstream-prs.md` (#1328's six lines). *(Dropped: `docs/upstream-prs.md` marks #1328 and its six commits `drop` with the figures; `docs/SSD_STREAMING.md` unchanged.)*
- [x] 5.4 Q2: the Q2 GGUF is on disk (`gguf/Qwen3.8-Flash-Next-Q2.gguf` in the main checkout). Run the streamed gates (3.2, 3.3) and the measurement (4.1) on Q2 too; the handshake engages only there (design D4). *(Q2 done first, as D4 puts the handshake there: 3.2, 3.3 and 4.1 above are Q2's. Q4: 3.1 and 3.2 only.)*
- [x] 5.5 `openspec validate 170-ssd-decode-handshake --strict` passes. 
- [x] 5.6 Report to the user in Italian. Commit only when the owner asks: one signed commit, with the PR author as `Co-authored-by`. *(Closed by the night executor under the standing rule for local `main`: one signed docs commit; push is the owner's.)*
