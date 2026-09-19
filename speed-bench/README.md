# Qwen3.8 benchmarks

The C benchmarks isolate Metal scheduling and prefill variants. The scripts
measure server concurrency and plot repeatable results. Historical Qwen
checkpoint results live in `qwen38-checkpoints/`.

Use the same GGUF, prompt, context, thermal state, and command-line options for
before/after runs. Report medians and verify generated tokens before accepting a
speed improvement.
