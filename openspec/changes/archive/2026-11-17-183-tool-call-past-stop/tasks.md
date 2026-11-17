# Tasks

GPU: live fault-injection checks and guards on Q4 (section 4). Sections 1-3 are model-less.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c183/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `./ds4_test --server`, reading the names of the new tests in
its output.

## 1. Branch and references (no GPU)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c fix/183-tool-call-past-stop`. `git fetch upstream pull/1071/head pull/997/head`; check the heads are still `1018c65` and `4c6a9c3`; save both diffs to `$SCR/c183/`.
- [x] 1.2 Re-read `130`'s design and `docs/SERVER.md` "Tool calls" / "Unfinished turns"; record in `$SCR/c183/notes.txt` the line of every stop site in `generate_job_inner` (sampled, drafted, batched MTP). The `main` worktree for `ab_bench` moved to 4.0, the first step that needs it, under `.claude/worktrees/` (the session rule for new worktrees).

## 2. Step S1: tracker structural advance (design D2; no GPU)

- [x] 2.1 Port #997's structural-loop fix. Add the byte-by-byte prefix tests over Qwen calls with stray bytes (after `<tool_call>`, between parameters, before `</tool_call>`, a long run). Revert the fix once and record that the tests fail.
- [x] 2.2 Run the step checks; step review.

## 3. Step S2: stop override (design D1, D3, D5; no GPU)

- [x] 3.1 Add `tool_call_stop_override()` and its unit test. Apply it at the sampled-token site and, per token, at the drafted-token site (`resample = true`). Add the suppression count to the incomplete-call warning, without the text tail.
- [x] 3.2 Run the step checks; step review: every stop site from 1.2, `ignore_eos` and batched MTP included; `130`'s calls-cut path and `160`'s end-token path unchanged.

## 4. Live checks and guards (GPU: Q4, sequential)

How to run (prepared model-less; `W` is this worktree, `S=$SCR/c183`):
- The fault patch is `$S/fault-injection.patch`, a scratch file that is never
  committed. With it, the server replaces the first sampled token after
  `<function=` with `<|im_end|>` once per request. `DS4_C183_FAULT_N=30`
  keeps injecting on every later sampled token of the call (the bound
  variant). Each injection logs `c183 fault: injected stop #N`.
- Apply and build: `cd $W && git apply $S/fault-injection.patch && make -j8`.
- One server at a time, each run in this order:
  - `./sf-q3-8flash-server -m <Q4> --port 8004 2>&1 | tee $S/srv-plain.log`,
    then `$S/fault-requests.sh 8004`, then stop the server;
  - the same with `--mtp` (`srv-mtp.log`);
  - the bound variant: `DS4_C183_FAULT_N=30 ./sf-q3-8flash-server -m <Q4> --port 8004`
    (`srv-bound.log`), then the same requests.
- Expected with one injection: each of the three requests carries the call
  whole (OpenAI `finish_reason: "tool_calls"`, Anthropic
  `stop_reason: "tool_use"`). Each log has one `injected stop #1` and one
  `1 stop token(s) inside an open tool call suppressed` per request, and no
  `incomplete Qwen tool call`.
- Expected with the bound variant: `24 stop token(s) ... suppressed`, then
  `incomplete Qwen tool call: stop=stop token ... suppressed=24`. The
  non-streamed request then takes the tool-error continuation; the streamed
  ones take #1163's parse-failure recovery. No `finish_reason: "error"`. The
  injection count is per request and the suppression count is per decode pass,
  so the non-streamed continuation pass can log up to 5 more suppressions
  (injections 26-30).
- Revert: `git checkout ds4_server.c && make -j8`; `git status` must be clean.

- [x] 4.0 `git worktree add --detach .claude/worktrees/183-prev main` and `make -j8` in it (the `--a` side of 4.3). Done with the existing `.claude/worktrees/prev-main`, built at `main` (`174a2a1`); no `183-prev` was created. `main` was merged into the branch first (it was cut before 180/181).

- [x] 4.1 Scratch-only fault injection (design D6), never committed: OpenAI streamed and non-streamed, Anthropic stream, each with and without `--mtp`. Each returns the closed call whole, `finish_reason: "tool_calls"`, one suppression warning. The 30-injection variant ends in today's fallbacks. Record in `$SCR/c183/steps.txt`; remove the patch. Result: all six return the call whole with one suppression warning. The prepared patch never fired (the tokenizer joins `=` with the function name, so the text never ends in `<function=`); it now injects at the first sampled token once the call text contains `<function=`. An extra injection at the drafted site (`ti > 0`, `--mtp`) also returns the call whole. The bound needs a call with more than 24 sampled tokens left (`/etc/hosts` has 21, all suppressed, call whole): with a long path each request logs `24 stop token(s) ... suppressed` and `incomplete Qwen tool call ... suppressed=24`; non-streamed takes the tool-error continuation (5 more suppressions, `tool_calls`), streamed takes the parse-failure recovery (`stop` / `end_turn`); no `error`.
- [x] 4.2 `DS4_TEST_MODEL=<Q4> ./ds4_test --tool-call-quality` passes.
- [x] 4.3 `tests/model_gates.sh <Q4>`: every gate `PASS`. `python3 speed-bench/ab_bench.py --a .claude/worktrees/183-prev --b . -m <Q4> --bitwise --budget 600`: `PASS (tokens; bitwise)` (design D4).
- [x] 4.4 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`.

## 5. Review and closing

- [x] 5.1 Final pass over the touched region. One refinement: the suppression warning lost its `(finish=...)` field, which printed the loop's `stop` beside the turn's `tool_calls`; gates re-run on that code.
- [x] 5.2 `docs/SERVER.md` "Unfinished turns": a stop token inside an open call; `docs/upstream-prs.md`: `1018c65` and `4c6a9c3` to `adopt -> 183-tool-call-past-stop`.
- [x] 5.3 `openspec validate 183-tool-call-past-stop --strict` passes.
- [x] 5.4 Report to the user in Italian. Land as one signed commit, with the PR authors as `Co-authored-by`; delete `$SCR/c183/`; archive the change (syncs the `server-protocol` delta).
