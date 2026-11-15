# Proposal

## Why

Every Qwen prefill layer writes the hyper-connection residual in its own
pass and then reads it straight back in the next stream norm. This happens
after attention (`R += 2*sigmoid(inj/hc) * blk`) and again inside
`kernel_qwen4_moe_reduce`. #1150 (`ce6d991`) defers the write into that norm
pass instead. A new `kernel_qwen4_hc_combine_norm_rows` applies the pending
`(blk, inj)` write to its own `R` slice in the `hc_norm_reuse` layout, so the
read-modify-write is race-free.

The author's figures (M5 Max, not reproduced here):
- the write+norm pair goes from 122.2 to 88.2 µs at T = 256;
- the hc_ffn stage of a 4096-token chunk goes from 242.6 to 191.7 ms;
- Q4 prefill is +2.4% at 8192 tokens and +1.3% at 32768.

The author reports it bit-identical to the eager pair: the test pins R, xn and
inj byte for byte across f32/f16/q8 inject weights and T = 3..256, and the
prefill variant bench's logit gate passes. Eager writes stay where a consumer
reads R directly:
- T <= 3 (verify and decode rows);
- layers that feed the PLE block;
- the last trunk layer, whose pre-mixer R the predictor captures.

The debug dumps and an enabled FFN steering projection flush the pending
write first. `DS4_QWEN4_NO_HC_DEFER` keeps the eager writes.

## What Changes

- Port `ce6d991` (Metal only; `04dbebe` is CUDA and is dropped):
  - `kernel_qwen4_hc_combine_norm_rows` in `metal/qwen4.metal`;
  - its wrapper `ds4_gpu_qwen4_hc_combine_norm_rows_tensor`;
  - the pending-write state in `ds4_qwen4_gpu_graph`;
  - the call sites in `qwen4_graph_forward_tokens`, `qwen4_graph_moe`,
    `qwen4_graph_apply_steering_ffn` and the MTP chain;
  - the byte-exact kernel test.
- Check it against what the child has and #1150's base did not:
  - **`40`'s HC reuse kernel** (`kernel_qwen4_hc_norm_reuse_*`, M5, one decode
    token). T = 1 keeps eager writes, so the two should not meet, but the
    shared `hc_norm_reuse` layout is checked;
  - **`30`'s priming**, which runs the predictor's attention over every
    prompt chunk and writes the predictor residual over the trunk streams in
    place. It must see a flushed R, so the last-trunk-layer exception has to
    cover the child's priming call as well as upstream's predictor capture;
  - **`82`'s exact verify rows** (T <= 3 eager: unchanged by construction);
  - **the steering FFN flush**: steering stays in every child (StarForge
    rule 4).
- Decide on GPU section time, then guard with the harness (design D2).

Non-goals: CUDA; changing the eager kernels; decode (T = 1 is untouched).

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: the change claims bit-identical prefill and decode logits; the
existing `mtp-speculation` and `ssd-streaming` requirements must keep
passing)

## Impact

- `metal/qwen4.metal`, `ds4_metal.m`, `ds4_gpu.h`, `ds4.c` (prefill HC path),
  `tests/test_qwen4_kernels.c`, `speed-bench/perf-record.md`,
  `docs/upstream-prs.md`.
- Runs after `90`: #1238's `b5aedb9` changes the HC norm and inject loads that
  this kernel builds on. The port starts from the synced kernels.
- Ends, like every performance change, with `tools/parity-check.sh` and an
  A/B against the current segment's start, plus its record row.
