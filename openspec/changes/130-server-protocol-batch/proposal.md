# Proposal

## Why

The 2026-11-13 review lists open server PRs that reach this child's Qwen
server and are not in `upstream/main`. They fix:
- prompt injection through chat content;
- turns that stop after one tool call;
- lost answers, and HTTP 200 responses with `finish_reason: "error"`;
- a ChatML cold-cache anchor that is never found;
- invalid UTF-8 in JSON output;
- seeds rounded through a double;
- missing protocol fields.

Agents reach the model through `sf-q3-8flash-server` (`docs/CLIENTS.md`), so
these defects hit the child's main use. No sync brings them.

Reachability came from hunk function names, Qwen/GLM/DeepSeek mentions on
changed lines and the PR bodies. It was **not traced call by call**. Two
claims were checked in the source on 2026-11-14:
- #1157: the Qwen vocabulary sets `user_id`/`assistant_id` to -1
  (`ds4.c:29724`);
- #1131: `seed` is parsed into a double (`ds4_server.c:3426`).

The other claims are open until task 1.2 checks them.

## What Changes

Triage (design D1 gives the reasons):

| PR | Verdict | What |
|---|---|---|
| #1288 + #1284 base | moved to `131-trusted-marker-masking` | owner decision D1 = C (2026-11-14): masking with trust-aware cache keys is its own change |
| #1325 | drop (owner 2026-11-15: `160` takes #1169's end-of-turn policy) | evaluate Qwen's `<\|im_end\|>` after a thinking answer, so the next live turn does not see an unclosed answer |
| #1140 | take | several Qwen tool calls per turn; drop the GLM parts |
| #1251 | take, with #1140 | stream Qwen tool-call arguments over OpenAI SSE; drop the DSML/GLM parts |
| #1134 | take | keep mid-conversation system messages in place (reported 14.8K-token re-prefill -> 17 tokens) |
| #1088 | take | recover an unterminated reasoning block as content when the turn completed |
| #1163 | take | an unterminated tool call goes to parse-failure recovery instead of `finish_reason: "error"` |
| #1157 | take | find the cold KV anchor in ChatML prompts |
| #1155 | take (3 commits, fixup squashed) | prefill progress against the full prompt; detached backend state is a live cache miss |
| #1175 | take | validate the parent history before live tool KV reuse; keep user follow-ups in Responses tool continuations |
| #1226 | take | invalid UTF-8 becomes U+FFFD in every JSON escaper |
| #815 | idea (covered by #1226) | dropping a partial trailing sequence instead; design D3 |
| #1131 | take | integer seeds without rounding through a double |
| #1161 | take | Anthropic `stop_sequence` when a client stop matches |
| #1162 | take | Responses `incomplete_details.reason = max_output_tokens` |

Out of this batch: KV-reuse PRs (`160-agent-kv-reuse`); #1137, #1139, #1304
and #1309 (`open` in the registry, separate features or limits).

Each PR is ported by hand onto the tree after `90` and `92`, in the order of
design D2, with its own unit tests in `./ds4_test --server`.

## Capabilities

### New Capabilities
- `server-protocol`: what the Qwen server guarantees to API clients for tool
  calls, reasoning recovery, control-token injection, cache-reuse validity,
  JSON text and protocol fields.

### Modified Capabilities
(none)

## Impact

- `ds4_server.c` (renderers, parsers, live-session tiers, stream writers),
  `ds4.c` and `ds4_kvstore.*` (the #1284 mask plumbing), `tests/ds4_test.c`,
  `docs/SERVER.md`, `docs/CLIENTS.md` where client behaviour changes,
  `docs/upstream-prs.md`.
- Prompt bytes change for requests that carry control-token spellings in
  message data (#1288), mid-conversation system messages (#1134), and the
  Qwen thinking-answer close (#1325). For those conversations the first
  request after the upgrade misses the KV cache once.
- No engine arithmetic changes. The CLI and the bench do not use the server
  renderer, so parity and the A/B token gate are guards.
- Depends on `90` (`ds4_server.c` conflicts; `a8ce74a` blank-reasoning parsing
  arrives with it) and on `92` (same renderer).
