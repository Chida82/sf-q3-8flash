# Testing

Run the model-less suite after every change:

```sh
make -j8
make test -j8
python3 tests/test_model_download.py
```

Focused checks:

```sh
make test-qwen4-kernels
make test-qwen4-q2
make test-qwen4-prefill-reuse
make test-q8-prefill-variants
make test-qwen4-ngrams
```

Model-backed checks require a Qwen3.8 GGUF:

```sh
make mtp-verify-depth DS4_TEST_MODEL=/absolute/path/model.gguf
./sf-q3-8flash-eval -m /absolute/path/model.gguf --suite core
./sf-q3-8flash-bench -m /absolute/path/model.gguf
```

Vision parity additionally requires the original checkpoint, projector GGUF,
and an image; see `make help` for the three environment variables.

Before a PR, run StarForge's parity oracle against the upstream merge-base.
Greedy tokens must match exactly and median throughput must remain within 2%.
