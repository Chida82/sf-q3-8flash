# Design

## Context

`130` set the child's tool-call rules:
- #1140: several `<tool_call>` blocks per turn. Decoding stops at the end
  token or at non-call text, which is cut together with the turn's live
  frontier.
- Each streamed call is sent whole when its `</tool_call>` arrives.
- #1088: a turn that ends with its stop token before `</think>` and has no
  calls promotes its reasoning to content.
- #1163: a streamed unterminated call defers to the parse-failure recovery.

`160` evaluates `<|im_end|>` into the live KV after tool-call and stop turns.

The tracker (`dsml_decode_tracker`) has explicit states:
- `STRUCTURAL`, `STRING_BODY` and `JSON_PARAM` inside a call;
- `BETWEEN` after a `</tool_call>`, where another call may follow;
- `DONE` after non-call text.

`dsml_tracker.decode != DSML_DECODE_OUTSIDE` exactly when the tracker is
inside a call. Inside reasoning the tracker is reset, so it is outside.

## Decisions

### D1. "Open call" is the tracker's state, per token

Upstream's predicate, `saw_tool_start && !saw_tool_end`, is wrong for this
child. After the first call closes, the tracker is in `BETWEEN`: `saw_tool_end`
is still false (it turns true only at `DONE`), yet a stop token there is the
legitimate end of a turn with closed calls. Upstream's predicate would suppress
it, up to 24 times, and decode past the turn's end. The child uses
`dsml_decode_state_is_tool(dsml_tracker.decode)` with `!thinking.inside`.

- **Sampled token:** the predicate is read before sampling, as the loop
  already does for `in_tool_call`.
- **Drafted tokens:** the predicate is read at each `ti`, from the tracker
  after the previous piece. A block that drafts `</tool_call>` and then a stop
  token keeps the stop, while upstream's once-per-block predicate would
  resample it.

The decision is one helper, `tool_call_stop_override(in_call, thinking,
suppressed)`, so a unit test can pin it.

### D2. Take #997's structural advance with it

With the tracker parked on a stray byte (for example a Hermes-style
`{"name": ...}` inside `<tool_call>`), the call never closes in the tracker's
view. D1 would then suppress every stop token of the turn, up to the bound,
and the turn would keep greedy sampling to the end. #997's fix ends the
structural loop with `dt->pos++` instead of `return`.
- Its byte-by-byte prefix tests, rewritten for Qwen's syntax, go into the
  `--server` group.
- Its differential reference recognizer is not taken: it is test-only code for
  a syntax the child no longer has.
- Its lone-`<` fix is already in the child (`ds4_server.c:6886`, "Keep even a
  lone '<'"), so it is not ported.

### D3. Forced token: argmax, as upstream

Inside a call's structure the loop already samples greedily
(`greedy_tool_syntax`), so argmax is what would have been chosen without the
stop token. Inside a string body, argmax replaces a sample.

Rejected alternative: sampling from the distribution renormalized without the
stop tokens. It is the faithful conditional, but it needs a new sampler entry
point for a state that is already invalid, and the bound keeps it short.

### D4. "No precision loss"

The owner's rule (`no-precision-loss`) rejects performance routes that change
greedy output or the sampled distribution of valid generations. This change is
not such a route:
- it acts only after the model has selected a stop token inside an unclosed
  call;
- today that output is discarded: it becomes a tool-error continuation, raw
  text, or an error;
- every generation that does not reach that state decodes bitwise as before,
  because the helper returns "no override" and nothing else changes.

The guard proves the last point: `ab_bench.py --bitwise` and the MTP identity
gates, which never enter a tool call, must pass unchanged.

### D5. Fallbacks after the bound

After 24 suppressions the stop is accepted and today's paths run unchanged:
- non-streamed: the tool-error continuation;
- streamed: #1163's parse-failure recovery.

#1088 is unaffected, since reasoning is never "inside a call". `160`'s end
token follows the turn's real end: either `</tool_call>` and then a stop
token in `BETWEEN`, or the accepted stop after the bound.

### D6. Proof

- **Model-less:** `./ds4_test --server`. It names the helper test and the
  stray-byte tracker tests. Each fix is reverted alone once, to see its test
  fail.
- **Live, Q4, scratch-only fault injection:** a throwaway patch, never
  committed, replaces the first sampled token after `<function=` with
  `<|im_end|>` once per turn. With it:
  - an OpenAI streamed request, a non-streamed one and an Anthropic stream,
    each with tools, at `--mtp` and without, return the call closed and whole
    with `finish_reason: "tool_calls"`;
  - the log shows one suppression warning per turn.

  A second throwaway variant injects the stop 30 times; it must end in
  today's fallbacks (D5).
- **Guards:** `DS4_TEST_MODEL=<Q4> ./ds4_test --tool-call-quality`;
  `tests/model_gates.sh` on Q4; `ab_bench.py --bitwise` against `main`;
  parity.

## Risks / Trade-offs

- **A model that wants to stop may produce a forced, odd closing.** The bound
  limits it to 24 tokens. The result is still parsed by the final parser and
  can fail there, which is today's outcome.
- **Taking #997 changes the sampling mode** (greedy or payload) for calls
  whose structure has stray bytes after the stray byte. That is the fix: such
  calls were held greedy to the end of the turn.
