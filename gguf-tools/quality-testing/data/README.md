# Qwen3.8 quality fixtures

This directory retains Qwen3.8 Flash Next continuation fixtures collected from
a pinned Alibaba endpoint:

- `qwen38-flash-alibaba-100`: 100 short no-thinking prompts.
- `qwen38-flash-alibaba-long`: 12 archive/code prompts crossing sparse-attention boundaries.

Each set contains exact prompts, continuations, available response metadata,
and a `manifest.tsv` consumed by `score_official`. Collection metadata records
the provider and prompt-template hashes. Hosted precision may differ from the
local checkpoint, so use these fixtures as quality signals alongside local
upstream parity.
