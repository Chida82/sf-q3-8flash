# Proposal

## Why

#1115's second commit, `f5e419d` ("server: render Qwen prompts the way the
fixed template does"), was marked `next sync` on 2026-09-24. It never landed
upstream: no patch or subject match in `fc80bd6..upstream/main`, and upstream
has neither `tests/test_qwen4_reasoning_retention.py` nor
`tests/template_parity_ab.py`. The sync to b3f5018 (`90`) therefore does not
bring it, and `90` lists it as a non-goal. This change ports it, with its test
fix `c544020`. The KV-quantization commit of the same PR (`485902a`) stays
dropped.

What `f5e419d` changes, from its message and diff (read 2026-11-14 through the
GitHub API; the commits are not in the local object store):
- **Reasoning retention switch.** A request may set `preserve_thinking` (or the
  llama.cpp alias `preserve_reasoning`, which wins), at the top level or in
  `chat_template_kwargs`. The default, true, keeps today's bytes. With false,
  the reference template's window applies: reasoning is rendered only for
  assistant turns after the last real user query. Tool outputs never close the
  window.
- **Reasoning inside assistant content.** A client that replays its transcript
  can leave a leading `<think>…</think>` block inside `content`. The template
  extracts it and renders one reasoning pair. Today the child copies those
  bytes, and the tokenizer turns them into control tokens the model never
  sampled. An explicit `reasoning_content` wins over the in-content block.
- **Tool schemas.** Parsed strings go through `json_escape` (UTF-8 kept), but
  nested values are copied verbatim, so `—` stays six characters where
  the template renders one. `json_recode_value` recodes verbatim values the way
  `tojson` with `ensure_ascii=False` does. Structure, key order and spacing are
  unchanged. HTTP response writers keep escaping as before.
- **Effort aliases.** `extreme` and `ultracode` map to `xhigh` (the child's
  `DS4_THINK_HIGH`), and `off` to `none`.
- **`--trace`.** A request whose client text carries control-token spellings
  gets a `--- client control tokens ---` section. Rendering does not change.

## What Changes

- Port `f5e419d` and `c544020` into `ds4_server.c`, `tests/ds4_test.c`,
  `docs/SERVER.md`, `docs/TESTING.md` and `docs/QWEN38_FLASH_NEXT.md`.
  - Keep the Qwen branch of `render_chat_prompt_text_preserving` only.
  - Keep `append_glm_tool_schema_json`, which the Qwen tools prompt calls
    despite its name.
  - Drop the GLM and DeepSeek renderer branches.
- Add `tests/test_qwen4_reasoning_retention.py`, the PR's live regression with
  `c544020`'s fixes.
- `tests/template_parity_ab.py` needs `jinja2` (not installed here) and the
  reference template files. It is not ported (design D3).
- Add a model-free render check before the port: the same request corpus,
  rendered by the old and the new code, may differ only in the classes listed
  above (design D1).

**Which outputs change.** Only server chat requests whose rendered prompt
changes. That happens in four cases:
- a tool schema with JSON escapes in non-string values;
- an assistant history turn whose `content` starts with a `<think>` block;
- `preserve_thinking=false`;
- a reasoning effort spelled `extreme`, `ultracode` or `off`, which the child
  rejects today.

For those requests the prompt tokens change, so greedy output and the KV
checkpoint key may change: the first request of such a conversation after the
upgrade starts cold. Nothing else changes:
- the CLI and `sf-q3-8flash-bench` build prompts in `ds4.c`
  (`ds4_chat_append_message`, `ds4_encode_chat_prompt`) or by raw
  tokenization, and this port does not touch `ds4.c`;
- the parity oracle's prompts all go through the CLI.

So parity against upstream at the merge-base and the A/B token gate are
expected to pass unchanged. `speed-bench/perf-record.md` opens a new segment
when a template fix makes the token gate fail. This fix should not. If the gate
or parity fails, the port reached the CLI path, which is a defect to report.
It is not a reason to open a segment.

## Capabilities

### New Capabilities
- `chat-rendering`: how the server renders Qwen chat requests into a prompt
  (reasoning retention, reasoning carried in content, tool-schema text, effort
  names, and byte stability for every other request).

### Modified Capabilities
(none)

## Impact

- `ds4_server.c` (Qwen renderer, request parsing, trace), `tests/ds4_test.c`
  (`--qwen-render`, server unit tests), new
  `tests/test_qwen4_reasoning_retention.py`, `docs/SERVER.md`,
  `docs/TESTING.md`, `docs/QWEN38_FLASH_NEXT.md`, `docs/upstream-prs.md`
  (#1115 rows).
- Depends on `90`: `ds4_server.c` conflicts there, and `a8ce74a` (blank
  reasoning parsed as absent) arrives with it and touches the same renderer.
- `130-server-protocol-batch` touches the same renderer and comes after this
  change. Its #1288 masks control tokens in client text; this port only traces
  them (design D4).
- No engine, kernel or format change. No record row.
