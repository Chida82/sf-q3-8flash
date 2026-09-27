# sf-q3-8flash

`sf-q3-8flash` is a specialized fork of [ds4 / DwarfStar](https://github.com/antirez/ds4)
by Salvatore Sanfilippo and contributors, reduced to **Qwen3.8 Flash Next** on
**Apple Metal**. The upstream commit this fork sits on is not written here:
ask git, which cannot go stale --
`git describe --tags --match 'sync-*' --abbrev=0` for the last sync, or
`git merge-base HEAD upstream/main` for the base itself.
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

## Quality and performance

**Token quality.** Performance work here must not change what the model
writes. Every change is checked in four ways:
- the StarForge parity oracle (`tools/parity-check.sh`) runs ten prompts
  greedily on this child and on upstream ds4 at the child's merge-base, with
  the same GGUF, and requires token-identical output;
- the A/B harness requires identical tokens against the previous build, and
  bit-identical logits (`--bitwise`) when a change claims it;
- kernel tests compare every optimized kernel with the CPU reference or with
  the kernel it replaces, byte for byte at their edge sizes;
- `tests/test_qwen4_mtp_limits.py` checks MTP's draft depth and rollback
  limits.

**Performance.** `speed-bench/ab_bench.py` alternates the two builds in ABBA
pairs for 600 s, drops pairs whose GPU clock sagged, and reports medians with
bootstrap 95% intervals for plain decode, prefill at three shapes, and MTP on
code and prose. A step is kept only when its target gains and no metric
clearly loses. Each change appends a row to `speed-bench/perf-record.md`
against a fixed start commit. See `speed-bench/README.md`.

**Against ds4.** Measured on 2026-09-27 on an M5 Max, 128 GB, using upstream's
own methods. The builds compared are ds4 at the merge-base `0aaea5a` and this
child with `81-q2-prefill-tails`.
- The sweep rows use `ds4-bench` on *I Promessi Sposi*: 2048-token intervals up
  to 65536, and 128 generated tokens per context size.
- Past the 1 GiB snapshot limit, both benches replay the prefix.
- The CLI rows use upstream's three Qwen cases (`--ctx 8192 --temp 0
  --nothink`) and give the mean generation speed.
- Each value is the mean of two runs per build, in the order ds4, sf, sf, ds4.

| Pack | Measurement | ds4 t/s | sf t/s | sf vs ds4 |
|---|---|---:|---:|---:|
| Q2 | prefill, context 2048 | 1361.0 | 1427.8 | +4.9% |
| Q2 | prefill, context 16384 | 1293.2 | 1372.2 | +6.1% |
| Q2 | prefill, context 32768 | 1131.5 | 1264.8 | +11.8% |
| Q2 | prefill, context 65536 | 916.4 | 999.6 | +9.1% |
| Q2 | generation, context 2048 | 51.9 | 56.7 | +9.3% |
| Q2 | generation, context 16384 | 51.7 | 56.3 | +9.1% |
| Q2 | generation, context 32768 | 48.6 | 54.7 | +12.6% |
| Q2 | generation, context 65536 | 43.0 | 47.3 | +10.1% |
| Q2 | CLI generation, no MTP | 54.2 | 59.1 | +9.0% |
| Q2 | CLI generation, MTP | 75.7 | 83.8 | +10.7% |
| Q4 | prefill, context 2048 | 1365.9 | 1396.5 | +2.2% |
| Q4 | prefill, context 16384 | 1261.4 | 1343.3 | +6.5% |
| Q4 | prefill, context 32768 | 1107.9 | 1234.9 | +11.5% |
| Q4 | prefill, context 65536 | 907.4 | 994.0 | +9.5% |
| Q4 | generation, context 2048 | 54.1 | 54.4 | +0.5% |
| Q4 | generation, context 16384 | 53.5 | 54.0 | +0.9% |
| Q4 | generation, context 32768 | 48.5 | 52.4 | +8.1% |
| Q4 | generation, context 65536 | 41.7 | 44.1 | +5.9% |
| Q4 | CLI generation, no MTP | 56.5 | 57.5 | +1.9% |
| Q4 | CLI generation, MTP | 78.7 | 83.4 | +6.1% |

Without MTP, the text of all six CLI cases is identical between ds4 and this
child. With MTP, five of the six match plain greedy output. The exception is
Q2 on the networking prompt, which diverges after two paragraphs. The
divergence starts with the predictor priming taken in `30-mtp-cycle`.

## Licence

MIT. `LICENSE` is inherited unchanged from ds4 and includes the GGML notice.
