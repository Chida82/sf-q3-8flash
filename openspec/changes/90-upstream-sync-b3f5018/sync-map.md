# Sync map: sf-q3-8flash `main` (765e9a5, base fc80bd6) -> upstream b3f5018

Read-only analysis, 2026-11-13. No build, test or model run was done. "Verified" means
the source text was compared (normalised 3-way diff fc80bd6 / child `main` / upstream
`b3f5018`); "claimed" means only the upstream commit message says so. Every
"claimed bit-exact" item still has to pass the child's kernel tests and the parity
oracle.

Range: 267 commits (236 non-merge). 68 non-merge commits touch Qwen text; the rest
are DeepSeek V4.1 / GLM / CUDA / ROCm / DSpark work, some of which edits shared files
the child keeps.

## 0. Answers to the three questions that decide the sync

1. **Does upstream have the change-82 fix (MTP greedy == plain greedy)? No.**
   Verified at b3f5018:
   - `ds4_session_qwen4_spec_cycle` still sets `g->verify_rows_exact = deep`
     (only 3-row verify), not `true`.
   - The 3-row attention is still the 2/1 sub-batch split, now moved into the new
     `qwen4_graph_attention_core_rows`. Upstream has neither `qwen4_verify_attention_rows`
     nor `qwen4_attention_rows_core`.
   - `ds4_gpu_qwen4_hc_gate_mix_tensor` still takes the pair kernel for every T=2
     batch (`pair = n_tokens == 2u && getenv(...)`), so 2-row verify uses the pair
     mixer.
   - There are no `kernel_mul_mv_q8_0_f32_r2/r3` and no `kernel_mul_mv_f16/f32_f32_4_r2/r3`,
     and the Q8_0 legacy and F32 matvecs still take `n_tok == 1` only.

   So upstream `--mtp` can still leave plain greedy output. Also, after cd1c550 the
   upstream predictor gets zeroed history on resident runs, so upstream's drafts
   (and so its verify-batch pattern) are no longer the ones the child sees.
2. **Does upstream change plain-path Qwen logits relative to fc80bd6?** Not by
   intent. Every candidate claims to preserve arithmetic:
   - 37f66ba restores the 0aaea5a resident prefill arithmetic after the PR's
     chunk-invariant detour (0024ca0/2d6a207/89986c3).
   - a279860 makes streamed use resident arithmetic.
   - #1238 is titled "bit-exact".
   - 1c6d058, 2960711 and 6b7cb44 each claim matching logits.

   The text diffs confirm order-preserving rewrites for b5aedb9, 6605c3c, f768d14,
   b3f5018, the shared-Q8 helpers and the NAX prefill bodies. They cannot prove the
   fused-reduce kernel (4ed25e4) or 028b43f (see below). **This is the one thing to
   measure before merging** (decision D1).
3. **Can both parity constraints hold?** Only if (2) holds. The two constraints are
   "token-identical to upstream at the new merge-base" and "child plain bit-identical
   to its previous build". If upstream's plain output moved, they contradict each
   other, and a human must pick which baseline wins.

## 1. #1056: commits the child already judged (head 4642526 in docs/upstream-prs.md)

Relation is upstream's final state at b3f5018 compared with the child's `main`.

