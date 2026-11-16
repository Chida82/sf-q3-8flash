# Proposal

## Why

Every Qwen prompt is tokenized by `bpe_tokenize_text_qwen35` (`ds4.c:24360`),
which splits the text and hands each piece to `bpe_emit_piece`
(`ds4.c:24201`). For every piece that function:
- allocates a byte-encoded copy and one buffer per symbol;
- on every merge round, rebuilds and hashes a string for every adjacent pair.

The merge loop is quadratic in the piece length. Detokenization is a malloc
plus a UTF-8 decode per token (`ds4_token_text`). The server calls it for
every generated piece, for every key text (`ds4_tokens_key_text`, `131`), and
for every disk checkpoint it renders (`ds4_kvstore_render_tokens_text`).

#1219 (`b3f552f`, one commit, `ds4.c` +344/-229, plus an 816-line test)
replaces this:
- merges resolve at load to (left id, right id) -> (rank, merged id);
- a piece merges through a candidate heap over a linked symbol array, with no
  allocation up to 128 bytes;
- the GPT-2 byte maps become closed forms, and pre-tokenizers take
  (pointer, length) instead of copies;
- every token's text is decoded once at load into an arena, and
  `ds4_token_bytes()` returns a zero-copy view.

The author's figures (not reproduced here):
- 3-11 -> 15-53 MB/s on ordinary text;
- a 135K-token rendered prompt from tens of ms to about 5 ms;
- an unbroken 20,000-character run (base64, hex, spaceless CJK) from 1.4 s to
  1 ms.

Output is claimed bit-identical: the PR's `tests/test_tokenizer` runs the new
code against a verbatim copy of the old one, with 4.29 M pieces per
vocabulary and zero differences. The quadratic case is what agent workloads
hit: a tool result with a base64 blob or a minified file stalls the request
before prefill starts. Performance under the intake criteria.

The path is reachable: the child's `bpe_tokenize_text` calls only the Qwen
splitter, and that splitter emits every piece through `bpe_emit_piece`.

## What Changes

- Port `b3f552f` onto the child's tokenizer, Qwen only. The PR's GLM and
  DeepSeek pre-tokenizer hunks have no target here (removed by `100`/`101`).
- Keep the child's own marker and key machinery from `131`:
  `special_token_at`, used by `ds4_tokens_key_text`, and the masked
  rendering. The PR replaces `special_token_at` with an inline marker scan.
  The child takes that scan only if it measures a gain (design D1, step S3).
- Add `ds4_token_bytes()` and move the hot detokenization callers to it
  (server piece emission, key text, kvstore render). The remaining
  `ds4_token_text` callers (CLI, bench, eval, tests) keep the allocating API.
- Port `tests/test_tokenizer.c` restricted to the Qwen shape, with its
  reference copy of the old implementation, plus `tests/tokenizer_vocab.py`.
  Add it to `make test` with the synthetic vocabulary. The real-vocabulary
  run is a gate, not part of `make test`, since it needs the GGUF.
- The load-time check that rejects a merge producing a piece missing from the
  vocabulary comes with the port. It must accept the shipped Q2 and Q4 GGUFs.

Token ids must not change for any input. Model output, KV checkpoints and
cache keys are therefore unchanged, by construction and by the gates.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: tokenizer speed only; token ids and token bytes are identical)

## Impact

- `ds4.c` (vocabulary load, BPE, byte maps, Qwen splitter signature, token
  text arena), `ds4.h` (`ds4_token_bytes`), `ds4_server.c` and
  `ds4_kvstore.c` (detokenization callers), `Makefile` (test target),
  `tests/test_tokenizer.c`, `tests/tokenizer_vocab.py`.
- Supersedes #873 (`142d95b`) and #1027, which fix only the quadratic merge.
- Overlaps #942 (detach tokenizer storage from the model mmap): the arena
  already copies token text out of the mapping. Record #942 as superseded if
  the arena covers it.
- `docs/upstream-prs.md`.
