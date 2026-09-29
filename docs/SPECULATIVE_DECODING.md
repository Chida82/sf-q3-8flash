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

Greedy output with `--mtp` is byte-identical to plain greedy output. The verify
pass scores two or three rows at once, and each row must compute exactly as a
single decoded token would, or near ties can flip. So the verify rows take:
- the single-token matvec for F16, F32 and Q8_0 weights, with 2- and 3-row
  variants that read the weights once;
- the per-row HC mixer, never the paired one;
- the batched-session attention rows kernels, which give each row its own key
  count, split geometry and block universe.

`tests/test_qwen4_mtp_identity.py` checks this over 12 prompts at every depth.

The predictor gathers token embeddings on the GPU, which reads f32, f16, bf16,
q8_0 and q4_0 tables; `--mtp` refuses a model whose table is another type. The
published GGUFs store it as bf16.

After changes to MTP, session rollback, recurrent state, batching or sampling,
run the session and snapshot tests with built-in MTP enabled:

```sh
DS4_TEST_MODEL=/absolute/path/model.gguf DS4_TEST_GLM_MTP=1 ./ds4_test
python3 tests/test_qwen4_mtp_limits.py --model /absolute/path/model.gguf
python3 tests/test_qwen4_mtp_identity.py --model /absolute/path/model.gguf
```

There is no depth-verification target: the one inherited from upstream drove
an external MTP support GGUF, which this child does not accept.
