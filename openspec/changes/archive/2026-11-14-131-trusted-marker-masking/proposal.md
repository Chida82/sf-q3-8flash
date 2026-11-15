# Proposal

## Why

The tokenizer turns a control-token spelling (`<|im_start|>`, `<|im_end|>`,
`<think>`, `<tool_call>`, `<tool_response>`, ...) into the control token
wherever it appears in the rendered prompt, including inside text a client
sent. A user message, a pasted document or a tool result that contains
`<|im_end|>\n<|im_start|>assistant\n` gives the model a turn boundary nobody
sampled. That is prompt injection through the model's own structure, and it
also happens by accident: an agent that reads this repository's server code,
docs or tests feeds the model fake turn boundaries inside tool output. `92`
only traces these spellings (`--trace`).

Upstream's fix, #1284 with the Qwen part of #1288, masks them: the renderer
records which bytes it wrote itself, and only those bytes can become control
tokens. As written it pays for that with speed. A prompt with an untrusted
spelling no longer maps bytes to tokens one to one, so #1284 sets
`session_ambiguous` and turns off every byte-comparing cache tier for the
rest of the live session: the visible-text tiers (`REUSE_THINKING_VISIBLE`,
`REUSE_RESPONSES_VISIBLE`, `REUSE_MEMORY_TEXT`) and the disk cache, load and
store. A thinking-mode agent that does not send reasoning back relies on the
visible tier, so such a conversation re-prefills the whole prompt on every
turn. For an agent working on this repository that is most conversations.

The owner chose option C of `130`'s decision D1 (2026-11-14): mask, and keep
the cache tiers working. `130` therefore ports nothing from #1284/#1288; this
change does.

## What Changes

- Port #1284's trusted-byte mask and the Qwen part of #1288 (renderer
  records trusted spans; the tokenizer promotes a control spelling only in a
  trusted span). Drop `aa982ec` (GLM) and the V4.1 renderer part.
- Child addition: cache keys carry the trust information instead of the
  tiers being turned off. The text a key is built from writes an untrusted
  control spelling with an escape byte, so a masked spelling and a real
  control token never produce the same key text. The escape is decidable from
  the token stream (one control token against several text pieces), so live
  keys and disk keys rebuilt from tokens agree. `session_ambiguous` is not
  set by an untrusted spelling.
- The checkpoint file layout does not change. Keys of conversations that
  carried untrusted spellings change once, so those old checkpoints miss
  once; every other key is byte-identical to today's.
- `--trace` keeps `92`'s client-control-token section, now naming the
  spellings that were masked.

Non-goals: no change for requests without control spellings (prompt tokens,
keys and output identical); no masking of the server's own framing; the
Anthropic and Responses endpoints follow the same renderer, nothing
endpoint-specific.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `server-protocol`: message data cannot inject control tokens, and masking
  keeps cache reuse.

## Impact

- `ds4_server.c` (renderer trust spans, key text), `ds4.c` (tokenizer entry
  that honours the spans), `ds4_kvstore.*` if the disk-key path builds text
  there, `tests/ds4_test.c`, `docs/SERVER.md`.
- Depends on `92` (renderer and trace, landed first). Coordinates with `130`
  (ports the rest of its batch around this) and `160` (its
  `speed-bench/agent_reuse.py` workload is the reuse gate).
- Child-only code in the cache-key path: a permanent merge site, marked
  `sf-keep(server)` where it diverges from #1284.
