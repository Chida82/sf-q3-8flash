# Design

## Context

The server keeps reuse keys as text. A key stored after a turn says: "the KV
at this frontier holds the prompt whose rendering starts with these bytes".
The next request hits only if its rendered prompt starts with the key. For
Qwen, the renderer `append_qwen_assistant_message` (`ds4_server.c`) writes an
echoed assistant turn as:

    <|im_start|>assistant\n [<think>\n reasoning \n</think>\n\n] body [tool calls] <|im_end|>\n

`body` is the content with leading whitespace trimmed. Since `92`, a plain
answer (no tool calls) keeps its trailing whitespace, because the sampled
tokens include it and the echoed turn must re-tokenize to them.

Three builders predict that rendering when a turn ends, and all trim both ends
of the content:

| Builder | Key it feeds | Callers |
|---|---|---|
| `build_qwen_assistant_suffix` | Responses-visible live and disk key, tool checkpoint, tool-turn visible key | `build_responses_visible_assistant_suffix`, `build_tool_checkpoint_suffix`, `build_qwen_tool_turn_visible_text` |
| `build_thinking_visible_text` | thinking live key (clients that omit reasoning) | `remember_thinking_checkpoint` |

With tool calls the renderer trims both ends too, so only plain answers that
end in whitespace diverge. That is a common shape: Qwen answers often end in a
newline after a code block or a list.

## Decisions

### D1. One body writer, used by the renderer and by the builders

Add `append_qwen_answer_body(buf *out, const char *content, bool has_calls)`,
which returns whether the body is non-empty. It contains the renderer's
current rule (trim leading; trim trailing only when `has_calls`).
`append_qwen_assistant_message` and both builders call it in place of their
own trimming. The renderer's bytes do not change, so prompts, parity and the
`92` render corpus stay byte-identical. Only the stored keys change, and only
for plain answers ending in whitespace.

Alternative rejected: trimming in the renderer again. That would undo `92`'s
fix: the echoed turn would re-tokenize differently from the sampled tokens,
and the live KV would stop matching the prompt.

Alternative rejected: fixing each builder separately. Two copies of one rule
are how this bug happened.

### D2. The invariant is the test

`./ds4_test --server` gains a test that, for each answer shape × tool calls on/off ×
think on/off × API (chat, Responses), builds request N, stores the key the
builder would store, appends the assistant message to the history, renders
request N+1 and asserts that the key is a byte prefix of that rendering (in
`131`'s key space, so the mask is compared too). This is the property every
visible tier depends on. It covers future edits to either side.

### D3. The workload confirms the hit and guards the rest

`speed-bench/agent_reuse.py` on `main` and on the fix, twice each:
- responses byte-identical between builds and run to run;
- no request's cached tokens lower on the fix;
- the shape that missed now hits.

The clean workload may not produce an answer ending in `\n`. If it does not,
the variant `131` used (10 characters of A's first tool-result slice
overwritten with `<|im_end|>`, same length) does. Rebuild that variant if the
scratch file is gone. Failing that, add a scripted Responses turn whose
answer the model reliably ends with a newline (for example, an answer that
ends in a fenced code block).

## Risks / Trade-offs

- **A key that now matches must also be correct.** The key is only as good
  as the claim that the KV holds those tokens. For a plain answer the sampled
  tokens include the trailing whitespace, which is `92`'s premise. The
  checkpoint replay test (`tests/test_qwen4_checkpoint_replay.py`) and the
  workload's byte-identical responses are the guards.
- **`build_thinking_visible_text` also appends `<|im_end|>\n` to a key whose
  KV did not evaluate `<|im_end|>`.** That is the end-of-turn question `160`
  settles with #1169. This change leaves it alone and must not make it worse:
  D2's test asserts only the body bytes before the end-of-turn marker for the
  thinking key.
