# sf-q3-8flash

`sf-q3-8flash` is a specialized fork of [ds4 / DwarfStar](https://github.com/antirez/ds4)
by Salvatore Sanfilippo and contributors, reduced to **Qwen3.8 Flash Next** on
**Apple Metal**. Upstream base commit: `8db1d1d` (updated at every sync).
Everything that works here works because of ds4, llama.cpp and GGML; see
`LICENSE` and the acknowledgements below.

## Acknowledgements to llama.cpp and GGML

`ds4.c` does not link against GGML, but it **exists thanks to the path opened by the
llama.cpp project and the kernels, quantization formats, GGUF ecosystem, and hard-won
engineering knowledge developed there**.
We are thankful and indebted to [`llama.cpp`](https://github.com/ggml-org/llama.cpp)
and its contributors. Their implementation, kernels, tests, and design choices were
an essential reference while building this DeepSeek V4 specific inference path.
Some source-level pieces are retained or adapted here under the MIT license: GGUF
quant layouts and tables, CPU quant/dot logic, and certain kernels. For this
reason, and because we are genuinely grateful, we keep the GGML authors copyright
notice in our `LICENSE` file.

## Scope

This repository intentionally supports one model and one production backend:
Qwen3.8 Flash Next (`qwen4exp`) on Apple Metal. The CPU implementation remains
for reference and tests. Qwen vision, built-in MTP, directional steering, the
HTTP server, disk KV cache, and the inherited TP/RDMA/pipeline plumbing are kept.
There is no bundled agent binary; connect an external client to the server.

The model combines gated delta-net and gated GQA layers, block-sparse attention,
hyper-connections, MoE, built-in MTP, and a large BF16 n-gram table read directly
from its GGUF. It is not a general GGUF runner and rejects other architectures.

## Build

Requirements: Apple Silicon, macOS, Xcode command-line tools, and enough memory
for the selected quantization.

```sh
make -j8
./download.sh q2                 # or q4
./sf-q3-8flash --ctx 8192 --prefill-chunk 1024
```

Q2 is about 137.10 GiB on disk with 41.73 GiB of resident weights. Q4 is about
165.11 GiB on disk with 69.74 GiB resident. Context and runtime buffers require
additional RAM. Both files include the original BF16 n-grams and MTP weights.

```sh
./sf-q3-8flash --mtp -p "Explain mmap in C"
./sf-q3-8flash-server --ctx 8192
curl http://127.0.0.1:8004/v1/models
```

The server supports OpenAI chat/completions and Responses APIs, Anthropic
Messages, request streaming, batching, tool calls, and optional disk KV cache:

```sh
./sf-q3-8flash-server --ctx 8192 \
  --kv-disk-dir ~/.sf/q3-8flash/kv --kv-disk-space-mb 8192
```

See `docs/SERVER.md` and `docs/CLIENTS.md`.

## Vision

```sh
./download.sh vision
./sf-q3-8flash --vision gguf/mmproj-Qwen3.8-Flash-Next-Q8_0.gguf
```

In the interactive CLI, use `/read image.png`. API clients can send image
content through the supported chat endpoints. See `docs/QWEN38_FLASH_NEXT.md`.

## Directional steering

Directional steering is retained for all 48 trunk layers:

```sh
./sf-q3-8flash --dir-steering-file vectors.bin \
  --dir-steering-ffn 1.0 --dir-steering-attn 1.0
```

The interactive `/steer` command can change scales. See
`dir-steering/README.md` for vector creation and format details.

## Development and verification

Read `AGENTS.md` before changing code. The normal local loop is:

```sh
make -j8
make test -j8
make test-qwen4-kernels
python3 tests/test_model_download.py
```

Model-backed MTP, vision, evaluation, benchmark, and upstream parity checks are
documented in `AGENTS.md` and `docs/TESTING.md`. The default model file is
`qwen3.8-flash-next.gguf`; `-m FILE` overrides it.

## Licence

MIT. `LICENSE` is inherited unchanged from ds4 and includes the GGML notice.
