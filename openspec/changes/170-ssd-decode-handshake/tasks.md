# Tasks

Starts from `main` with `90` and `120` landed. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`; `$SCR` is `~/.sf/q3-8flash/scratch`, and this
change's files go in `$SCR/c170/`. Model runs are strictly sequential, each at
the Nominal thermal state. **Never emulate used memory on a resident run.**

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `tests/test_qwen4_ssd_experts`, reading its pass line.

## 1. Branch and references

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/170-ssd-decode-handshake`. `git fetch upstream pull/1328/head`; save the six commits' diffs to `$SCR/c170/`. Verify that the PR head is still `2d48e3b`, or record the new commits.
- [ ] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it.
- [ ] 1.3 Design D2 and D3 by reading: record in `$SCR/c170/notes.txt` how an invalid id is handled, and where slab allocation happens relative to admission.

## 2. Step S1: the port (design D1)

- [ ] 2.1 Port the six commits as one unit, without the early-commit switch. Keep one copy of the slot-return logic shared with `120`.
- [ ] 2.2 Add the invalid-id test (design D2) and a failed-load / cancelled-request test for the handshake. Run the step checks.
- [ ] 2.3 Step review: the diff and every function it touches.

## 3. Correctness and memory gates

- [ ] 3.1 Resident unchanged: `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --budget 600`, `PASS (tokens; bitwise)`.
- [ ] 3.2 Streamed equals resident: `ab_bench.py --a . --b . --b-bench-arg --ssd-streaming`, token gate PASS on plain and MTP kinds.
- [ ] 3.3 Streamed at emulated 48 GB on the B side only: token gate PASS against resident. Record the peak footprint against the admitted budget (design D3).

## 4. Measurement (design D4)

- [ ] 4.1 `ab_bench.py --a ../sf-q3-8flash-prev --b . --bench-arg --ssd-streaming --bench-arg --simulate-used-memory <X>`, emulating 48 GB, plain and MTP kinds. Pool; keep the change by D4's rule. Record the figures in `$SCR/c170/steps.txt`.
- [ ] 4.2 If neutral or worse: drop the change, restore `main`'s files, record the figures.

## 5. Review and closing

- [ ] 5.1 Final pass: no dead code in the `.inc` files; decide on `DS4_QWEN4_STREAM_HANDSHAKE`; measure refinements like a step.
- [ ] 5.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. A resident `ab_bench.py` run against the current segment's start; append its row with step `perf/170-ssd-decode-handshake`. Put the streamed figures in the commit message.
- [ ] 5.3 `docs/SSD_STREAMING.md` (the handshake, its switch, the up-front slabs) and `docs/upstream-prs.md` (#1328's six lines).
- [ ] 5.4 Q2: list the streamed Q2 run as pending the owner's approval of the download.
- [ ] 5.5 `openspec validate 170-ssd-decode-handshake --strict` passes.
- [ ] 5.6 Report to the user in Italian. Commit only when the owner asks: one signed commit, with the PR author as `Co-authored-by`.
