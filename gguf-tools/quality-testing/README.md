# Qwen3.8 quality testing

`score_official` measures local Qwen3.8 GGUF continuations against curated
Alibaba-hosted fixtures. The retained datasets are:

- `data/qwen38-flash-alibaba-100`: 100 short no-thinking prompts.
- `data/qwen38-flash-alibaba-long`: 12 archive/code prompts from 2K to 24K.

Build the scorer and run from the repository root:

```sh
make gguf-tools/quality-testing/score_official
gguf-tools/quality-testing/score_official MODEL.gguf \
  gguf-tools/quality-testing/data/qwen38-flash-alibaba-100/manifest.tsv /tmp/qwen-short.tsv 4096
gguf-tools/quality-testing/score_official MODEL.gguf \
  gguf-tools/quality-testing/data/qwen38-flash-alibaba-long/manifest.tsv /tmp/qwen-long.tsv 32768
```

Use `--quality` to compare the quality path. For long prompts also compare
`--continued-prefill 1` and `--continued-prefill 256`. Hosted output is a
reference signal, not proof of checkpoint identity; local upstream parity is
the release gate.
