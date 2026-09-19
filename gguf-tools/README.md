# Qwen3.8 GGUF tools

This directory keeps only conversion, packing, n-gram, and quantization helpers
used by Qwen3.8 Flash Next.

- `qwen4_exp_convert.py`: convert the source checkpoint to `qwen4exp` GGUF.
- `qwen4_pack.py`: pack a converted model.
- `qwen4_pack_to_qwen4exp.py`: migrate an older packed GGUF.
- `qwen4_native_ngrams.py`: append the original BF16 n-gram table.
- `qwen4_iq2.py`: Qwen low-bit expert tooling.
- `gen_qwen4_unicode.py`: regenerate `ds4_qwen4_unicode.inc`.
- `quants.c/.h`: local quantization support.
- `glm53_quantize.py` and `glm53_manifest.py`: retained internal GGUF primitives
  imported by `qwen4_pack.py`; they are not model support or user entry points.
- `quality-testing/`: score local GGUFs against Qwen continuation fixtures.

The runtime requires the original BF16 n-grams, page-aligned after the mapped
weights. Validate the final artifact with `tests/test_qwen4_ngrams` and the
model-backed checks in `docs/TESTING.md`.
