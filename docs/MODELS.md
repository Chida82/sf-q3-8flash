# Model

This repository accepts Qwen3.8 Flash Next GGUFs with architecture `qwen4exp`.
The supported production shape has 48 trunk layers plus one built-in MTP block,
a 2560-wide hidden state, gated delta-net and gated GQA layers, 512 routed
experts, hyper-connections, and disk-backed BF16 n-grams.

`DS4_SHAPE_QWEN4_MINI` exists only for synthetic tests. Other architectures are
rejected during metadata validation.

Use `./download.sh q2` or `./download.sh q4`. Both artifacts include the main
model, n-grams, and MTP weights. Use `./download.sh vision` for the separate
Qwen3-VL projector.
