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

Built-in MTP is enabled with `--mtp`. Add `--mtp-exact-sampling` when sampled
requests must preserve the ordinary distribution. Supply the Qwen3-VL
projector with `--vision FILE` for image inputs.

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
traces as sensitive because they contain request content. Run
`./ds4_test --server` after server changes and use the focused integration test
for the protocol touched.
