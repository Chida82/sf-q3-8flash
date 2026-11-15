# Proposal

## Why

The sweep for `100-post-sync-ablation` proved more dead code than the sync
added. Change 100 removed the sync's own leftovers (part A) and the
init-only GLM pipelines (part B1). The rest is older: it came with the fork
and survived the earlier ablations because each piece hides behind a
constant that only the optimizer folds (`#if defined(__APPLE__) return
false`, a compress ratio that is always 0 for Qwen, a flag nothing sets), or
behind a name that sounds shared. It is about 6.5K lines of `ds4.c`,
`ds4_metal.m`, `ds4_image.c`, `ds4_server.c` and `metal/`. The child exists
to be cheap to read (StarForge rule 16), and most of it sits inside the
DeepSeek graph that `AGENTS.md` keeps for TP and pipeline plumbing, so every
part needs an explicit SPEC.md §B answer before it is cut.

## What Changes

Each part is removed in its own batch with its own gates, in this order
(largest proven win with the fewest §B questions first). Proof labels:
**linkO0** = no caller chain from any `main()` or test in the `-dead_strip`
link maps of all 41 binaries at -O0; **linkO1** = every caller folded at
-O1 -fno-inline, with the constant-false guard named; **M3** = the -O0 link
fails on functions declared and never defined, so their call sites are dead;
**lit** = no `"kernel_x"` literal the host can form.

- **B2, CUDA-only code in `ds4.c` (~3,000 lines).** The 40
  `metal_graph_cuda_*_requested/_threshold/_min_score` predicates (each
  `#if defined(__APPLE__) return false`) and their consumers: whole
  functions first (`metal_graph_prefill_pipeline_stage_major` and its stage
  helpers, `metal_graph_verify_decode2_exact`,
  `ds4_session_greedy_splitkv_replay_exact`,
  `metal_graph_encode_output_head_split_top1` and its reader,
  `metal_graph_cuda_tp_ep_finish_reduce`, the `engine_*cuda*` placement and
  output-shard helpers, `engine_install_per_device_caches`), then the CUDA TP
  blocks inside live DeepSeek-graph functions (~1,200 lines, guards
  `g->cuda_tp_*` and `cuda_tp_partner_tier`), the Metal shims for CUDA
  multi-GPU (`ds4.c` 136-375), their `ds4_gpu_mgpu.h` prototypes (SPEC.md
  §C lists that header for removal) and the 11 `ds4_gpu.h` prototypes that
  are declared and never defined. Proof: linkO1 per function, M3 for the
  undefined 11.
- **B3, DeepSeek compressed attention (~2,500 lines).** Everything behind
  `ds4_layer_compress_ratio() != 0`, which is 0 for every Qwen layer:
  `metal_graph_encode_layer_attention_batch`'s `ratio != 0` branch, the
  ratio-4 compressor state refresh, the `metal_graph_attn_comp_*` stages,
  `payload_{write,read}_tensor_span`; the `ds4_metal.m` wrappers only those
  branches call (`ds4_gpu_attention_indexed_mixed_batch_heads_tensor`,
  `ds4_gpu_qkv_pair_quad_compressor_store_tensor`,
  `ds4_gpu_indexer_score_one_tensor`,
  `ds4_gpu_matmul_f16_quad_compressor_store_tensor`,
  `ds4_gpu_dsv4_comp_row_finalize_tensor`,
  `ds4_gpu_indexer_scores_{batch,prefill,decode_batch}_tensor`,
  `ds4_gpu_compressor_prefill_state_ratio4_tensor`,
  `ds4_gpu_matmul_q8_0_kslice_rows_impl`, `ds4_gpu_dsv4_topk_mask_tensor`,
  `ds4_gpu_dsv4_indexer_qat_tensor`, ~1,190 lines) and the kernels only they
  name (`kernel_dsv4_indexer_scores_{tiled_f32,tiled,nax}`,
  `kernel_dsv4_indexer_score_one_{heads,direct}`,
  `kernel_dsv4_comp_row_finalize_f32`,
  `kernel_mul_mv_f16_f32_quad_compressor_store_4`,
  `kernel_dsv4_qkv_pair_quad_compressor_store_q8_0`). Proof: linkO1 with the
  guard `ds4_layer_compress_ratio() == 0` (an earlier `sf-ablate(ds4)`), then
  lit for the kernels once their host functions are gone.
