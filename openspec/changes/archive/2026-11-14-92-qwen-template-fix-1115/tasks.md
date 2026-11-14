# Tasks

Starts from `main` with `90-upstream-sync-b3f5018` landed. `<Q4>` is the
child's `qwen3.8-flash-next.gguf`. `$SCR` is `~/.sf/q3-8flash/scratch`, and
this change's files go in `$SCR/c92/`. Model runs are strictly sequential, and
nothing else runs beside one.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `./ds4_test --server`, ending with its pass line.

## 1. Branch and sources

- [x] 1.1 `git config rerere.enabled true`; `git switch -c fix/92-qwen-template-fix-1115`. Verify with `git status --short --branch`.
- [x] 1.2 `git fetch upstream pull/1115/head`. Verify that `git log --oneline -3 FETCH_HEAD` lists `c544020`, `f5e419d` and `485902a`, and save `git show f5e419d c544020` to `$SCR/c92/pr.diff`.

## 2. Step 1: render baseline (design D1)

- [x] 2.1 Port only the `--qwen-render` entry of `tests/ds4_test.c`, calling `render_chat_prompt_text_for_syntax` and ignoring `PRESERVE`. Run the step checks.
- [x] 2.2 Write the corpus in `$SCR/c92/corpus/` (design D1). Render every case with `./ds4_test --qwen-render` into `$SCR/c92/before/`. Verify one file per case, none empty.

## 3. Step 2: the port (design D2)

- [x] 3.1 Apply `f5e419d`'s `ds4_server.c` hunks (Qwen branches only), its unit tests and its docs, and `c544020`. Delete the GLM/DeepSeek branches. Verify that `rg -n 'SERVER_MODEL_SYNTAX_(GLM|DEEPSEEK)' ds4_server.c` finds nothing new.
- [x] 3.2 Add `tests/test_qwen4_reasoning_retention.py` and its line in `docs/TESTING.md`. Verify `python3 tests/test_qwen4_reasoning_retention.py --help` exits 0 without a model.
- [x] 3.3 Run the step checks. Verify that the new unit tests (`test_render_qwen_reasoning_parity` and the kwargs alias cases) run inside `./ds4_test --server`, by name in its output or with a deliberate failing assert removed again.
- [x] 3.4 Render the corpus again into `$SCR/c92/after/` and diff it against `before/`. Verify that only the cases in the four classes of proposal.md differ, and each only where its class says. Record the diff summary in `$SCR/c92/steps.txt`.
- [x] 3.5 Step review: read the whole diff and every function it touches; fix what would break a child rule (AGENTS.md trust-boundary validation, `sf-ablate` markers at cuts).
- [x] 3.6 Owner questions from the step review, decided 2026-11-14 (owner delegated): (a) `\b` and `\f` in tool schemas stay `\u0008`/`\u000c`, the spelling `json_escape` and the PR use; the difference from Python `tojson` reaches only schemas holding those control characters. (b) A history with no real user query keeps the PR's window (whole history, or only the newest turn past 50 messages) rather than the template's error: a request is answered instead of refused. (c) `preserve_thinking` and the control-token trace stay on `/v1/chat/completions` only, as upstream; the Anthropic and Responses endpoints are a separate change if a client needs them.

## 4. Model gates (Q4)

- [x] 4.1 `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout: `PARITY OK`. The CLI path is untouched, so any token difference is a defect to report. (PARITY OK, 10 prompts, 2026-11-14.)
- [x] 4.2 `python3 speed-bench/ab_bench.py --a <worktree at main> --b . --bitwise --budget 600`: `PASS (tokens; bitwise)`. This is a guard; no record row, since nothing claims speed. If the token gate fails, stop and report (proposal.md). (PASS (tokens; bitwise), 18 pairs. The MTP decode medians read -6..-7% while the 100 analysis loaded the CPU; the bench binary's code section is identical to main's (`otool -t` hashes equal), so the figure is noise. No record row.)
- [x] 4.3 `DS4_TEST_MODEL=<Q4> ./ds4_test`, compared against the baseline table in `docs/TESTING.md`: no new failure. (Run inside `tests/model_gates.sh`: ds4_test PASS against the five known failures; MTP identity, limits, vision and host paths PASS too.)
- [x] 4.4 `python3 tests/test_qwen4_reasoning_retention.py --model <Q4> --out $SCR/c92/retention`: every arm passes or reports INCONCLUSIVE with its reason. Record the reuse figures next to the PR's (1279/1281 live, 1281/1281 after a restart). (15 checks pass, 1 INCONCLUSIVE: D1, neither arm replayed the opener. Reuse 1279/1281 live, 1281/1290 after a restart; the PR reports 1279/1281 and 1281/1281.)

## 5. Review and closing

- [x] 5.1 Final pass over the touched region (AGENT.md, surrounding idiom, dead code the port left). (Read the server diff end to end: renderer, retention window, kwargs precedence, trace table, JSON recoding; nothing changed.)
- [x] 5.2 Update #1115's rows in `docs/upstream-prs.md`: `f5e419d` and `c544020` to `adopt -> 92-qwen-template-fix-1115`, with what the corpus and the retention run showed; `tests/template_parity_ab.py` not ported (design D3).
- [x] 5.3 `openspec validate 92-qwen-template-fix-1115 --strict` passes.
- [x] 5.4 Report to the user in Italian: the corpus diff, the retention figures, the gates, the decisions. Commit only when the owner asks: one signed commit with the PR author as `Co-authored-by`. (Reported 2026-11-14; commit waits for the owner.)
