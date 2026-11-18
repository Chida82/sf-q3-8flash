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
semantics at nonzero temperature and follows the same depth policy and pin:
each draft is accepted with its target probability, position by position, and
the first rejection emits a residual sample and ends the cycle. The cycle draws
the next token itself, from the same sampler and RNG, so the next draft is
conditioned on the token that will be emitted, and a residual sample opens the
next verify instead of a one-row replay; `ds4_session_sample` returns that held
token at the same position and sampler, and a rewind, sync, snapshot restore
or `ds4_session_set_logits` drops it. Greedy decoding accepts matching drafts
directly.

Drafts can also come from the context. When the last three committed tokens
and the next one occurred earlier in the prompt or the output, and the two
sites agree six or more tokens back, the two tokens that followed are a
second source for the cycle's draft rows (prompt lookup). The predictor still
runs every cycle, so its state stays current and its own first draft is known:
- each source keeps a window of its last eight first-draft verdicts, scored
  on every cycle, whichever source drafted it;
- the lookup is heard while six of its last eight were right. When both name
  the same first token, the lookup's second token is verified as the second
  draft, at either depth, and the predictor's chained step is not run. When
  they differ, the source with the better window drafts, the predictor on a
  tie;
- a looked-up second draft that misses counts against the lookup.
Verification decides acceptance as for any draft, so the output does not
change; under `--mtp-exact-sampling` a looked-up token is a point proposal
like the predictor's. The index takes 16 bytes per context token at a
131072-token context (2 MiB); building it over 100K tokens takes about a
millisecond, and each cycle about 18 microseconds. Batched server sessions
draft from the predictor only. `DS4_QWEN4_MTP_LOOKUP=0` turns the lookup off. With
`--mtp-timing` the session reports how many cycles a lookup drafted. On an
edit that copies most of a file from its prompt (the `mtp-copy` bench kind)
MTP decode is 5.0% faster on Q2 and 4.7% on Q4; code and prose prompts are
unchanged.

Greedy output with `--mtp` is byte-identical to plain greedy output. The verify
pass scores two or three rows at once, and each row must compute exactly as a
single decoded token would, or near ties can flip. So the verify rows take:
- the single-token matvec for F16, F32 and Q8_0 weights, with 2- and 3-row
  variants that read the weights once;
- the per-row HC mixer, never the paired one;
- the batched-session attention rows kernels, which give each row its own key
  count, split geometry and block universe.

`tests/test_qwen4_mtp_identity.py` checks this over 12 prompts at every depth.

Across turns the same holds only if both modes start each turn from the same
KV. Plain decode stops at a sampled stop token without evaluating it; a verify
pass can accept it as a draft, and commit drafts after it. The server and the
REPL therefore rewind a verify block to the tokens they keep (the server's
speculative boundary rewind, the REPL's turn end). The rewind restores the
verify snapshot, so it costs no recomputation. `tests/test_qwen4_cli_vision.py
--compare` checks REPL conversations, text-only (`--text-turns`) and with
images.

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

After changes to exact sampling, also run its session test and compare the
sampled distribution with the previous build (a built tree at `PREV`):

```sh
DS4_TEST_MODEL=/absolute/path/model.gguf DS4_TEST_GLM_MTP=1 DS4_TEST_MTP_EXACT=1 \
    ./ds4_test --session-exact-held --session-rewind-resample
python3 tests/test_qwen4_exact_sampling_dist.py --model /absolute/path/model.gguf \
    --a PREV --b . --depth 3
```

There is no depth-verification target: the one inherited from upstream drove
an external MTP support GGUF, which this child does not accept.
