# Proposal

## Why

The sync to `b3f5018` (`90`) left out four pieces of performance work on
purpose, to keep the merge's risk to output identity small. Each is either
upstream code that needs a kernel the child removed, or child code that the
merge replaced with upstream's equivalent. The A/B run that closed `90` (Q4, `--bitwise`, old `main` against `main`) measured prefill at -0.3% (8192), -1.0% (+512) and -0.7% (+2048, range -0.9..-0.1%): small, but on the wrong side, and step 1 is the prefill one. Each is bit-identical by its own
claim, so each can come back as a measured step under the project's A/B rules
(`openspec/config.yaml`).

## What Changes

One measured step each, in this order, every one gated on bitwise logits
(`ab_bench.py --bitwise`) and the identity test:

1. **Device gather of prompt embeddings (the idea of `1c6d058`, not its
   kernels).** Upstream gathers BF16 embedding rows on the GPU with
   `kernel_glm53_embedding_bf16` and then expands them to the HC streams with a
   second dispatch (`ds4_gpu_repeat_hc_rows_tensor`). That kernel is a plain
   row gather (token id to BF16 row to FP32) that upstream happened to write
   for GLM 5.3; it lives in `metal/glm53_bf16.metal`, a file this child
   deleted with GLM. Taking it would bring back a GLM file and a GLM name for
   twelve lines of code.

   The child already has the piece that matters: `qwen4_embd_at` in
   `metal/qwen4.metal`, the device dequantizer of one embedding element for
   every table type the host reference reads (F32, F16, BF16, Q8_0, Q4_0),
   exact against `qwen4_ref_row` and used today by `kernel_qwen4_mtp_stage`.
   Write one Qwen kernel, `kernel_qwen4_embd_rows`, that reads the token ids
   from `g->selected`, dequantizes with `qwen4_embd_at`, and writes each value
   to all `hc` streams of `g->R` in the same thread: one dispatch, no repeat
   pass, no GLM file, no BF16-only condition. Image spans and short inputs keep
   the host path, as upstream does; the length threshold (upstream: 128) is
   measured, not copied. Remove the `sf-keep(sync)` marker in
   `qwen4_graph_stage_embeddings`, replacing it with an `sf-keep(sync)` that
   names the Qwen kernel standing in for upstream's pair. Target: prefill at
   16K and 32K contexts (E2: -5.8% at 32768).
2. **MoE for the last MTP row only (`qwen4_graph_moe_last`).** Upstream runs the
   predictor's routed experts only for the row whose output feeds the draft.
   Target: MTP decode on code and prose; the identity test must still pass at
   every depth.
3. **The `70` MXFP4 down pass.** The merge took upstream's
   `kernel_qwen4_moe_down_mxfp4_pf` in place of the child's
   `qwen4_moe_down_mxfp4_pass` refactor with shared Q8 row reuse (Q4 decode
   `moe_down` -2.5% GPU time when measured in `70`). Re-measure it on top of
   upstream's #1238 kernels; take it back only if it still gains.
4. **Template names in `metal/dense.metal` (D5 clean-up, no speed claim).** The
   child's `82` row templates and upstream's V4.1 templates share the names
   `kernel_mul_mv_q8_0_f32_rows_impl` and `kernel_mul_mv_t_t_4_rows(_impl)` as
   overloads. Rename the child's to `*_vrows*` (host names unchanged), and use
   upstream's exact F16 multi-row kernel if `82`'s byte-exact pin passes on it.

Non-goals: no change to output; Q2-only effects wait for the Q2 pack.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: bit-identical performance work)

## Impact

- `ds4.c` (stage embeddings, MTP steps), `ds4_metal.m`, `ds4_gpu.h`,
  `metal/qwen4.metal` (the gather kernel), `metal/dense.metal`.
- `speed-bench/perf-record.md`: one row per kept step, in the segment `90`
  opens.
- Depends on `90`.
