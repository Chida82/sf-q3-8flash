# Directional steering

Qwen3.8 directional steering applies one float32 direction per hidden dimension
for each of the 48 trunk layers. Load a raw vector file with:

```sh
./sf-q3-8flash --dir-steering-file /path/to/vectors.bin \
  --dir-steering-ffn 1.0 --dir-steering-attn 1.0
```

The file contains `48 * 2560` native-endian float32 values in layer-major
order. In interactive mode, `/steer` changes scales without reloading the model.
Use `python3 tests/test_qwen4_steering.py --model /path/to/model.gguf` after
changes to capture, loading, graph application, or session reuse.

Steering changes model behavior intentionally. Keep a zero-scale run as the
control and verify that it matches ordinary inference exactly.
