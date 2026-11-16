# Tasks

GPU: closing guards only (6.2: model gates, parity, one bitwise A/B on Q4). All identity and speed gates run on the CPU and need only the GGUF's vocabulary.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c182/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites, including `test_tokenizer`; the D2 real-vocabulary run,
reading its difference count.

## 1. Branch and references (no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/182-linear-bpe-tokenizer`. `git fetch upstream pull/1219/head`; check the head is still `b3f552f`; save the diff to `$SCR/c182/`.
- [ ] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it. Port `tests/test_tokenizer.c` (Qwen shape, reference copy) and `tests/tokenizer_vocab.py` first, against `main`'s tokenizer, so the reference is proven equal to `main` before anything changes. Export the vocabulary (design D2) and build the corpus.

## 2. Step S1: BPE core (design D1; no GPU)

- [ ] 2.1 Port the id-pair merge table, the heap merge, the byte tables and the (pointer, length) splitter onto `bpe_emit_piece` / `bpe_tokenize_text_qwen35`. Add the load-time merge check.
- [ ] 2.2 Run the step checks: zero differences on the corpus. Run D3's bench and record it in `$SCR/c182/steps.txt`.
- [ ] 2.3 Step review: the diff and every function it touches; no allocation left in the per-piece path up to 128 bytes.

## 3. Step S2: token bytes (design D1; no GPU)

- [ ] 3.1 Decoded-token arena and `ds4_token_bytes()`. Move the server piece emission, the key builders and `ds4_kvstore_render_tokens_text` to it. Find every `ds4_token_text` caller with `rg` first.
- [ ] 3.2 Run the step checks, the all-ids detokenization check and the key-text harness (design D2). Record the arena and pair-table sizes and the load time.
- [ ] 3.3 Step review.

## 4. Step S3: marker scan (conditional; no GPU)

- [ ] 4.1 The first-byte marker table in `tokenize_rendered_chat_vocab`, keeping `special_token_at` for the key builders. Run the step checks.
- [ ] 4.2 D3 against S2 on rendered prompts. Keep it by the D3 rule; otherwise restore S2's file and record the figures.

## 5. Review (no GPU)

- [ ] 5.1 Final pass over the tokenizer region: delete what the port made dead (`tokenize_span`, the old byte maps), check against AGENT.md, measure refinements like a step.

## 6. Closing (GPU: guards)

- [ ] 6.1 `make test-qwen4-ngrams`; `python3 tests/test_model_download.py`.
- [ ] 6.2 `tests/model_gates.sh <Q4>`: every gate `PASS`. `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. `ab_bench.py --bitwise` against the current segment's start; append its row with step `perf/182-linear-bpe-tokenizer`. Put D3's figures in the commit message.
- [ ] 6.3 `docs/upstream-prs.md`: `b3f552f` to `adopt -> 182-linear-bpe-tokenizer` with the figures; `142d95b` (#873) and #1027 stay superseded; #942 superseded if the arena covers it.
- [ ] 6.4 `openspec validate 182-linear-bpe-tokenizer --strict` passes.
- [ ] 6.5 Report to the user in Italian. Land as one signed commit, with the PR author as `Co-authored-by`; delete `$SCR/c182/` and `../sf-q3-8flash-prev` if this change created it; archive the change.
