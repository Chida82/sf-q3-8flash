# Performance

Judge a change with the A/B harness, which runs the baseline and the
candidate tree interleaved on the same GGUF, gates on identical tokens (and,
with `--bitwise`, identical logits) and reports the median B/A ratio per metric:

```sh
python3 speed-bench/ab_bench.py --a /path/to/baseline-tree --b .
```

See "A/B harness" in [speed-bench/README.md](../speed-bench/README.md) for
the procedure, the thermal preheat and the measured noise floor. For a single
build, `./sf-q3-8flash-bench -m /absolute/path/model.gguf` still prints the
raw CSV.

Report median prefill and decode throughput, memory use, model quantization,
context size, and whether MTP or vision was enabled. A valid optimization must
preserve output correctness. StarForge parity permits at most a 2% throughput
regression and requires token-identical greedy output.

Qwen-specific historical measurements and scripts are under
`speed-bench/qwen38-checkpoints/`.
