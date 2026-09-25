# Built-in MTP

Qwen3.8 Flash Next stores its MTP weights in the main GGUF. Enable speculative
decoding with `--mtp`; no support model is required.

```sh
./sf-q3-8flash --mtp -p "Explain speculative decoding."
./sf-q3-8flash-server --mtp --ctx 8192
```

Prefill primes the predictor. For a text prompt, the MTP layer's caches are
filled over every prompt position during prefill, so the first drafts already
attend over the prompt. Prompts with images are not primed. Priming costs about
2% of prefill throughput in MTP mode; plain mode does no predictor work.

Each cycle drafts one token (depth two) or two chained tokens (depth three). The
runtime moves to depth three after a run of accepted first drafts, and back when
acceptance or the second draft falters. `DS4_QWEN4_MTP_DEPTH=2` or `=3` pins the
depth for diagnosis. `--mtp-exact-sampling` preserves ordinary sampling
semantics, and runs at depth two at nonzero temperature; greedy decoding accepts
matching drafts directly.

The predictor gathers token embeddings on the GPU, which reads f32, f16, bf16,
q8_0 and q4_0 tables; `--mtp` refuses a model whose table is another type. The
published GGUFs store it as bf16.

After changes to MTP, session rollback, recurrent state, batching or sampling,
run the session and snapshot tests with built-in MTP enabled:

```sh
DS4_TEST_MODEL=/absolute/path/model.gguf DS4_TEST_GLM_MTP=1 ./ds4_test
python3 tests/test_qwen4_mtp_limits.py --model /absolute/path/model.gguf
```

There is no depth-verification target: the one inherited from upstream drove
an external MTP support GGUF, which this child does not accept.
