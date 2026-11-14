# Design

## Context

`f5e419d` is 1,902 diff lines. About 500 are renderer, parser and trace code
in `ds4_server.c`; the rest are tests and docs. The commit message reports a
real 167K-token replay request rendering byte-identical to the pre-change
render, and a passing live retention run (1279 of 1281 tokens reused live,
1281 of 1281 after a restart). Neither result was reproduced here. The changed
hunks of existing server unit tests only add the new `preserve` argument;
none changes an expected render. That supports the claim that default
requests keep their bytes, but does not prove it.

## Decisions

### D1. A render corpus decides "unchanged except the listed classes"

Step 1 ports only the `ds4_test --qwen-render EFFORT PRESERVE MESSAGES.json
[TOOLS.json]` entry. Its render call is `render_chat_prompt_text_for_syntax`,
and `PRESERVE` is ignored until step 2. A corpus of request bodies goes in
`$SCR/c92/corpus/`:
- the synthetic scenarios of `tests/template_parity_ab.py`, transcribed;
- the fixtures of the Qwen server unit tests (plain, thinking, tool loop,
  tool schemas, multi-turn);
- one case per changed class: an escaped tool schema, `content` starting with
  `<think>`, `preserve_thinking=false`, and each effort alias.

Rendered before and after the port, every case outside the four classes must
be byte-identical, and every case inside them must differ only where the class
says. The corpus stays in the scratch dir. Only `--qwen-render` lands, as the
tool a later renderer change reuses.

### D2. What is ported, what is not

- **Ported:**
  - `preserve_thinking`/`preserve_reasoning` parsing;
  - `qwen_last_query_index` and the retention window;
  - `qwen_assistant_text_load`;
  - `json_recode_value` and its helpers;
  - the effort aliases;
  - `note_client_control_tokens` and the trace section;
  - the new unit tests, with `c544020`'s retention test.
- **Dropped:** every GLM/DeepSeek renderer branch. The
  `render_chat_prompt_text_preserving` dispatcher collapses to the Qwen call,
  since `server_model_syntax` has one value here.
- **Kept despite its name:** `append_glm_tool_schema_json`. The Qwen tools
  prompt calls it, and `f5e419d` changes its non-string branch, so the Qwen
  render depends on that edit.

### D3. `tests/template_parity_ab.py` stays out

It needs `jinja2` and two template files (the shipped one and the
"froggeric" fixed template from Hugging Face). Neither is in the child, and a
test that cannot run on the owner's machine without extra installs is not
a gate. D1's corpus check covers the same invariant against the child's own
previous renderer. If the owner wants the Jinja comparison as one-off
evidence, run it in a `mktemp` venv with `jinja2` installed there, then delete
the venv. That needs no machine change, but it downloads the template files.

### D4. Tracing, not masking, until `130`

`f5e419d` deliberately leaves control-token spellings in client text alone:
rewriting them would break parity with the reference templates and invalidate
KV checkpoints. `130`'s #1288 masks them, as a prompt-injection fix. This
change ports the trace as written. `130` then decides the masking, and the
trace section reports what was masked. A requirement here that the bytes stay
unrewritten would contradict `130`, so the spec delta does not state one.

## Risks / Trade-offs

- **Conversations that hit a changed class lose their KV checkpoint once** →
  this is intended. The commit message and `docs/SERVER.md` say so, and the
  release note in the commit message names the classes.
- **The retention window depends on finding the last real user query.** Tool
  outputs sent as user messages carrying call ids must not close it.
  `chat_msg_is_glm_tool_result` decides this (another `glm_` name used by the
  Qwen path), and the ported unit tests cover it.
- **The live retention test takes several minutes and restarts the server
  once.** Run it last, alone, on Q4.

## Open Questions

None left from reading. `minimal` already maps to `low` in the child
(`parse_reasoning_effort_name`, `ds4_server.c:1040`), so the PR's doc sentence
on `minimal` describes existing behaviour and is ported as is.
