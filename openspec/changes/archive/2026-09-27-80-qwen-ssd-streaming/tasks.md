# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child checkout.

`<Q2>` is the Q2 pack in the Hugging Face cache:
`~/.cache/huggingface/hub/models--antirez--qwen3.8-flash-next-gguf/snapshots/d600fe1a43d2e1cdcadb85144ce3142f66f9eefe/Qwen3.8-Flash-Next-Q2.gguf`,
expanded to an absolute path.

`$SCR/c80/` holds this change's files, with `$SCR` outside `/tmp`
(`~/.sf/q3-8flash/scratch`), so a reboot does not erase them. `X` is the pathspec `-- . ':!openspec'`.

`S` stands for the streamed bench arguments: `--b-bench-arg=--ssd-streaming`
for a streamed-against-resident comparison, or `--bench-arg=--ssd-streaming`
for a comparison of two streamed runs.

`E48` stands for `--b-bench-arg=--simulate-used-memory --b-bench-arg=80GB`.
`E40` is the same with `88GB`: the smallest machine this host can emulate, since the kernel lets a process wire at most 108.8 GiB and Metal buffers count against it (a 96 GiB lock leaves too little and is refused). The emulation goes to B only: B streams, so it
plans within the memory left. A resident A side beside a locked 80 GiB hung the
machine once (2026-09-26); the engine now refuses that combination.

**Model runs are strictly sequential.** Nothing runs beside one: no other
model run, no test and no build. Before each run:
- wait until the thermal state is Nominal;
- give the run a fresh `--out` directory;
- do not rebuild or edit `metal/*.metal` while a model runs from the tree.

"The step checks":
- `make -j8`, with no warnings;
- `make test -j8`, whose output names the suites;
- `make test-qwen4-kernels`, whose hashes must equal `main`'s unless the
  step says otherwise;
- `make test-qwen4-q2`;
- `make test-qwen4-ssd-experts` and `make test-qwen4-memory`, once they
  exist;
- `python3 tests/test_ab_bench.py`.

"The step review": read `git diff <previous snapshot> X` and every function
the diff touches. Record the findings in `$SCR/c80/review.md` and fix the
*fix now* ones.

## 1. Branch, intake, references

- [x] 1.1 With only this change's `openspec/` artifacts modified, run `git config rerere.enabled true`, then `git switch -c feature/80-qwen-ssd-streaming`.
- [x] 1.2 Fetch the PR: `git fetch upstream refs/pull/1056/head:refs/remotes/upstream/pr-1056`. Verify that its head is `4642526`, or record the new head and any commit after it.
- [x] 1.3 In `docs/upstream-prs.md`, add lines for `81ee4ba` (adopt, `80`), `089d966` (idea, a later MTP change) and `4642526` (split: the SSD tests go to `80`, the Q4 decode part to a later Q4 change). Update #1056's head and its commit count.
- [x] 1.4 Mark with `sf-keep: used by Qwen SSD streaming (80); revisit after it lands` every `ds4_gpu_stream_expert_cache_*` entry point, and every `ssd_streaming` helper, that `e37f185` calls. Get the list from `git show e37f185 | rg -o 'ds4_gpu_stream_expert_cache_[a-z_]+' | sort -u`.
- [x] 1.5 Situation 0, one after the other: `tools/parity-check.sh sf-q3-8flash <Q4>`, then with `<Q2>`. Snapshot `T_0`. Create the worktrees:
  - `git worktree add --detach ../sf-q3-8flash-prev main`;
  - `git worktree add --detach ../sf-q3-8flash-start 91f225a`.

## 2. Step S0: bench arguments (design D5)

- [x] 2.1 Add `--bench-arg ARG` and `--b-bench-arg ARG` to `speed-bench/ab_bench.py`. Both are repeatable and appended after the harness's own bench arguments. The header names them, and the record row is suppressed with a reason.
- [x] 2.2 Add unit tests for the three spec scenarios, and a README usage line. Verify that `python3 tests/test_ab_bench.py` prints `OK`.
- [x] 2.3 Run the step checks, the step review, and an A/A resident run with `<Q4>` using `--bench-arg=--show-output`, a flag the harness already passes. Verify the CIs contain 0. Snapshot `T_S0`.

## 3. Phase A: the foundation

