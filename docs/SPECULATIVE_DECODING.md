# Built-in MTP

Qwen3.8 Flash Next stores its MTP weights in the main GGUF. Enable speculative
decoding with `--mtp`; no support model is required.

```sh
./sf-q3-8flash --mtp -p "Explain speculative decoding."
./sf-q3-8flash-server --mtp --ctx 8192
```

The runtime adaptively uses depth two or three. `DS4_QWEN4_MTP_DEPTH=2` or `=3`
can pin the depth for diagnosis. `--mtp-exact-sampling` preserves ordinary
sampling semantics; greedy decoding accepts matching drafts directly.

Run `make mtp-verify-depth DS4_TEST_MODEL=/absolute/path/model.gguf` after
changes to MTP, session rollback, recurrent state, batching, or sampling.
