# Qwen3.8 Flash Next model card

This repository executes Qwen3.8 Flash Next GGUF files using the `qwen4exp`
architecture. It does not redistribute model weights. Obtain supported Q2, Q4,
and vision artifacts with `download.sh`; their upstream repositories provide
the authoritative model licence and provenance.

The runtime supports text generation, Qwen3-VL vision, directional steering,
and built-in MTP on Apple Metal. Quantization, prompt format, context length,
and sampling settings affect quality. Validate intended workloads before
production use and do not treat generated output as guaranteed factual.