- [x] 3.1 Port `e37f185` onto the child: the cache, admission, bind paths, function constant 906 in the PR's kernels, the two test programs and their Makefile targets, and the n-gram test update. Resolve by hand against the child's kernels, keeping the child's arithmetic. Lift the refusal for `ssd_streaming` only, with the PR's text.
- [x] 3.2 Port `81ee4ba`.
- [x] 3.3 Extend the address path to the child's kernels of design D2. Where a kernel cannot take it, select the PR's addressed generic kernel on the host while streaming only. Add addressed-against-resident byte-exact cases to `test_qwen4_ssd_experts` for each of them, at T 1, 2, 32, 33 and 128.
- [x] 3.4 Run the step checks. Verify that `make test-qwen4-kernels` hashes equal `main`'s, and that both new tests pass and name their cases.
- [x] 3.5 Step review.
- [x] 3.6 Resident gate: `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise --budget 600` with `<Q4>`, then with `<Q2>`. Verify `PASS (tokens; bitwise)` and no metric's pooled CI wholly below 0.
- [x] 3.7 Streamed identity, one after the other, for `<Q4>`, then `<Q2>`:
  - `ab_bench.py --a . --b . --b-bench-arg=--ssd-streaming --budget 600`;
  - the same with `E48`;
  - the same with `E40`.

  Verify that every run prints `PASS (tokens)`. Record the streamed/resident ratios in `steps.txt`.
- [x] 3.8 Admission probe: open Qwen with `--ssd-streaming --simulate-used-memory 96GB`, a single run. Verify that it refuses with both GiB figures (the wire room left is below the fixed need). Also probe the resident guard with a sparse fake model and a small lock. Snapshot `T_A`.

## 4. Phase B: overlap and I/O (design D4)

- [x] 4.1 A/A streamed noise floor: `ab_bench.py --a . --b . --bench-arg=--ssd-streaming --bench-arg=--simulate-used-memory --bench-arg=80GB -m <Q4> --budget 600` (both sides stream, so both may carry the lock). Record the half-widths.
- [x] 4.2 Bring `../sf-q3-8flash-prev` to `T_A`. For each step in order, port it, then run the step checks and the step review. Then run two A/Bs against prev:
  - streamed: `ab_bench.py --a ../sf-q3-8flash-prev --b . --bench-arg=--ssd-streaming --bench-arg=--simulate-used-memory --bench-arg=80GB` (both sides stream);
  - resident guard: `--bitwise`, no bench arguments.

  Keep the step by the rule of design D4, snapshot `T_<step>` and bring prev to it; otherwise restore. Record every result.

  The steps, in the PR's order (`9e1429b`'s smaller MTP reserve is safe only once `85d37ae` stages the selected MTP experts):
  - `e2b4a47`;
  - `85d37ae`, judged with `<Q2>`;
  - `d6cbc77` + `81b9ebb`, one step (the second extends the first's overlap to MTP verification and down);
  - `9e1429b`;
  - `5cbdb6e`, SSD part only;
  - `2ba92ab` + `fd0c24a`;
  - `47ca2eb`;
  - the SSD tests of `4642526`, a tests-only step judged by the step checks.

## 5. Review and refine

- [x] 5.1 Final pass over the ported region against `AGENT.md`, and over the child's idiom. Delete what the change made dead, and check that every `sf-keep` added in 1.4 is still accurate. Record *take* and *leave*.
- [x] 5.2 Apply the *take* findings. Measure them like a step, with both the resident gate and a streamed A/B.

## 6. Docs, registry, closing

- [x] 6.1 Update `AGENTS.md` (design D6), `docs/SSD_STREAMING.md` and `docs/QWEN38_FLASH_NEXT.md`: how to enable streaming, the cache sizing, and the measured minimum RAM and decode/prefill rates at E48 and E40, for both packs. Also update each routed commit's registry line with its outcome.
- [x] 6.2 Run the end checks, one after the other: parity with `<Q4>`, then with `<Q2>`; then `tests/test_qwen4_mtp_limits.py` for both packs; then `DS4_TEST_MODEL=<Q4> DS4_TEST_GLM_MTP=1 ./ds4_test`.
- [x] 6.3 Change result. The resident A/B against `main` runs with `--bitwise`, for both packs, followed by the record rows against `../sf-q3-8flash-start` for both packs, appended to Segment 1. The streamed summary at E48 and E40 for both packs goes to `docs/SSD_STREAMING.md`, not to the record.
- [x] 6.4 Final snapshot. Verify that `openspec validate 80-qwen-ssd-streaming --strict` passes.
- [x] 6.5 Report to the user in Italian: each step with its figures, the identity results, the memory figures, the review findings, and the decisions taken. Do not commit. On request, land one signed commit on `main` with the #1056 author as `Co-authored-by`, and remove the worktrees.