- **B4, DeepSeek and GLM image preprocessing in `ds4_image.c` (~545
  lines).** `ds4_glm53_smart_resize`, `ds4_image_preprocess_glm53`,
  `ds4_deepseek4_{grid_tokens,solve_resize,safe_resize}`,
  `ds4_image_preprocess_deepseek{,4,41}`,
  `ds4_deepseek{4,41}_image_layout_build`, the patch/layout frees,
  `ds4_deepseek4_prefill_chunk`, `ds4_align_u32`, and their `ds4_image.h`
  declarations. Proof: linkO0. Kept although the name looks foreign:
  `ds4_deepseek4_next_image_span`, `ds4_deepseek4_attention_bounds`
  ("Names that lie"); `ds4_image_preprocess_qwen4`; the vendored
  `third_party/iris` decoders.
- **B5, small items (~250 lines).** `dot_iq2_pair_16` and `dot_q2_16`
  (unused in both the Metal and `DS4_NO_GPU` builds once `DS4_MAYBE_UNUSED`
  is off); `ds4_engine_power`/`ds4_engine_set_power` (`--power` is V4-only,
  SPEC.md §C); `ds4_think_max_prefix` and
  `ds4_chat_append_max_effort_prefix` (think-max is DeepSeek-only);
  `render_live_tool_tail` and `parse_generated_message_for_response` in
  `ds4_server.c`; four unused locals in
  `metal_graph_encode_decode_layer_phase`; the dead `string_value` branch of
  `dsml_decode_tracker_update`. Left over by 100, proof lit: the seven
  generic kernels whose init-only pipelines 100 removed
  (`kernel_get_rows_{q8_0,q4_0,q4_K}_f32`, `kernel_cpy_f16_f16`,
  `kernel_swiglu_f32`, `kernel_add3_f32`, `kernel_add_rms_norm_mul_f32_4`),
  `kernel_mul_mv_q8_0_f32_bf16{in,io}` (their only literals went with the
  V4.1 parallel-FFN modes), and the `dense.metal` multi-row template
  overloads with no instantiation left (`kernel_mul_mv_t_t_4_rows_impl`
  args_t variant, `kernel_mul_mv_t_t_4_rows` and its typedef, the
  `kernel_mul_mv_q8_0_f32_rows_impl` V4.1 overload), which also settles the
  naming collision the 90 merge left as a follow-up. Unreferenced Metal
  helpers that predate 100: `dsv4_attend_f32_row_as_f16`,
  `dsv4_attend_shared_f32_row_as_f16{,_at}`, `dsv4_indexer_dot128_shared_q`,
  `ds4_metal_expert_address_table`, the uninstantiated
  `kernel_mul_mm_id_addr` template and its two typedefs.
- **B6, preprocessor-dead blocks (~300 lines, optional).** `DS4_ROCM_BUILD`
  (never defined on Darwin), `DS4_HAS_DEEPSEEK41_GPU` (never defined in this
  child), and the `!__APPLE__` side in `ds4.c`, `ds4_gpu.h`, `ds4_tp.c`,
  `ds4_bench.c`. No block is over 5 lines, so per rule 16 only where another
  cut already passes through.

Non-goals: no behaviour change; no removal of the `ds4_tp` RDMA transport,
the layer-slice pipeline entry points, steering, the CPU reference path or
the disk KV cache (SPEC.md §B); no renames of `ds4_*` files.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: code removal with identical behaviour)

## Impact

- `ds4.c`, `ds4_metal.m`, `ds4_gpu.h`, `ds4_gpu_mgpu.h`, `ds4_image.c/.h`,
  `ds4_server.c`, `ds4.h`, `metal/*.metal`, possibly `ds4_tp.c` and
  `ds4_bench.c` (B6), `AGENTS.md`.
- Gates per part: `make -j8` with no warnings, `make cpu`, `make test -j8`
  naming its suites, `./ds4_test --server`, the kernel tests,
  `tests/model_gates.sh` on Q2 and Q4, the StarForge parity oracle and an A/B
  run with `--bitwise` against `main`.
- Depends on `100`. B2 and B3 add many conflict sites inside the DeepSeek
  graph; rerere replays them only when the conflict text is identical, so
  whole functions go first and scattered blocks only where the token saving
  is real.
