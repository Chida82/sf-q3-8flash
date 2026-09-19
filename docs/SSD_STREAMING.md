# SSD streaming

The SSD subsystem is retained because it is part of the StarForge child
contract and Qwen's BF16 n-gram table is read directly from the GGUF. The main
Qwen3.8 graph currently requires resident model weights and rejects the general
`--ssd-streaming` execution mode.

Keep the GGUF on a fast local SSD. Do not remove `ds4_ssd.*` or generic cache
interfaces when changing the Qwen graph: they are shared by tests and by the
n-gram path. Enable full model-weight streaming only after a Qwen-specific
implementation and model-backed parity test exist.
