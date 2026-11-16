# Tasks

GPU: live fault-injection checks and guards on Q4 (section 4). Sections 1-3 are model-less.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c183/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `./ds4_test --server`, reading the names of the new tests in
its output.

## 1. Branch and references (no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c fix/183-tool-call-past-stop`. `git fetch upstream pull/1071/head pull/997/head`; check the heads are still `1018c65` and `4c6a9c3`; save both diffs to `$SCR/c183/`.
- [ ] 1.2 Re-read `130`'s design and `docs/SERVER.md` "Tool calls" / "Unfinished turns"; record in `$SCR/c183/notes.txt` the line of every stop site in `generate_job_inner` (sampled, drafted, batched MTP). `git worktree add --detach ../sf-q3-8flash-prev main` and build it.

## 2. Step S1: tracker structural advance (design D2; no GPU)

- [ ] 2.1 Port #997's structural-loop fix. Add the byte-by-byte prefix tests over Qwen calls with stray bytes (after `<tool_call>`, between parameters, before `</tool_call>`, a long run). Revert the fix once and record that the tests fail.
- [ ] 2.2 Run the step checks; step review.

## 3. Step S2: stop override (design D1, D3, D5; no GPU)

- [ ] 3.1 Add `tool_call_stop_override()` and its unit test. Apply it at the sampled-token site and, per token, at the drafted-token site (`resample = true`). Add the suppression count to the incomplete-call warning, without the text tail.
- [ ] 3.2 Run the step checks; step review: every stop site from 1.2, `ignore_eos` and batched MTP included; `130`'s calls-cut path and `160`'s end-token path unchanged.

## 4. Live checks and guards (GPU: Q4, sequential)

- [ ] 4.1 Scratch-only fault injection (design D6), never committed: OpenAI streamed and non-streamed, Anthropic stream, each with and without `--mtp`. Each returns the closed call whole, `finish_reason: "tool_calls"`, one suppression warning. The 30-injection variant ends in today's fallbacks. Record in `$SCR/c183/steps.txt`; remove the patch.
- [ ] 4.2 `DS4_TEST_MODEL=<Q4> ./ds4_test --tool-call-quality` passes.
- [ ] 4.3 `tests/model_gates.sh <Q4>`: every gate `PASS`. `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q4> --bitwise --budget 600`: `PASS (tokens; bitwise)` (design D4).
- [ ] 4.4 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`.

## 5. Review and closing

- [ ] 5.1 Final pass over the touched region.
- [ ] 5.2 `docs/SERVER.md` "Unfinished turns": a stop token inside an open call; `docs/upstream-prs.md`: `1018c65` and `4c6a9c3` to `adopt -> 183-tool-call-past-stop`.
- [ ] 5.3 `openspec validate 183-tool-call-past-stop --strict` passes.
- [ ] 5.4 Report to the user in Italian. Land as one signed commit, with the PR authors as `Co-authored-by`; delete `$SCR/c183/`; archive the change (syncs the `server-protocol` delta).