| Upstream | What | Child counterpart | Relation | Merge resolution | Logit risk | Risk |
|---|---|---|---|---|---|---|
| e37f185, 85d37ae, d6cbc77, 81b9ebb, 5cbdb6e (SSD part), 2ba92ab, e2b4a47, 9e1429b, 47ca2eb, 81ee4ba | Bounded SSD expert streaming: expert cache, admission, I/O overlap, eviction planning, compact dispatch, MTP staging, memory budget | `cf74f17` (80): `qwen4_stream_*`, `ds4_gpu_stream_expert_cache_*`, `qwen4_streaming_memory_*`, function constant 906 on all 11 routed kernels | **identical** for 14 Metal host functions (`qwen4_stream_read_layer/selected/range/overlap`, `qwen4_moe_dispatch_slots`, `qwen4_moe_mm_copy_active/dispatch_experts`, `ds4_gpu_stream_expert_cache_plan_reuse/prepare_selected_batch/take_planned_reuse`, reuse heap, `qwen4_bind_experts`, `ds4_gpu_qwen4_moe_build_lists_tensor`); `qwen4_streaming_memory_budget/staging_bytes` identical; **divergent** `ds4_gpu_qwen4_moe_stream_tensor`, `qwen4_stream_mid_before_read`, `qwen4_stream_missing_gate_up_ready`, `qwen4_streaming_memory_admit`, `qwen4_graph_memory_estimate`. Constant 906 is the same id (`qwen4_expert_addresses`) on both sides | Take upstream for the identical part (it is a no-op). In the five divergent functions, start from upstream and re-apply the child's deltas: hand-ported `81ee4ba` admission, 906 on all routed kernels. Re-run `tests/test_qwen4_ssd_experts.c` and the streamed-vs-resident check | Resident: none if 906 stays off when not streaming. Streamed: must stay token-identical to resident | medium |
| cdfc0d5 (HC part) | HC gate-mix reuse kernel `kernel_qwen4_hc_gate_mix_f16_reuse` | `7034f14` (40) | kernel body **identical**; **dispatch divergent**: upstream runs reuse only under `ds4_gpu_qwen4_legacy_tuning()` (M1-M4, nsg 16), the child runs it on M5 for one decode token | Combine: keep the child's M5 single-token branch and add upstream's legacy branch | none (verified byte-exact against `_pf` in 40) | low |
| cdfc0d5 + 13c53d9 (IQ2 part) | `kernel_qwen4_moe_mid_iq2` (NR1/NR2) | `d242114` (70) | kernel **equivalent**: the only difference is the shared-Q8 helper (`qwen4_moe_shared_q8_mid` in the child, `qwen4_q8_pair_dot` upstream), whose arithmetic is verified identical. **Dispatch divergent**: upstream uses it only on legacy devices (`iq2 = ... && ds4_gpu_qwen4_legacy_moe_tuning()`); on M5 upstream takes the new `kernel_qwen4_moe_mid_iq2xxs` (47c34fb) | Take upstream's kernel text and helper (`qwen4_q8_pair_dot`, so the child-only helper goes). The M5 dispatch is decision D4 | none from the kernel text | medium |
| 13c53d9 (shared Q8 loop) | shared Q8 gate/up in Q4_K per-token mid | `53dcad6` (50): `qwen4_moe_shared_q8_mid` inside `qwen4_moe_mid_q4k_pass` | **equivalent** (same four-term expression and lane map). The child refactored `qwen4_moe_mid_q4k_pass` to take `pairs/pair_stride`, upstream to take `list/ebase` (SSD address table) | Take upstream's signature (it carries `ebase` for streaming) and keep the child's per-token caller | none | low |
| 9a8462a + 5cbdb6e (Q2_K down) | `kernel_qwen4_moe_down_q2k`, shared Q8 row reuse | `d242114` (70): `kernel_qwen4_moe_down_q2k` + `qwen4_q2k_block_rows` + `qwen4_moe_shared_q8_rows` | **equivalent**: same 8-element FP32 chain, `simd_sum`, packed loads. Child reads the scales as two `half`, upstream as `packed_half2` (same values). **Dispatch divergent**: upstream only on legacy devices with grid `rows_per_tg`; child on M5 with grid `(out_dim+7)/8`, 128 threads | Take upstream's kernel text. The M5 dispatch is D4 | none | medium |
| 496b153 (tails) | remainder tiles | `08ea4d7` (60) tails on M5 for Q4; `eda305c` (81) low-bit tails on M5 | **divergent policy**: `qwen4_moe_mm_tails` upstream = M5/M6 for types 12/39 only; child = M5 for 12/39/16/10 (owner-approved trade-off in 81). Child's extra `kernel_qwen4_moe_mm_{mid,down}_nax16/nax8` instantiations are child-only | Keep ours (81 is an owner decision), widened to `ds4_gpu_device_is_m5_or_m6_apple_silicon()` | none (tails bit-identical) | low |
| b86c8ae, 92f57fc, 089d966, a6ad636 | MTP prefix caches, predictor tail state, `DS4_QWEN4_MTP_PREFILL`, replay diagnostics | `30-mtp-cycle` (59c6488..fe126d3): `qwen4_graph_mtp_prime/priming/tail_flush`, cache-only priming | **divergent design**. Upstream: `mtp_tail_R` pending-row model, `qwen4_graph_mtp_cache_steps/cache_cold/boundary/project/input`, `kernel_qwen4_mtp_project_q8*`. Child: #1062 `acce8da` priming in every trunk encoder | Keep ours (D2). Do not merge both priming designs. Delete upstream's `qwen4_graph_mtp_cache_*` / `mtp_project` path and its kernels with `sf-ablate(mtp)` markers, or keep it only if it is reachable through `DS4_QWEN4_MTP_PREFILL` and someone decides to own it | MTP drafts only. Greedy output is safe while 82 is kept | **high** (largest conflict zone: `qwen4_graph_forward_tokens` 169 differing lines, `qwen4_graph_mtp_steps` 91, `ds4_session_qwen4_spec_cycle` 104) |
| 2960711 | skip indexer queries for dense-only prefill chunks | none (registry: `open`) | **new to child**: `qwen4_attention_needs_index_query`, used in `qwen4_graph_attention_cache` | Take. It is Metal-only, MTP keeps the full prep, and crossing chunks keep the full projection | low (claimed, and it changes only which output of the fused gemv is written) | low |
| 028b43f | "stabilize Qwen HC arithmetic", M6 tuning | dropped by the child (its `_pf` already spells the F16 order) | **upstream-ahead / possible arithmetic change**: `kernel_qwen4_hc_gate_mix` (F16) now forces `x=l*(1/hc); t=x*w; u=t*sigmoid(x)` with `reassociate(off) contract(off)`, and `kernel_qwen4_hc_gate_mix_pair` (F16) uses an explicit `fma`. Upstream's intent is to pin what the fast-math compiler already emitted | Take, then run the `tests/test_qwen4_kernels.c` byte-exact pins (plain vs `_pf` vs reuse) and the parity oracle. If the plain kernel moves, the child's prefill (T>2) and the per-row verify mixer move with it | **possible** (HC mixer of prefill rows and of 82's per-row verify) | medium |
| a50fecc, 04c0867, 9bff1ca, 0024ca0, 2d6a207, 89986c3, 11811b9, fd0c24a, bbbc012, a37fd7f, 4642526 | dropped by the child | none | after 37f66ba/a279860, upstream's resident path no longer carries the chunk-invariant policy. 11811b9's half-operand split survives (`kernel_qwen4_moe_mm_*_f16*`) for large SSD batches and M1 | Take as upstream code. On M5 resident these paths are not selected (check `qwen4_moe_mm_*` selection after the merge) | none on M5 resident if the gates hold | low |

## 2. #1056: commits new to the child (after head 4642526, merged in 4ef9e4d)

| Upstream | What | Child | Relation | Resolution | Logit risk | Risk |
|---|---|---|---|---|---|---|
| ee79f22 | MXFP4 prefill staging with packed loads; NR2 batched MXFP4 down rows (function constant 907, M1) | 60 changed `qwen4_load_raw16` MXFP4 to aligned-word loads | **divergent loads, same dequant**. Upstream keeps `r.m[17]` bytes; child uses `r.q`/`r.h.x` words | Combine: keep the child's load (measured in 60) and take upstream's 907 pair rows (legacy only) | none (load-only) | low |
| b96a12b, 0231312 | M1 Q4 SSD K32 NT4 kernels; M1 tuning extended to M2-M4 (`ds4_metal_device_name_uses_qwen_legacy_*`) | none | **new to child**; not on M5 | Take (TP/other devices still run the child) | none on M5 | low |
| 37f66ba | restores fc80bd6-era resident prefill arithmetic; adds `tests/test_qwen4_resident_arithmetic.c` + misc/ research | child never left it | **equivalent end state** | Take the code and the test. misc/ is removed again by 5c9ed63 | none | low |
| f32a16a, 575369b | research dumps under `misc/` | — | removed by 5c9ed63 | take the deletion (net zero) | none | low |

## 3. Post-merge fix-ups by antirez (2026-11-03)

| Upstream | What | Child | Relation | Resolution | Logit risk | Risk |
|---|---|---|---|---|---|---|
| c942a90 | restore predictor scratch views after the fused down-reduce path | — | follows 4ed25e4 | take with 4ed25e4 (D4); without it, drop | MTP state | medium |
| afd33ef, 2cd0ae7 | M5 tuning beside the streamed path; M6 separate from DS/GLM; `DS4_MAYBE_UNUSED`; `ds4_gpu_device_is_m5_or_m6_apple_silicon` | 80 | **upstream-ahead** (helper renames used across Qwen dispatch) | take. Rename the child's `m5_single` etc. to the upstream names to cut conflicts | none | low |
| a279860 | streamed experts use resident projection, attention and shared-expert reductions; `tests/test_qwen4_generation.c` | 80 already token-identical streamed == resident | **equivalent goal**, different code (upstream removes the SSD-only legacy policy 37f66ba had scoped there) | take upstream's structure. Re-check that the child's 906 path and the resident path stay bitwise (the child's 80 acceptance test) | streamed only | medium |
| 7bba0f7 | Qwen payload **v3** (`0x51573803`, stores the MTP prefix and pending trunk row), reads v2 | child writes and reads v2 (`0x51573802`) | **upstream-ahead, depends on 92f57fc's `mtp_tail_R`** | D3: keep v2 (the child's home `~/.sf/q3-8flash` never shares checkpoints with ds4). If v3 is taken, it is a format change and needs the save/load, rewind, truncated-input and reuse tests in AGENTS.md | none | medium |
| cd1c550 | `DS4_QWEN4_MTP_PREFILL=auto` -> history only when streaming; resident gets zeroed predictor history | child primes always (30, +8.3% MTP decode on code) | **divergent policy** | D2: keep ours. If the knob is kept, default `on` | drafts only (and upstream's MTP greedy, because upstream lacks 82) | medium |
| 0dbfd05, 5e3a344 | test housekeeping (CUDA split, compact-dispatch test widths) | child has `test_qwen4_moe_mm_compact.py` | take 5e3a344 (the test matches the K-tile template argument); 0dbfd05 is CUDA-only | none | low |
| b3f5018 | `qwen4_row_dot` Q2_K: packed `uchar4` loads (fixes a3a7e2d's word-aligned read on half-aligned rows) | child `qwen4_row_dot` uses byte loads; child `qwen4_q2k_block_rows` uses `packed_uchar4` | **child already correct**. The bug only came with a3a7e2d, which the child never took. Upstream's final `qwen4_row_dot` is order-equivalent to the child's | take upstream's text (it brings b440c3c's F32 unroll too) | none | low |
| 5c9ed63 | delete `misc/qwen-*` research dumps | — | — | take | — | — |

**Alignment watch item:** ef8e536 (below) adds a Q2_K branch to `qwen4_load_raw16_next`
that reads `uint` words. b3f5018 fixed the same pattern only in `qwen4_row_dot`. Q2_K
rows of the 640-wide down projection are 4-aligned when the row is the full 3-superblock
row, but b3f5018's tests use "sliced" and "address-table" rows that start two bytes
into a word. Before taking ef8e536, confirm that MM prefill never sees a half-aligned
Q2_K row (TP slices, SSD cache slots). If it can, port it with `packed_uchar4`.

## 4. #1238 (paradise-runner, "faster Metal decode (bit-exact)", merged 95976d7). Not in the registry

| Upstream | What | Child | Relation | Resolution | Logit risk | Risk |
|---|---|---|---|---|---|---|
| 47c34fb | new `kernel_qwen4_moe_mid_iq2xxs` (grid/sign tables in threadgroup memory, `qwen4_iq2xxs_row_dot_tg`); upstream M5 default unless streaming | child M5 = `kernel_qwen4_moe_mid_iq2` (70) | **competing kernel for the same M5 slot** | D4 | claimed exact | medium |
| fd16a72 | `qwen4_moe_mv_specialize` true for IQ2/Q2_K on M5 | child 70 deliberately kept M5 to MXFP4 only ("its IQ2_XXS and Q2_K rows run their own kernels") | **divergent** | D4 | none (specialization keeps order) | low |
| 4ed25e4 (+6946209 naming, c942a90) | `kernel_qwen4_moe_down_reduce`: T=1 Q2_K down + weighted reduce + HC update in one kernel; `DS4_QWEN4_NO_DOWN_REDUCE` | child: `kernel_qwen4_moe_down_q2k` + separate reduce | **competing**. Text: per-slot `qwen4_row_dot`, then `o = Σ w[s]*part[s]` in slot order, then `+ sigmoid(g)*shared`, then `R[s] += wgt[s]*o`. This matches `kernel_qwen4_moe_reduce` only if that kernel uses the same order and the same `qwen4_hc_inject_weight` (not checked line by line) | D4. If taken, add a byte-exact test against down_q2k + reduce | **must be tested** | medium |
| a3a7e2d (+b3f5018) | Q2_K row dot word loads | child byte loads | resolved by b3f5018; equivalent | take the final text | none | low |
| b440c3c | F32 row dot `#pragma unroll 4` | — | order-preserving (verified text) | take | none | low |
| b5aedb9 | `kernel_qwen4_hc_norm` and `qwen4_hc_inject_weight`: loads issued ahead, sums in the same order | — | verified order-preserving (same element sequence) | take | none | low |
| f768d14 | attention decode NSG 4->6, HPS 3->2 | 82's verify rows use the rows kernels | per-head arithmetic unchanged (claimed). The heads-to-simdgroups map moves, and each head is folded by one simdgroup | take. Re-run the 82 identity test (`tests/test_qwen4_mtp_identity.py`), because the rows kernels and the decode kernel must still agree | claimed none | medium |
| 6605c3c | merge: split maxima loaded 16 at a time | — | verified order-preserving (`max` in split order) | take | none | low |
| 9000fb7, 0f12ea4 | HC norm prefetches the down projection into the system cache | — | memory hint only | take | none | low |
| 6b7cb44 | router reads a BF16 copy of BF16-valued F32 rows (`dense.metal`) | — | exact only if every router weight is BF16-representable (claimed). Costs a weight copy in RAM | take after one check that the GGUF router tensors are F32-holding-BF16 on both packs | low (if the assumption fails, logits change) | medium |
| d2ae13e, 6946209 | PLE n-gram reads overlap layer 0; `DS4_QWEN4_NO_PLE_OVERLAP` | child decode PLE path (`qwen4_ngram_read` child-changed) | host scheduling; conflicts with the child's `qwen4_ngram_read` edits | take, keeping the child's change | none | low |

The registry gets a new `#1238` block. #1238's speedups are measured on M5 Max:
the "speedup" figures in its commit messages run cumulatively, from 50.98 to about
60 t/s. If upstream's M5 decode is now faster than the child's, the parity speed
gate (>2% loss) fails even though the tokens are identical. That is why D4 is
not optional.

## 5. Other Qwen commits outside #1056 and #1238

| Upstream | What | Relation | Resolution | Risk |
|---|---|---|---|---|
| e73e516 (#1198, Matthijs van den Bos) | Q4_K raw-load reuse in NAX prefill (`qwen4_load_raw16_next`, Q4_K branch) | **both-new-differ**: the child's 60 has a `qwen4_load_raw16_next` with an extra `nb` parameter. Its Q4_K branch is textually identical to upstream's | Combine into one function: upstream signature + the child's MXFP4 word loads + upstream's Q2_K branch (watch item above) | low |
| ef8e536 | Q2_K bit-plane reuse in prefill staging | new; see the alignment watch item | take after the alignment check | medium |
| 347c2e1, 64baaa0 | PLE reads overlap prefill GPU work (`qwen4_ple_prefetch_run`, `qwen4_graph_stage_ple`); `tests/test_qwen4_ple_prefetch.c` | new | take | low |
| c97964b | validate token ids before prefetched staging (trust boundary) | new | **take** (AGENTS.md: never weaken validation) | low |
| 1c6d058 | BF16 prompt embeddings gathered on the GPU (`qwen4_graph_stage_embeddings`) | new, conflicts with the child's `qwen4_graph_stage_inputs` (child 4 lines, upstream 46) | take. Claimed exact (matched saved state and logits) | medium (prefill input path; parity decides) |
| 32604bc, b7615c1 | CUDA Qwen Q8 | removed area | drop (`ds4_qwen4_cuda.cuh` is not in the child) | none |
| #1115 f5e419d / c544020 | Qwen template rendering fix | **did not land**: no matching subject in `fc80bd6..upstream/main`, and upstream has no `tests/test_qwen4_reasoning_retention.py` or `tests/template_parity_ab.py`. The PR is still open | stays "next sync -> not in upstream"; port it separately if wanted | — |
| #1062 (acce8da etc.) | MTP priming the child adopted | **not in upstream** (PR still open) | the child stays the only holder of the priming; see D2 | — |

## 6. Removed-area commits that touch code the child keeps

| Upstream | Shared code touched | Qwen reaches it? | Resolution | Risk |
|---|---|---|---|---|
| d95f8b6, 0ac42d6, 26335c7, b66c926, 55b1e75, a6b50ff, 262b4a6, 9f3892d, d8d1523, 5a588db, 7d9903b (V4.1) | `metal/dense.metal`: `helper_mv_reduce_and_write<NR0, ROUND=false>`; `kernel_mul_mv_q8_0_f32_impl` is now a wrapper over `kernel_mul_mv_q8_0_f32_rope_impl<..., ROUND, ROUND_IN, ROPE_*, HC_OUT=false>`; `kernel_mul_mv_t_t_4_impl<..., ROUND=false>` | **yes**: these are Qwen's T=1 Q8_0/F16/F32 projections | Take. Verified: with the defaults the loop and reduction are textually the fc80bd6 ones, so arithmetic is unchanged | low |
| same V4.1 series | `dense.metal` defines `kernel_mul_mv_q8_0_f32_rows_impl` and `kernel_mul_mv_t_t_4_rows(_impl)`: **the same template names as the child's 82 kernels**, with different parameters (`<NR0,args_t>` upstream, `<NR0,NR1>` child) | name collision, a compile error if both stay | Rename the child's 82 templates (e.g. `_vrows`), keeping the host names `kernel_mul_mv_*_r2/r3`, or see D5 | **high (build break)** |
| V4.1 exact-rows | `ds4_gpu_matmul_f16_tensor_impl(..., exact_rows, round_bf16)`: with `exact_rows` and 2..8 rows it now selects `kernel_mul_mv_f16_f32_4_rows` (one weight walk, per-row K walk and reduction, claimed) | **yes**: the child's 82 passes `exact_rows = g_qwen4_verify_rows_exact && n_tok <= 3` | Conflict in the same lines as 82's `ds4_gpu_mv_rows_name`. See D5 | high |
| V4.1 rounding | `dsv4_hc.metal` (`kernel_dsv4_hc_expand*`: `args.round_block_in`, `args.round_bf16`), `flash_attn.metal` (`ds4_flash_attn_vec_reduce_row` gains a pointer argument), `norm.metal`, `moe.metal` | DeepSeek graph only (kept for TP plumbing); Qwen uses `kernel_qwen4_hc_*` | Take kernels and host argument init together (the new arg fields must be zero) | low |
| 82aa7e8, 4ff3af6, 01772c0, af7c02b | `argsort.metal` top-k | not reached (Qwen uses `qwen4_idx_radix`; registry #959 note) | take | none |
| 345d7f4, e4709b4, db67455, c2779bb, efd018c, 46ade1b, 4f80638 | `dsv4_misc.metal` indexer/GLM kernels | GLM/V4.1 only | drop the GLM parts per the child's ablations; take the V4 helpers that remain referenced | low |
| a4c922c, 381808d | `ds4_metal.m`: autorelease around `contents`/read/write (session leak on `/ctx`) | **yes**, generic | **take**, and its test `tests/test_metal_command_memory.c` | low |
| 9fe88cd, 890898c | per-model Metal weight policy chosen after the GGUF family is validated | generic open path | take (V4.1 branch is dead in the child; keep the ordering fix) | low |
| c71ca56 | `metal_graph_prefill_layer_major` overlap | DeepSeek graph only | take or drop with the rest of that function's ablation | none |
| a8ce74a | server: whitespace-only reasoning parsed as absent (all renderers) | **yes** (Qwen chat) | take (prompt bytes change only for clients that send blank reasoning) | low |
| f5127df, 67f2ca9 | server: 256 images per request; advertise modalities | yes (vision child) | take | low |
| 7da9535 + cad7933 | idle prefill quantum = engine prefill cap, then limited to `ds4_engine_is_deepseek41` | dead in the child | drop with `sf-ablate(server)`, or keep the field at 2048. Registry #1118 stays `open` | none |
| b799c90, 2768d0e | `ds4_image.c` parallel bicubic rows (bit-identical claimed); `third_party/iris/jpeg.h` SOS validation | yes (vision, server trust boundary) | **take both** (2768d0e is a memory-safety fix on request images) | low |
| 187f46b | `ds4-bench` per-step decode logits hash/dump | yes | take (useful for D1) | low |
| e14d7f8 | `ds4_test` closes cached engines between tests | yes | take, then re-baseline `docs/TESTING.md` | low |
| cef4a4d, c548410, 724336c, 52780d4, cbb6874 | `ds4_tp.c/h`, TP residency | TP plumbing kept (SPEC §B) | take the generic parts; drop the V4.1-specific ones | low |
| Makefile, `.gitignore`, `download_model.sh`, `tests/test_model_download.py` (a101246, 5379c1c) | — | — | keep the child's download path. After resolving the Makefile, check `grep -c '^test:' Makefile`, the `-cpu` binary names (rules 18/19) and the new test targets below | medium |

New upstream Qwen/Metal tests the child does not have yet:
`test_metal_qwen4_{hc,moe_down,moe_half,moe_mid,mxfp4_stage}.m`,
`test_metal_q8_{gemv_reference,reduction}.m`, `test_metal_device_policy.c`,
`test_qwen4_{generation,mtp_policy,mtp_prefill,ple_prefetch,resident_arithmetic}.c`.
Several of them pin upstream's M5 dispatch (iq2xxs, down_reduce), its MTP design
(mtp_prefill/policy) and v3 payloads. Each must be taken, adapted or removed to
match D2-D4, never left failing.

## 7. Conflict hot spots (for the human resolving the merge)

- `metal/qwen4.metal`: `kernel_qwen4_moe_{mid,down}_q2k/iq2` (text equivalent, take
  upstream), `qwen4_load_raw16(_next)` and `qwen4_dequant_raw16` (combine),
  `qwen4_moe_mid_q4k_pass` (take upstream's signature), the MM `_nax_t`/`mm_mid`/`mm_down`
  bodies (upstream only adds expert-address/empty-expert lines; arithmetic
  unchanged), `kernel_qwen4_mtp_stage/combine` and `kernel_qwen4_argmax` (child-changed
  by 30; keep ours).
- `ds4_metal.m`: 10 Qwen dispatch functions changed on both sides
  (`ds4_gpu_qwen4_hc_gate_mix_tensor`, `..._moe_{mid,down}{,_grouped}_tensor`,
  `..._moe_mm_{mid,down}_tensor`, `qwen4_dispatch_resident`, `qwen4_moe_mm_tails`,
  `qwen4_moe_mv_rows`), plus 82's three matvec sites (`ds4_gpu_matmul_q8_0_legacy_tensor`,
  `ds4_gpu_matmul_f16_tensor(_impl)`, `ds4_gpu_matmul_f32_tensor`).
- `ds4.c`: 17 Qwen functions changed on both sides. The MTP/forward core is the
  dangerous part: `qwen4_graph_forward_tokens`, `qwen4_graph_moe`, `qwen4_graph_mtp_steps`,
  `ds4_session_qwen4_spec_cycle`, `qwen4_graph_attention_tail`, `qwen4_batch_mtp_drafts`,
  `qwen4_session_{load,save}_payload`, `qwen4_graph_stage_inputs`. In
  `qwen4_graph_attention_tail`, upstream moved the pre-82 2/1 split into
  `qwen4_graph_attention_core_rows`. The child's
  `if (g->verify_rows_exact && T > 1u) return qwen4_verify_attention_rows(...)`
  must be re-applied on top, and the 2/1 split deleted. Otherwise 82 silently
  reverts for T=2 while still compiling.
- rerere has no recorded resolution for any of these (first sync over #1056).

## 8. Decisions a human must take

**D1. Gate the sync on a pre-merge plain parity run.** Build upstream b3f5018 and run
the parity prompts (plain lines) against the current child `main` on both packs.
Use `ds4-bench`'s new logits hash (187f46b) if it helps.
*Recommendation:* do this before opening `sync/b3f5018`. If the tokens match, both
parity constraints can hold and the merge proceeds. If they differ, an upstream
change moved Qwen arithmetic. Bisect among 028b43f, 1c6d058, 2960711, 6b7cb44,
4ed25e4, f768d14 and b5aedb9, and decide which baseline wins before resolving
anything.

**D2. MTP design: keep the child's (30 priming + 82 exact verify), not upstream's
(92f57fc tail state + 089d966/cd1c550 zero-history default + 7bba0f7 v3).**
*Recommendation:* keep ours. Upstream still lacks 82, so taking its verify path
brings back the measured MTP != plain divergence. Its resident default discards
the priming that gave MTP decode +8.3%. Ablate the unused upstream MTP-prefill
machinery with markers. For the parity file's `--mtp` line, compare the child
against **upstream plain** for that prompt (or accept an MTP-line mismatch as
expected), because upstream `--mtp` is no longer a valid reference for exactness.

**D3. Snapshot payload: keep v2 or adopt v3.**
*Recommendation:* keep v2 and leave a marker that v3 exists. v3 only exists to carry
92f57fc's pending trunk row, which D2 rejects. The child's home and checkpoints are
never shared with ds4, so no cross-binary compatibility is lost. If v3 is wanted
later, it is a separate change with the four snapshot tests.

**D4. M5 Q2 decode path: the child's 70 kernels (`mid_iq2` + `down_q2k` + separate
reduce) against upstream #1238 (`mid_iq2xxs` + `mv_specialize` for IQ2/Q2_K +
fused `down_reduce`, with c942a90).** Upstream now restricts the 70-equivalent
kernels to M1-M4.
*Recommendation:* resolve the merge with the child's M5 dispatch (known
bitwise-exact). Then, still on the sync branch and before parity, A/B the #1238 M5
path with the bench harness. Take it if it is faster and passes a byte-exact kernel
test against the child's kernels and the 82 identity test. Otherwise the parity
speed gate can fail against a faster upstream.

**D5. dense.metal collision with 82.**
*Recommendation:*
- F16: drop the child's `kernel_mul_mv_f16_f32_4_r2/r3` and let `exact_rows` take
  upstream's `kernel_mul_mv_f16_f32_4_rows`. Before that, prove it byte-exact against
  single rows with 82's kernel test; this takes the most divergent code out of the
  child.
- Q8_0 and F32: keep the child's r2/r3 (upstream has no equivalent on the Qwen path),
  renaming its templates so they do not clash with upstream's V4.1
  `kernel_mul_mv_q8_0_f32_rows_impl` and `kernel_mul_mv_t_t_4_rows`.

**D6. 028b43f HC F16 order pinning.**
*Recommendation:* take it, since it makes the plain/`_pf`/reuse/per-row equivalence a
language guarantee instead of a compiler accident. Accept it only if the child's
kernel byte-exact pins and D1 pass. If it moves logits, report that upstream changed
arithmetic. Do not hide it with a child-side revert.

**D7. Low-bit remainder tails on M5 (81).**
*Recommendation:* keep ours. That is the owner's recorded trade-off. Upstream's M5/M6
policy keeps tails for Q4 only, so this stays a child delta with an `sf-keep` note.

**D8. Registry and #1115.**
*Recommendation:* in the same branch, add a #1238 block and verdicts for ee79f22,
b96a12b, 0231312, 37f66ba, a279860, cd1c550, 7bba0f7 and b3f5018 to
`docs/upstream-prs.md`. #1115's template fix did **not** land; keep it as a separate
follow-up and do not fold it into this sync.
