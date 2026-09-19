# Engineering notes

`sf-q3-8flash` is a focused Qwen3.8 Flash Next inference engine for Apple
Metal. It is not a general GGUF runner. Keep the C implementation readable,
use Objective-C only at the Metal boundary, and keep kernels under `metal/`.

## Goals

- Preserve the whole-model Metal graph as the production path.
- Keep model loading mmap-backed. The large BF16 n-gram table stays on disk and
  selected rows are read directly from the GGUF.
- Keep the CPU path as a correctness/reference implementation and for fast
  model-less tests; avoid huge CPU inference runs on macOS.
- Preserve correctness before speed. Never accept unexplained attention,
  recurrent-state, KV-cache, MTP, or logits drift.
- Keep vision, directional steering, disk KV checkpoints, and the existing
  distributed plumbing working when touching shared code.

## Quality rules

- Prefer the smallest direct implementation. Do not add C++, speculative
  abstractions, permanent semantic variants, or a dependency for stdlib work.
- Before changing a helper, find every caller. Fix a root cause once.
- Keep public APIs narrow: frontends should not know tensor internals.
- Comment only non-obvious model mechanics, cache lifetime, memory policy, and
  synchronization constraints.
- New branches, parsers, kernels, and state transitions need one focused
  runnable regression. Reuse the existing test nearest to the behavior.
- Preserve input validation and clean failure at GGUF, HTTP, snapshot, and
  filesystem boundaries.

## Layout

- `ds4.c`: Qwen model loading and validation, tokenizer/chat rendering, CPU
  reference, graph scheduling, sessions, MTP, and payload serialization.
- `ds4_metal.m`: Metal resource lifetime and kernel wrappers.
- `metal/qwen4.metal`: Qwen text and MTP kernels.
- `metal/qwen4_vision.metal`: Qwen vision kernels.
- `ds4_cli.c`: command line and interactive REPL.
- `ds4_server.c`: OpenAI/Responses/Anthropic-compatible HTTP server, batching,
  tool-call continuation, and disk KV policy.
- `ds4_bench.c`, `ds4_eval.c`: performance and quality tools.
- `ds4_tp.*`, `ds4_distributed.*`: retained transport/distributed code.
- `tests/test_qwen4_*`: Qwen-specific tests; `tests/ds4_test.c` covers shared
  session and server behavior.

## Testing

Start with `make -j8 && make test -j8`. Use the focused Qwen targets listed in
`AGENTS.md`; model-backed tests and parity require the large Qwen GGUF. For a
performance change, compare identical prompts, context, quantization, and
sampling settings before and after, and report medians rather than a best run.
Do not run multiple full model processes concurrently.
