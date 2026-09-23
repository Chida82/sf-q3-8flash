# Qwen3.8 GGUF tools

This child does not convert or quantize models; it runs the published GGUFs
that `download.sh` fetches.

- `gen_qwen4_unicode.py`: regenerate `ds4_qwen4_unicode.inc`.
- `quality-testing/`: score local GGUFs against Qwen continuation fixtures.
