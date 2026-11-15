# Design

## Context

Thirteen open PRs, 1 to 6 commits each, all in `ds4_server.c` and its tests,
except #1284's mask plumbing in `ds4.c` and the kvstore. Every PR was written
for upstream's multi-model server. Its GLM, DSML and DeepSeek V4.1 parts touch
renderers this child deleted, so they drop out. The child's
`server_model_syntax` has one value, `SERVER_MODEL_SYNTAX_QWEN`, so any new
predicate that tests the syntax collapses (StarForge rule 17).

## Decisions

### D1. Triage reasons

- **#1288 (+#1284): take, Qwen parts.** Message data can carry
  `<|im_start|>`, `<|im_end|>`, `<think>` or `<tool_call>` spellings. The
  rendered-chat tokenizer promotes them to control tokens, so a client, or a
  document a client pastes, can inject structure the model never sampled. That
  is a trust-boundary defect, and AGENTS.md forbids weakening validation there.
  - Taken: `def0f60`, `138cb39`, `e66797e`, `6ee4a73`, `0252371`.
  - Dropped: `aa982ec` (GLM), and #1284's V4.1 renderer part.
  - `92`'s port of #1115 chose to trace these spellings, so as not to break
    parity with the reference Jinja templates (which do not mask) and not to
    invalidate KV checkpoints. Masking breaks that parity for exactly the
    requests that carry the spellings. Recommendation: take the mask, keep
    `92`'s trace section to report what was masked, and record the trade in
    `docs/SERVER.md`. **Open for the owner** (task 1.3).
- **#1140 + #1251, #1134, #1088, #1163, #1157, #1155, #1175:** take.
  Each fixes a wrong answer, a lost answer, a wrong protocol state or a wrong
  cache decision for Qwen requests. #1140 and #1251 touch the same tool-call
  parser and stream translator, so they land as one step.
- **#1226 over #815 (D3).**
- **#1131, #1161, #1162:** take. Small protocol corrections; each has a unit
  test.

### D2. Order

Each step runs `./ds4_test --server` and keeps it passing:

1. #1284 base and #1288's Qwen mask, since later renderer edits must keep the
   mask;
2. #1134;
3. (#1325 dropped: `160`'s #1169 owns the end-of-turn boundary);
4. #1088;
5. #1163;
6. #1140 + #1251;
7. #1157;
8. #1155;
9. #1175;
10. #1226;
11. #1131;
12. #1161;
13. #1162.

Renderer first, then parsers and recovery, then cache tiers, then output
encoding and fields.

### D3. UTF-8: #1226, not #815

- #815 drops a partial trailing UTF-8 sequence from finished text only.
- #1226 replaces any invalid sequence with U+FFFD in every JSON escaper.

They overlap on the length-cut case, where #815 drops the partial character
and #1226 emits one U+FFFD. Recommendation: take #1226. It guarantees valid
JSON on every path, not only on finished text, and adding #815 on top would
make the same case behave two ways. The child already holds a trailing
incomplete character back in SSE deltas (`ds4_server.c:1298`), so the
visible difference is limited to the final text of a length-cut answer.
**Open for the owner**, if dropping is preferred to U+FFFD.

### D4. Checks

- **Each step:** `make -j8` with no warnings; `./ds4_test --server`, reading
  the names of the new unit tests in its output; `make test -j8` after the
  last step.
- **Protocol coverage** (AGENTS.md: server changes preserve the OpenAI,
  Responses, Anthropic and completions endpoints, exact tool-call
  continuation and disk-KV validation):
  - one live request per endpoint against `sf-q3-8flash-server` on Q4,
    covering a two-tool-call turn (OpenAI, streamed and not), an Anthropic
    stop sequence, a Responses `max_output_tokens` cut, and an injected
    `<|im_end|>` in user text;
  - `DS4_TEST_MODEL=<Q4> ./ds4_test --tool-call-quality`;
  - `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>` for disk-KV
    validation after #1175 and #1157.
- **Guards:** parity and `ab_bench.py --bitwise` against `main`. No record
  row.

## Risks / Trade-offs

- **Reachability was inferred from hunks.** A PR whose Qwen path turns out
  not to exist in the child is dropped at task 1.2, with its reason in the
  registry.
- **Masking changes prompts** that today reach the model unmasked. A client
  that relied on injecting markers on purpose (for example to replay raw
  transcripts) now sees them as text. `92`'s in-content reasoning extraction
  covers the legitimate replay case.
- **Thirteen ports in one change is a large diff.** Each step is reviewed on
  its own (config: per-step review), and a step that cannot be made to pass
  `./ds4_test --server` is dropped from the batch, not forced.
