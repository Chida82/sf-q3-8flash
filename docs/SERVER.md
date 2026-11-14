# Server

Build and start the Qwen3.8 server:

```sh
make -j8
./sf-q3-8flash-server --ctx 8192
```

It binds `127.0.0.1:8004` by default. Override with `--host` and `--port`.
Supported APIs are OpenAI chat completions, Responses, text completions, and
Anthropic Messages. `GET /v1/models` lists the Qwen aliases accepted by this
server.
Each entry, and `GET /v1/models/{id}`, reports `architecture.input_modalities`
(`["text", "image"]` when `--vision` is loaded, otherwise `["text"]`) and
`architecture.output_modalities` (`["text"]`). A request may carry up to 256
images.

Built-in MTP is enabled with `--mtp`. Add `--mtp-exact-sampling` when sampled
requests must preserve the ordinary distribution. Supply the Qwen3-VL
projector with `--vision FILE` for image inputs.

## Reasoning controls

Besides `max`, `xhigh` or `high`, `medium`, `low` and `none`,
`reasoning_effort` takes client aliases: `extreme` and `ultracode` map to
`xhigh`, `minimal` maps to `low`, and `off` maps to `none`.

`preserve_thinking` (or the llama.cpp alias `preserve_reasoning`, which wins)
controls whether the prompt replays every historical reasoning block. It is
accepted at the top level and inside `chat_template_kwargs`, which overrides
the top level, and defaults to true, the shipped template's rendering. With
false, the template's own window applies: reasoning is rendered only for turns
after the last real user query, so a running tool loop keeps the chain that
produced it while earlier loops lose it. Tool outputs never close the window.

A history assistant turn whose `content` starts with a `<think>` block is
rendered with that block as its reasoning, in the template's framing; an
explicit `reasoning_content` wins and the in-content block is dropped. Tool
schemas reach the prompt the way the template's `tojson` writes them: an
escaped character such as `\u2014` becomes its UTF-8 bytes, while control
characters stay escaped.

Switching the flag changes the prompt, so the first request under the new
setting starts cold by design. Reuse requires the new prompt to extend the one
already in the session: resending an equal or shorter history reports
`reason=token-mismatch` even when every token matches, because the live Qwen
session is not rewound. Agent loops that only append are unaffected.

## Disk KV cache

```sh
./sf-q3-8flash-server --ctx 8192 \
  --kv-disk-dir ~/.sf/q3-8flash/kv --kv-disk-space-mb 8192
```

The cache validates model and quantization identity. Use
`--kv-cache-reject-different-quant` for strict quantization isolation. Tool-call
continuations retain the exact sampled model state when protocol IDs permit it.

## Concurrency

`--batched-session N` keeps N resident sessions and batches decode-ready work.
`--mixed-prefill-quantum N` bounds prefill work while generation is active.
Images and steering use an ordered fallback rather than native batched decode.

For local debugging, `--trace FILE` records prompts and cache decisions. Treat
traces as sensitive because they contain request content. A request whose
client text spells Qwen control tokens (`<|im_end|>`, `<think>`,
`<tool_call>`, ...) gets a `--- client control tokens ---` section naming each
token, its count and the role where it first appears: the tokenizer turns those
spellings into real control tokens. The prompt is not rewritten. Run
`./ds4_test --server` after server changes and use the focused integration test
for the protocol touched.
