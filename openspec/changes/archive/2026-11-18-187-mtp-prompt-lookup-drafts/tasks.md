# Tasks

GPU: 1.2 (one vocabulary export), sections 3 and 4. Model runs are strictly
sequential; a process that opens a GGUF is a model run, the vocabulary
export included. `$SCR` is `~/.sf/q3-8flash/scratch`; this change's files go
in `$SCR/c187/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names.

## 1. Step 0: offline measurement (design D1)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/187-mtp-prompt-lookup-drafts`. `git fetch upstream pull/1179/head`; check the head is still `79c914c` or record the new commits; save `7e6ab2f`'s diff to `$SCR/c187/`. *(2026-11-18: head still `79c914c`. The commit is 755 insertions over nine files, not only `ds4.c`: it also widens the verify to 16 rows; see design D7.)*
- [x] 1.2 In a GPU window with nothing else resident: export the vocabulary once (`tests/test_tokenizer --export-vocab`). Everything else in this section reads that export.
- [x] 1.3 Collect the transcripts: the checkpoint-replay conversations and the owner's agent turns. Tokenize them; keep prompt and output ids apart. *(There are no recorded conversations under `speed-bench/`, and no agent turns on this machine: the 331 disk-KV checkpoints of the service, read only for their token lists, are single-turn chats with reasoning and hold no tool call. Used: those 312 chat turns, and one synthetic tool loop from `speed-bench/agent_reuse.py` on Q4, labelled as synthetic. Real edit and tool-call transcripts are still owed to this measurement.)*
- [x] 1.4 The oracle script: match share, acceptance of the first three looked-up tokens, run-length histogram, per workload and per k. Record the tables in `$SCR/c187/steps.txt`. *(Tables in design D6.)*
- [x] 1.5 *(Does not stop: 24-35% on the synthetic tool calls, 12-22% on real chat prose; design D6.)* Apply D1's stop rule. If it stops here: record the figures in `docs/upstream-prs.md` (`7e6ab2f` to `measured, not needed`), report, archive.

## 2. Step S1: the port (design D2, D3; no GPU)

- [x] 2.1 Port `7e6ab2f` hunk by hunk onto the child's cycle and field names. Find every reader of the fields it touches with `rg` first. *(Only the index is ported; the 16-row verify, its snapshots and kernels are outside this proposal. Every writer of `glm_mtp_have`/`glm_mtp_draft` was read: `qwen4_session_drafts` and the batch path, which now marks its drafts as the predictor's. Design D7.)*
- [x] 2.2 Per-source acceptance window; the kill switch; the minimum match length from step 0. *(Two eight-verdict windows scored on every verify; `DS4_QWEN4_MTP_LOOKUP=0`; minimum 6.)*
- [x] 2.3 Decide D3 from the code, and write the decision in the spec delta. *(Lookup stays on under exact sampling; design D7.)*
- [x] 2.4 Model-less tests: the index (match, extend, rewind) and the predictor state after a lookup cycle. The step checks. *(`test_lookup` in `tests/test_session_state.c`: match, minimum agreement, extension, rewind, context bounds, and the source choice. The predictor runs its catch-up and first draft on every cycle exactly as before, so its state after a lookup cycle is the state after a depth-2 cycle; that is covered with the model, by the identity gates of 3.2.)*
- [x] 2.5 Step review of the whole ported region. *(Found and fixed: a second argmax over the row-0 logits per cycle, which read -0.2% on `mtp-prose`; the health threshold written twice. Measured again after it.)*

## 3. Model checks (design D4)

- [x] 3.1 The copy-heavy bench kind: its prompt file under `speed-bench/` and its entry in `ab_bench.py`. *(`speed-bench/copy_edit.txt` and the kind `mtp-copy`, which runs only when `--kinds` names it, so the default run and the record row keep their shape.)*
- [x] 3.2 `tests/model_gates.sh` on Q4 and Q2 with lookup on: every gate `PASS`. *(Both packs, on the first cut and again on the final code: identity, limits, turns, `ds4_test`, vision, host paths.)*
- [x] 3.3 `ab_bench.py`, lookup off against on, the three kinds. Keep or drop by D4; record tokens per cycle per source, the index's memory and build time. *(**Kept.** Figures in design D8.)*

## 4. Review and closing

- [x] 4.1 Final pass; remove the kill switch unless the measurement says the gain depends on the workload enough to keep it. *(`DS4_QWEN4_MTP_LOOKUP=0` stays: the gain exists on one kind of workload only, and the spec names the switch. Nothing else to remove: the experiment that skipped the predictor's draft head was not kept.)*
- [x] 4.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row. *(`PARITY OK`, 10 prompts, upstream `b3f5018`. Against `main`: `PASS (tokens; bitwise)`, 24 pairs. Against the segment start `91f225a`: `PASS (tokens)`, 24 pairs, row appended.)*
- [x] 4.3 `docs/upstream-prs.md`: `7e6ab2f` to `adopt -> 187-mtp-prompt-lookup-drafts` with the figures; the MTP doc gains the lookup source.
- [x] 4.4 `openspec validate 187-mtp-prompt-lookup-drafts --strict` passes.
- [x] 4.5 *(Landed by the night executor under the standing rule for local `main`: one signed commit with the upstream author as `Co-authored-by`; push is the owner's. D5: on the synthetic tool loop about half of the 6-token matches run four tokens or longer, 40% on real chat turns; real edit transcripts should decide the follow-up.)* Report to the user in Italian, with step 0's histogram and whether D5's follow-up is worth proposing. Land as one signed commit, with the upstream commit's author as `Co-authored-by`; delete `$SCR/c187/`; archive the change (syncs the `mtp-speculation` delta).
