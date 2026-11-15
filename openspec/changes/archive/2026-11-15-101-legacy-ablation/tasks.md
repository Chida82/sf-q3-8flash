# Tasks

Starts from `main` with `100-post-sync-ablation` landed. One part per batch,
in the order below; a red gate sends the batch back to be split, never
forward. Model runs are strictly sequential; nothing else runs beside one.
The proofs come from 100's sweep (link maps at -O0 and -O1 -fno-inline over
all 41 binaries, DWARF line tables, the kernel-literal audit); re-run them on
the current tree before each part, because 100 moved every line number.

## 1. Settle the SPEC.md §B questions (no code change)

- [x] 1.1 B2: does the CUDA tensor-parallel code inside the DeepSeek graph (`g->cuda_tp_*`, `cuda_tp_partner_tier`, the multi-GPU shims) count as the TP plumbing §B keeps? It is the CUDA backend (§C, non-Metal), not the `ds4_tp` RDMA transport, but it is interleaved with code §B keeps. Owner answer recorded here.
- [x] 1.2 B2: confirm `metal_graph_prefill_pipeline_stage_major` is CUDA micro-batching and not reached from any `ds4_session_*layer*` entry point (the layer-slice pipeline §B protects). Call-graph listing from those entry points.
- [x] 1.3 B3: does DeepSeek compressed attention lie inside the graph the TP/pipeline path reaches? List which of its functions `ds4_session_*layer*` and the TP spec cycle call by name. The `ratio != 0` branches of `ds4_session_save/load_layer_payload` and `ds4_session_save/load_payload` are reachable by call graph and dead by value (ratio is 0 for every Qwen layer): owner decides whether §B protects them (100's question Q2). Until then they stay, with `sf-keep` markers.
- [x] 1.4 B4: confirm the registry's vision clause keeps only this model's preprocessing (Qwen3-VL), so the DeepSeek and GLM paths in `ds4_image.c` are removable.

Outcomes (2026-11-14; owner answers at ~22:30 CET; call graph built with the
preprocessor applied for the Metal and `DS4_NO_GPU` configs, guards checked
by hand):

- 1.1 Owner: the CUDA TP code inside the DeepSeek graph is not §B TP
  plumbing; remove it. `ds4_tp`, `ds4_distributed` and the layer-slice entry
  points stay.
- 1.2 Correction: `metal_graph_prefill_pipeline_stage_major` IS reached by
  name (`ds4_session_eval_layer_slice` -> `metal_graph_prefill_layer_major`
  -> `stage_major`), behind `metal_graph_cuda_prefill_pipeline_requested(g)`,
  which is false under `__APPLE__`: dead by value, so B2 per 1.1. The other
  B2 blocks reached from `eval_layer_slice` and `ds4_session_tp_spec_cycle`
  (`g->cuda_tp_*` in the decode layer phase, output-head TP, the multi-tier
  shims) are dead by value too: every `*_requested()` is false on Apple,
  nothing sets `opt->cuda_tensor_parallel`, `g_n_gpus` is never assigned.
  Trap: `metal_graph_cuda_stream_prefill_batch_selected_load` returns TRUE
  on Apple; drop the call and keep `ok`.
- 1.3 Owner: compressed attention and the `ratio != 0` save/load branches
  are not §B; remove them with `sf-ablate` markers and keep the snapshot
  bytes unchanged. Proof: with ratio 0 every save/load loop hits `continue`
  before the branch; the per-layer `n_comp`/`n_index_comp` u32 headers sit
  outside the branches and stay; Qwen GPU sessions return through
  `qwen4_session_{save,load}_payload` first. No layer-slice or TP entry
  point calls a B3 function by name except the payload span helpers.
  Corrections to the proposal: `payload_{write,read}_tensor_span` carry the
  raw KV rows and the whole Qwen payload and stay; only their
  `_f16_as_f32`/`_f32_as_f16` variants are B3.
  `ds4_gpu_matmul_q8_0_kslice_rows_impl` is dead because its only caller
  passes `full_low_dim = 0`, not because of the ratio. Keep
  `ds4_layer_compress_ratio` and `ds4_engine_layer_compress_ratio`
  (`dist_kv_layer_tensor_bytes` uses them) and the CPU compressed-attention
  code (§B CPU reference). `ds4_layer_compress_ratio` returns a literal 0;
  the validated GGUF ratios in `g_ds4_compress_ratios` are read by nothing.
- 1.4 Owner: vision is Qwen3-VL only; the DeepSeek and GLM preprocessing in
  `ds4_image.c` goes. Keep `ds4_deepseek4_attention_bounds` (reached from
  the DeepSeek graph's visual mask on the layer-slice path, not from the
  Qwen graph as AGENTS.md says), `ds4_deepseek4_next_image_span`, the
  `ds4_deepseek4_image_token_type` enum (tests/ds4_test.c uses it), the
  shared bicubic resize and `third_party/iris`.

## 2. Removal, one part per batch

- [x] 2.1 B2 CUDA-only code (~3,000 lines; proof linkO1 per function with the `__APPLE__`-false predicate named, M3 for the 11 undefined `ds4_gpu.h` prototypes). Whole functions first, then the scattered `g->cuda_tp_*` blocks only if 1.1 allows them and the saving is real. One `sf-ablate(cuda)` marker per non-obvious cut.
  - Outcome: `ds4.c` 45,510 -> 40,567 (-4,943), `ds4_gpu_mgpu.h` 219 -> 63, `ds4_gpu.h` -370, `ds4.h` -1. Removed: every `g->cuda_tp_*`/`cuda_q*_fuse` flag and the blocks they guarded (decode layer phase, output head, layer FFN batch, alloc/validation), the `metal_graph_cuda_*_requested` predicates, `stage_major` with its stage helpers, `verify_decode2_exact`, `greedy_splitkv_replay_exact` and the split-kv/vec4 argmax path, `output_head_split_top1` and its reader, `tp_ep_finish_reduce`, `encode_mixed_routed_rows`, the decode-island graph capture (CUDA-only), the `engine_*cuda*` helpers, the whole multi-GPU engine placement (`engine_classify_multi_tier`, install, per-device caches, print layout, planner helpers, `gpu_cfg`/`placement`/`multi_tier` engine fields) and its unused `DS4_TEST_HOOKS` entry points, `cuda_tensor_parallel` (option, engine field, CUDA-TP default prefill chunk), the CUDA shims except the three the DeepSeek graph's multi-tier plumbing still names (`ds4_gpu_set_current_device`, `ds4_gpu_tensor_alloc_ptr_on`, `ds4_gpu_tensor_copy_xdev`), `g_gpu`/`g_n_gpus`/`g_gpu_peer_ok`, and 38 `ds4_gpu.h` prototypes declared and never defined (the 11 the proposal counted plus the ones this part freed). The trap held: `metal_graph_cuda_stream_prefill_batch_selected_load` returned true on Apple; the call was dropped and `ok` kept.
  - Method: a partial evaluator folded the constant-false atoms (`g->cuda_tp_*`, the predicates, `cuda_tp_partner_tier >= 0`, `cuda_tensor_parallel`, `gpu_cfg`, `e->multi_tier`) through `if`/`else` chains and `bool` declarations; then a loop compiled the Metal, `DS4_NO_GPU` and `DS4_NO_GPU+DS4_TEST_HOOKS` flavours with `-Wunused-function` and deleted a static function only when every flavour that compiles it reported it unused. Every rewritten condition was reviewed in the diff.
  - Kept on purpose: `g->cuda_qkv_pair` (a Metal switch, true by default; "Names that lie"), the DeepSeek graph's multi-tier plumbing (`g->placement`, `*_by_tier[]`, `metal_graph_set_active_tier_*`): dead on Metal, but removing it rewrites ~100 allocation sites of the graph §B keeps for TP/layer-slice, a follow-up if wanted.
- [x] 2.2 B3 compressed attention (~2,500 lines; proof linkO1 with guard `ds4_layer_compress_ratio() == 0`, then the literal audit for the kernels). Host wrappers, then their kernels in `dsv4_misc.metal`, `dsv4_rope.metal`, `dense.metal`, and their pipeline globals if 100 left any init-only. Within the limits 1.3 sets.
  - Outcome: `ds4.c` 40,567 -> 37,934 (-2,633), `ds4_metal.m` 42,255 -> 40,735 (-1,520), `ds4_gpu.h` -170, `dsv4_misc.metal` 2,610 -> 1,145, `dense.metal` -378, `dsv4_rope.metal` -202, `dsv4_kv.metal` -71. Removed: every GPU `ratio != 0` / `ratio == 4` / `compressed` branch of `metal_graph_encode_layer_attention_batch`, `metal_graph_encode_decode_layer_phase` and `metal_graph_alloc_raw_cap`; the compressed tails of `session_payload_live_tensor_bytes`, `ds4_session_layer_payload_bytes`, `ds4_session_{save,load}_layer_payload`, the GPU parts of `ds4_session_{save,load}_payload`, `spec_frontier_{snapshot,restore,commit_prefix}`, `metal_graph_reset_prefill_state` and `metal_graph_kv_cache_bytes_for_context` (one `sf-ablate(ds4)` marker each); `payload_{write,read}_tensor_span_{f16_as_f32,f32_as_f16}`; the `metal_graph_attn_comp_*` stages, `refresh_ratio4_compressor_state`, the indexer/compressor decode scratch buffers (12 per-tier tensors with their accessors); the ten listed `ds4_metal.m` wrappers plus `ds4_gpu_indexer_scores_batch_tensor`, `ds4_gpu_dsv4_topk_mask_tensor_impl` and `ds4_gpu_matmul_q8_0_kslice_rows_impl` (its branch dropped: the only caller passes `full_low_dim = 0`); 12 pipelines (5 built at init and never dispatched, 7 fetched by name at init only), 6 host and 5 shader argument structs; 18 kernels whose last literal went (literal audit: no `"name"`, `\bname<`, `decltype(name` or format pattern left) and 8 device helpers only they used.
  - Kept: the CPU compressed-attention reference (§B), `ds4_layer_compress_ratio`, `ds4_engine_layer_compress_ratio`, `dist_kv_layer_tensor_bytes`, the `n_comp`/`n_index_comp` u32 header arrays and `payload_{write,read}_tensor_span`, the compressor wrappers `tests/ds4_test.c` calls and `ds4_gpu_indexer_topk_tensor` (Qwen). Snapshot format unchanged: a server `--kv-disk-dir` snapshot of the same 10K-token prompt from main's and this tree's binaries differs in exactly two u64 fields (bytes 24 and 32, the save timestamps); the other 441,709,754 and 482,484,133 bytes of the two files are identical.
- [x] 2.3 B4 image preprocessing (~545 lines; proof linkO0). Keep `ds4_deepseek4_next_image_span`, `ds4_deepseek4_attention_bounds`, `ds4_image_preprocess_qwen4` and `third_party/iris`.
  - Outcome: `ds4_image.c` 1,204 -> 640, `ds4_image.h` 153 -> 93: the 14 listed functions, the two DeepSeek structs and 8 declarations. Nothing outside `ds4_image.c` named them.
- [x] 2.4 B5 small items (~250 lines; proofs: `-Wunused-function` with `DS4_MAYBE_UNUSED` defined empty, in the Metal and `DS4_NO_GPU` builds; linkO0; the literal audit for the kernels; grep for the uninstantiated templates). Before removing a kernel, search `\bname<` and `decltype(name` as well as `"name"`, and the macros that instantiate kernels (`DSV41_ROWS_SPLIT` hid two from 100's first audit).
  - Outcome (-555 lines): `ds4_engine_power`/`ds4_engine_set_power`, `ds4_think_max_prefix`, `ds4_chat_append_max_effort_prefix` (with `ds4.h`); kernels `kernel_get_rows_{q8_0,q4_0,q4_K}_f32`, `kernel_cpy_f16_f16`, `kernel_swiglu_f32`, `kernel_add3_f32`, `kernel_add_rms_norm_mul_f32_4`, `kernel_mul_mv_q8_0_f32_bf16{in,io}`; the uninstantiated `kernel_mul_mv_t_t_4_rows` with its `_impl` and typedef (re-audited after 95's `*_vrows*` rename: the vrows templates are separate and stay); `kernel_mul_mm_id_addr` with its two typedefs and `ds4_metal_expert_address_table`. The V4.1 `kernel_mul_mv_q8_0_f32_rows_impl` overload and the `dsv4_attend_*_as_f16*`/`dsv4_indexer_dot128_shared_q` helpers went in 2.2's helper sweep. The four unused decode-phase locals were CUDA-TP locals and went in 2.1.
  - Deferred: `render_live_tool_tail`, `parse_generated_message_for_response` and the `dsml_decode_tracker_update` `string_value` branch in `ds4_server.c` (deferred to avoid a conflict with 131, which rewrites that area). `dot_iq2_pair_16`/`dot_q2_16`: their only callers are the scalar `#else` fallbacks of the NEON-dotprod quant kernels, so removing them means removing those fallbacks, a B6 decision no cut passed through.
- [ ] 2.5 B6 preprocessor-dead blocks (~300 lines, optional): only where a cut from 2.1-2.4 already passes through. Check with a negative compile, never with a preprocessor-output diff (AGENTS.md trap).
  - Not done: the cuts removed whole `#if defined(__APPLE__)` predicate bodies with their functions, and no remaining B6 block sat inside a cut.
- [x] 2.7 From `100` task 1.2: one `fprintf` probe at the top of `ds4_gpu_mv_ext_name` and of `ds4_gpu_mul_mm_id_map0_name`, then one coverage session each of plain, `--mtp`, vision, steering, `--kv-disk-dir` and `--ssd-streaming` on Q4 (`llvm-cov` is in the Command Line Tools). Remove `kernel_mul_mv_ext_*_r1_{2..5}` and `kernel_mul_mm_id_map0_ne20_{10,16,22}` (about 90 lines) only if no session names them; remove the probes.
  - Probe placed in the two pipeline getters (`ds4_gpu_get_pipeline`, `ds4_gpu_get_mul_mv_ext_pipeline`) so every formed name counted, deduplicated. Sessions on Q4: plain (short and a 10K-token prompt), `--mtp` (code and prose), steering, `--ssd-streaming`, vision, and a server with `--kv-disk-dir` (two identical 10K-token requests, cache stored and hit). Named: `kernel_mul_mv_ext_{f16,f32,q8_0}_f32_r1_2`, `kernel_mul_mv_ext_q8_0_f32_r1_4`, `kernel_mul_mv_ext_q8_0_f32_r1_5`; no `kernel_mul_mm_id_map0_*` at all. Nothing removed: the `r1_{2..5}` family is one switch over the MTP row count, and sessions named three of its four arms; `map0_ne20_10` matches Qwen's 10 experts per token, so "not named in six sessions" is not a reachability proof for it. Probes removed (file restored from the pre-probe copy).
- [x] 2.6 Update `AGENTS.md` ("Names that lie", "Misleading-name traps") with anything a part establishes, and the `dsv4_*` row once B3's kernels are gone.
  - `dsv4_*` row updated; the `ds4_deepseek4_attention_bounds` row corrected (DeepSeek graph's visual mask on the layer-slice path, not the Qwen path); new rows for the compress-ratio helpers and `g_ds4_compress_ratios` (validated, read by nothing; wiring it in would need the removed paths back) and for `g->cuda_qkv_pair`; a trap entry for the true-returning CUDA helper and the multi-tier plumbing left in the DeepSeek graph.

## 3. Gates (after every part)

- [x] 3.1 `make -j8` with no warnings, `make cpu`, and `make test -j8` whose output names its suites (`grep -c '^test:' Makefile` first, StarForge rule 19); `./ds4_test --server`.
  - After each of B2-B5: 0 warnings in both builds, the default binaries link Metal and the CPU flavour keeps its own names, `^test:` = 1, `make test` names the same suites as the pre-change baseline with the same results (only sampling timings differ), `./ds4_test --server` ok.
- [x] 3.2 Kernel tests for any `metal/` change: `make test-qwen4-kernels`, `make test-qwen4-metal-units`, and the `test-metal-*` targets that compile the touched file.
  - After B3 and B5: `all qwen4 kernel tests passed`; metal units 145 PASS lines, identical to baseline. `test-metal-{moe-prefill,dense-mpp,ssd-experts,command-memory}` and `test-mxfp4-metal` pass; every test binary linking the touched objects builds. `test-q8-prefill-variants` fails with `kIOGPUCommandBufferCallbackErrorInvalidResource`, identically on an export of `main` (a543855): pre-existing, not this change.
- [x] 3.3 `tests/model_gates.sh` on Q2 and Q4 (MTP identity and limits, `ds4_test` against its known failures, vision, host paths); read the `PASS`/`FAIL` lines.
  - Q4 after B2, B3, B4 and B5, Q2 on the final tree: `PASS mtp-identity`, `PASS mtp-limits`, `PASS ds4_test`, `PASS vision`, `PASS host-paths`, `model gates: all PASS` every time.
- [x] 3.4 `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout: `PARITY OK`.
  - Run with `SF_CHILD_DIR` pointing at this worktree, against upstream b3f5018: `PARITY OK (10 prompts)` on Q4 (speed -0.5% .. +2.6%) and on Q2 (-0.3% .. +2.6%; prompt 10 resampled to a median of 5, +5.3%).
- [x] 3.5 `python3 speed-bench/ab_bench.py --a <worktree at main> --b . --bitwise`: tokens and logits identical, no metric's pooled CI wholly below zero; startup time measured where a part removes pipelines.
  - Q4 vs main (a543855), 600 s, 24 pairs: correctness PASS (tokens; bitwise). plain decode +0.1% (-0.1..+0.2), prefill 8192 -0.2%, +512 -0.1%, +2048 +0.1%; mtp-code decode +0.1% (-0.1..+0.4), prefill +0.1%, tokens/cycle equal; mtp-prose decode -0.2% (-0.3..-0.1), tokens/cycle equal. Gate not met: mtp-prose decode is consistently below zero. A second mtp-prose run read -0.3% (-1.1..-0.0); `ab_pool.py` over both: -0.26% (95% CI -0.27..-0.23, n=46). Bisected with scratch trees, mtp-prose only, 600 s each: end of B2 -0.0%; B3's `ds4.c` alone -0.0%; B3's `ds4_metal.m`/`ds4_gpu.h` with the old shaders -0.3%. So the shift comes from the host side of B3 in `ds4_metal.m` (wrapper/pipeline/struct removals no Qwen path calls); outputs stay bit-identical. Suspected mechanism, not proven: `ds4_gpu_get_pipeline` looks every name up in `g_pipeline_cache` (an NSMutableDictionary), which now holds 7 fewer entries, or code/data layout. An A/A run on main read -0.0% (CI -11.5..+14.0, one disturbed pair). Left for the owner: accept -0.26% on mtp-prose decode, or keep B3's `ds4_metal.m` part out. Parity's speed check (+/-2%) passes on both quants.
  - Coordinator's recommendation (2026-11-15, owner to confirm at commit): accept. The removed host code is never executed on a Qwen path, so the -0.26% is a layout/lookup side effect of the same kind any unrelated edit to `ds4_metal.m` can move either way; keeping ~1,500 dead lines to preserve it works against the child's purpose (rule 16).
  - Owner accepted the -0.26% mtp-prose decode shift (2026-11-15).
- [x] 3.6 Line counts of the touched files before and after, in the commit message.
