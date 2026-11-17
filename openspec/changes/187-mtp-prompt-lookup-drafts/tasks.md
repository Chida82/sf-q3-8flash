# Tasks

GPU: 1.2 (one vocabulary export), sections 3 and 4. Model runs are strictly
sequential; a process that opens a GGUF is a model run, the vocabulary
export included. `$SCR` is `~/.sf/q3-8flash/scratch`; this change's files go
in `$SCR/c187/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names.

## 1. Step 0: offline measurement (design D1)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/187-mtp-prompt-lookup-drafts`. `git fetch upstream pull/1179/head`; check the head is still `79c914c` or record the new commits; save `7e6ab2f`'s diff to `$SCR/c187/`.
- [ ] 1.2 In a GPU window with nothing else resident: export the vocabulary once (`tests/test_tokenizer --export-vocab`). Everything else in this section reads that export.
- [ ] 1.3 Collect the transcripts: the checkpoint-replay conversations and the owner's agent turns. Tokenize them; keep prompt and output ids apart.
- [ ] 1.4 The oracle script: match share, acceptance of the first three looked-up tokens, run-length histogram, per workload and per k. Record the tables in `$SCR/c187/steps.txt`.
- [ ] 1.5 Apply D1's stop rule. If it stops here: record the figures in `docs/upstream-prs.md` (`7e6ab2f` to `measured, not needed`), report, archive.

## 2. Step S1: the port (design D2, D3; no GPU)

- [ ] 2.1 Port `7e6ab2f` hunk by hunk onto the child's cycle and field names. Find every reader of the fields it touches with `rg` first.
- [ ] 2.2 Per-source acceptance window; the kill switch; the minimum match length from step 0.
- [ ] 2.3 Decide D3 from the code, and write the decision in the spec delta.
- [ ] 2.4 Model-less tests: the index (match, extend, rewind) and the predictor state after a lookup cycle. The step checks.
- [ ] 2.5 Step review of the whole ported region.

## 3. Model checks (design D4)

- [ ] 3.1 The copy-heavy bench kind: its prompt file under `speed-bench/` and its entry in `ab_bench.py`.
- [ ] 3.2 `tests/model_gates.sh` on Q4 and Q2 with lookup on: every gate `PASS`.
- [ ] 3.3 `ab_bench.py`, lookup off against on, the three kinds. Keep or drop by D4; record tokens per cycle per source, the index's memory and build time.

## 4. Review and closing

- [ ] 4.1 Final pass; remove the kill switch unless the measurement says the gain depends on the workload enough to keep it.
- [ ] 4.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row.
- [ ] 4.3 `docs/upstream-prs.md`: `7e6ab2f` to `adopt -> 187-mtp-prompt-lookup-drafts` with the figures; the MTP doc gains the lookup source.
- [ ] 4.4 `openspec validate 187-mtp-prompt-lookup-drafts --strict` passes.
- [ ] 4.5 Report to the user in Italian, with step 0's histogram and whether D5's follow-up is worth proposing. Land as one signed commit, with the upstream commit's author as `Co-authored-by`; delete `$SCR/c187/`; archive the change (syncs the `mtp-speculation` delta).
