# Proposal

## Why

`131`'s cache-reuse run found a miss that has nothing to do with masking and is
already on `main`. Conversation A's Responses answer `a.resp3` ended in `\n`.
The next request, `a.return1`, should have loaded the Responses-visible disk
checkpoint stored after `a.resp3`. It missed: the stored key matched the
request for 142,381 bytes and diverged at that trailing newline.

The cause is two rules for the same bytes:

- `92`'s renderer (`append_qwen_assistant_message`) keeps a plain answer's
  trailing whitespace, so an echoed turn re-tokenizes to the tokens the model
  sampled.
- The key builders that predict that rendering trim it:
  `build_qwen_assistant_suffix` (Responses-visible key, tool checkpoints,
  tool-turn visible key) and `build_thinking_visible_text` (thinking live
  key) call `append_trimmed_text` on the content.

So every plain answer that ends in whitespace stores a key that the next
prompt can never match. The live and disk checkpoints are written, and they
are never used. The client then pays a full re-prefill of the conversation;
in the `131` run that was the 142K-byte A conversation.

## What Changes

- One helper writes a Qwen assistant answer body, with leading whitespace
  trimmed always and trailing whitespace kept for a plain answer (no tool
  calls). The renderer and every key builder call it, so the rule lives in
  one place and cannot drift again.
- A unit test pins the invariant the keys rely on: for each answer shape
  (trailing `\n`, `\n\n`, spaces, none; with and without tool calls; think on
  and off), the key a builder stores is a byte prefix of the next request's
  rendered prompt.
- The agent workload (`speed-bench/agent_reuse.py`) shows the
  `a.return1`-shaped request hitting, and no other request losing cached
  tokens.

Not in scope: where `<|im_end|>` sits relative to the KV (the #1169/#1325
end-of-turn question, decided for `160`), and leading whitespace, which the
renderer and the builders already trim the same way.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `server-protocol`: a requirement that a stored visible key is a prefix of
  the prompt the next turn renders.

## Impact

- `ds4_server.c` (renderer and key builders), `tests/ds4_test.c` (`--server`
  unit test), `docs/SERVER.md` if it states the key rule.
- No change to the prompt bytes the model sees, to the CLI or to the bench:
  parity is a guard.
- Keys stored before the fix for answers ending in whitespace never matched
  anything, so nothing that used to hit can miss.
- Lands before `160`: `160`'s #1169 and #1206 rewrite the same builders, and
  should start from the corrected rule.
