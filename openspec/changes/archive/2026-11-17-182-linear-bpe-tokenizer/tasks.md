# Tasks

GPU: closing guards only (6.2: model gates, parity, one bitwise A/B on Q4). All identity and speed gates run on the CPU and need only the GGUF's vocabulary.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c182/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites, including `test_tokenizer`; the D2 real-vocabulary run,
reading its difference count.

**No tool opens a GGUF before section 6.** `model_open` on the 70 GiB file from
a `-DDS4_NO_GPU` tool, while another Q4 process is resident, froze the Mac three
times (`--export-vocab` on 16 Nov, the key harness twice on 17 Nov). From S2 on,
every identity, key and speed run takes its vocabulary from the text export
`$SCR/c182/qwen.vocab` (Q4; `qwen-q2.vocab` is `cmp`-equal). The reference
worktree is `.claude/worktrees/182-prev`, not `../sf-q3-8flash-prev`.

## 1. Branch and references (no GPU)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/182-linear-bpe-tokenizer`. `git fetch upstream pull/1219/head`; check the head is still `b3f552f`; save the diff to `$SCR/c182/`.
- [x] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it. Port `tests/test_tokenizer.c` (Qwen shape, reference copy) and `tests/tokenizer_vocab.py` first, against `main`'s tokenizer, so the reference is proven equal to `main` before anything changes. Export the vocabulary (design D2) and build the corpus.

## 2. Step S1: BPE core (design D1; no GPU)

- [x] 2.1 Port the id-pair merge table, the heap merge, the byte tables and the (pointer, length) splitter onto `bpe_emit_piece` / `bpe_tokenize_text_qwen35`. Add the load-time merge check.
- [x] 2.2 Run the step checks: zero differences on the corpus. Run D3's bench and record it in `$SCR/c182/steps.txt`.
- [x] 2.3 Step review: the diff and every function it touches; no allocation left in the per-piece path up to 128 bytes.

## 3. Step S2: token bytes (design D1; no GPU)

- [x] 3.1 Decoded-token arena and `ds4_token_bytes()`. Move the server piece emission, the key builders and `ds4_kvstore_render_tokens_text` to it. Find every `ds4_token_text` caller with `rg` first.
- [x] 3.2 Run the step checks, the all-ids detokenization check and the key-text harness (design D2). Record the arena and pair-table sizes and the load time.
- [x] 3.3 Step review.

## 4. Step S3: marker scan (conditional; no GPU)

- [x] 4.1 The first-byte marker table in `tokenize_rendered_chat_vocab`, keeping `special_token_at` for the key builders. Run the step checks.
- [x] 4.2 D3 against S2 on rendered prompts. Keep it by the D3 rule; otherwise restore S2's file and record the figures.

## 5. Review (no GPU)

- [x] 5.1 Final pass over the tokenizer region: delete what the port made dead (`tokenize_span`, the old byte maps), check against AGENT.md, measure refinements like a step.

## 6. Closing (GPU: guards)

- [x] 6.0 Pending from D2, with no other Q4 process resident (stop the sfctl service first): `tests/test_tokenizer <Q4> <corpus...>` on the final code, zero differences. This is the only run that reads the vocabulary through `vocab_load` and exercises the load-time merge check on the shipped file; S1 ran it once, S2 and later did not. Then the same for Q2, or `cmp` a fresh export against `qwen-q2.vocab`. Done 2026-11-17: Q4 `tokenizer tests: ok (3435975 BPE pieces compared)`, Q2 the same count; both shipped files pass the load-time merge check. The GGUF mode of the test now takes the instance lock before `model_open`, so it refuses to run beside a model process (and one refuses beside it).
- [x] 6.1 `make test-qwen4-ngrams`; `python3 tests/test_model_download.py`. Done: both OK.
- [x] 6.1b D3 end to end, not measurable without the server: tokenization time of the 135K-token prompt (`$SCR/c182/corpus/agent135k.txt`), `main` against the branch, from the `DS4_LOG_*` timing line or a trace. The CPU figures are in `$SCR/c182/steps.txt` (`abba_final.txt` for the commit message). Done: no timing line exists, so the figure is the request's wall time for `/v1/completions` with that prompt against the default 32768 context (400 `context_length_exceeded`, 146891 tokens on both builds, no prefill), 15 requests per server, servers A B B A: `main` 100.2 ms, branch 14.2 ms (7.1x).
- [x] 6.2 `tests/model_gates.sh <Q4>`: every gate `PASS`. `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. `ab_bench.py --bitwise` against the current segment's start; append its row with step `perf/182-linear-bpe-tokenizer`. Put D3's figures in the commit message. Done on Q4: model gates all PASS (with the vision fixtures); `PARITY OK` (10 prompts); `--bitwise` against `main`: `PASS (tokens; bitwise)`, 19 pairs, plain decode -0.5% (-2.0..+0.5). The record row is the run against the segment start `91f225a` (token gate, as the earlier rows).
- [x] 6.3 `docs/upstream-prs.md`: `b3f552f` to `adopt -> 182-linear-bpe-tokenizer` with the figures; `142d95b` (#873) and #1027 stay superseded; #942 superseded if the arena covers it. Done: #942 stays open, since the `token_to_id` keys still point into the mapping.
- [x] 6.4 `openspec validate 182-linear-bpe-tokenizer --strict` passes.
- [x] 6.5 Report to the user in Italian. Land as one signed commit, with the PR author as `Co-authored-by`; delete `$SCR/c182/` and `../sf-q3-8flash-prev` if this change created it; archive the change. `../sf-q3-8flash-prev` was never created; the reference worktree `.claude/worktrees/182-prev` is removed at landing.
