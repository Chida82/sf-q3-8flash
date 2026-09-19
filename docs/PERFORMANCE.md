# Performance

Benchmark with the same GGUF, prompt, context, sampling settings, and machine
before and after a change:

```sh
./sf-q3-8flash-bench -m /absolute/path/model.gguf
```

Report median prefill and decode throughput, memory use, model quantization,
context size, and whether MTP or vision was enabled. A valid optimization must
preserve output correctness. StarForge parity permits at most a 2% throughput
regression and requires token-identical greedy output.

Qwen-specific historical measurements and scripts are under
`speed-bench/qwen38-checkpoints/`.
