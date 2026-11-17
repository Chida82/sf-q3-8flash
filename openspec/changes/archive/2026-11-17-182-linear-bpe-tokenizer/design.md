# Design

## Context

The PR is against upstream's four-family `ds4.c` (hunks at line 40808 and
later); the child's tokenizer sits around line 24200 of a 38205-line `ds4.c`
and has one splitter. The port is a rewrite of the same algorithm onto the child's
functions, not a cherry-pick. Since `131`, the child's key builders
(`ds4_tokens_key_text`, `ds4_chat_key_text`) call `ds4_token_text` and
`special_token_at`. Key bytes must not change, or every disk checkpoint key
written before the upgrade stops matching.

## Decisions

### D1. Three steps, each gated on identity

1. **S1, BPE core:**
   - the id-pair merge table built at load;
   - the heap merge over a linked symbol array;
   - the 256-entry byte -> initial-token table and the closed-form byte maps;
   - the (pointer, length) splitter, which removes `tokenize_span`'s copy.

   This is the asymptotic fix and most of the speed.
2. **S2, token bytes:** the decoded-token arena and `ds4_token_bytes()`. Move
   the per-token callers that run on every request to the view: generated
   pieces in `generate_job_inner`, the key builders and
   `ds4_kvstore_render_tokens_text`. `ds4_token_text` stays as a thin copy
   over the arena for the rest.
3. **S3, marker scan (conditional):** the PR's first-byte table in
   `tokenize_rendered_chat_vocab`, written so that `special_token_at` stays
   for the key builders. It is kept only if D3 shows a gain on rendered
   prompts. Otherwise it is dropped, since it adds lines.

### D2. Identity gates (CPU, no GPU)

- `tests/test_tokenizer` on its synthetic vocabulary, in `make test`.
- Real vocabulary: `tests/test_tokenizer --export-vocab <Q4> $SCR/c182/qwen.vocab`,
  once. The export reads GGUF metadata only, on the CPU. Then
  `tests/test_tokenizer $SCR/c182/qwen.vocab <corpus...>`: zero differences
  between the new code and the reference copy. The corpus:
  - the repository's sources and docs;
  - `speed-bench/promessi_sposi.txt` and the harness prompts;
  - `rax.c`;
  - a 20,000-character base64 blob, a hex dump and a spaceless CJK run;
  - every `tests/vision-fixtures` README;
  - the rendered prompts of `tests/test_qwen4_checkpoint_replay.py`'s
    conversations, dumped with `--dump-tokens`.
- Detokenization: for every id in the vocabulary, `ds4_token_bytes` equals
  the old `ds4_token_text` bytes.
- Keys: a scratch harness renders the key text of a set of transcripts
  (tool calls, masked marker spellings from `131`, images) on `main` and on
  the branch, byte-identical.
- `make test-qwen4-ngrams` (the n-gram table is indexed by token ids).
- The Q2 GGUF's vocabulary equals Q4's; check it once with `cmp` on the
  export, then the load-time merge check is covered for both.

### D3. Speed (CPU)

`tests/test_tokenizer --bench <vocab> --shape qwen4 <files>`, new against
reference, ABBA, 10 pairs:
- `promessi_sposi.txt`;
- a 135K-token rendered agent prompt;
- the base64 blob.

Then end to end: the server's tokenization time for the 135K-token prompt,
from the `DS4_LOG_*` timing line or a trace, `main` against the branch. The
step is kept if tokenization time drops with a pooled CI wholly below zero on
one input and above zero on none. S3 is judged alone, against S2.

### D4. GPU guards

Token ids are identical, so model output is identical by construction. The
change still touches vocabulary load and every request's prompt path, so once
at the end:
- `tests/model_gates.sh` on Q4;
- `tools/parity-check.sh`;
- one `ab_bench.py --bitwise` run against the segment start, for the
  performance record.

The harness's prompts are short, so its rows are not expected to resolve the
gain. D3's figures go in the commit message.

## Risks / Trade-offs

- **Memory:** the arena holds every token's decoded bytes and the pair table
  one entry per merge (both a few MB at Qwen's vocabulary size). Record both sizes; they are
  negligible next to the model, but they are new resident memory.
- **Load time:** building the tables adds work at engine open. Measure it in
  D3; a regression above 50 ms is reported to the owner.
- **The new load-time rejection** turns a malformed GGUF vocabulary into an
  open failure. That is a stricter trust boundary, wanted, but it must accept
  the shipped files (D2).
