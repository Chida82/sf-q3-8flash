# Proposal

## Why

`130` took #1140: with tools, decoding runs on past each `</tool_call>` so one
turn can carry several calls. When the model writes anything after the last
closed call other than `<|im_end|>` (a newline, prose, a cut-off call), the
server drops that text from the reply, but the live KV still holds its
tokens. The client replays the turn as the closed calls followed by
`<|im_end|>`, so the live session no longer prefixes the next request:
- the turn gets no committed end token and no closed-turn key (`160`);
- a results-only continuation finds no live frontier;
- a full replay misses the live session and reloads a disk checkpoint, or
  prefills from scratch.

Before `130`, decoding stopped at the first `</tool_call>` and this could not
happen. `130` added a `DS4_LOG_KVCACHE` line for each such turn ("bytes after
the last closed tool call dropped; no live frontier"). How often it fires on
real agent traffic is unknown: in `130`'s live run it fired once, on a turn
already cut by `max_tokens`, which loses the frontier anyway.

## What Changes

1. **Measure first.** Run `speed-bench/agent_reuse.py` on Q4 with the
   server's KV-cache log, and count the line split by `finish`: only turns
   that end on the model's own stop matter, because a `length` cut loses the
   frontier anyway. If no such turn occurs, the change stops here: record the
   figures and leave the log line as the sentinel.
2. **Restore the frontier at the last closed call.** When a turn's text runs
   past the last closed call, bring the live session back to the token
   position right after that call's `</tool_call>`, then commit `<|im_end|>`
   there as `160` does. The closed-turn keys and the live tool state are then
   exact again. The reply is unchanged: the server already drops that text.
3. Keep the dropped bytes in the log line, and add the rewind cost.

Non-goals:
- no constraint on what the model may sample after a call (it would change
  output);
- no return to one call per turn.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: cache behaviour only; the reply bytes do not change)

## Impact

- `ds4_server.c` (`generate_job_inner` after the decode loop, where
  `calls_cut` is set), possibly a session snapshot helper in `ds4.c`.
- Tests: a server unit test for the frontier bookkeeping. A model-backed
  check that a turn with trailing output still continues from the live KV.
- Depends on `130` and `160` (both on `main`).
