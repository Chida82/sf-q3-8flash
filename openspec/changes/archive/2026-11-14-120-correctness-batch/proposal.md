# Proposal

## Why

The 2026-11-13 upstream review found small correctness fixes in open PRs that
reach this child and are not in `upstream/main`, so no sync brings them. Each
claim was checked against the source on 2026-11-14 (`main` `765e9a5`, and
`upstream/main` `b3f5018` where the sync rewrites the code). One claimed fix
was dropped, and one narrowed, because the cited code does not reach Qwen.

| PR / commit | Defect | Check on 2026-11-14 |
|---|---|---|
| #1326 `7b0e2aa` | `ds4_prompt_prefix_append` pushes EOS after an imported assistant turn. `qwen4_chat_close` already wrote `<\|im_end\|>` (the Qwen EOS, `ds4.c:29722`) plus a newline, so the turn closes twice. Affects `--prefix-file` only | **confirmed**: `ds4_prompt_prefix.h:44` pushes unconditionally; callers `ds4_cli.c:463` and `:1383` |
| #1156 `f63ae1d` | GGUF type table: `iq1_s` 256/110 should be 256/50; `iq4_nl` 256/50 should be 32/18. A third-party GGUF with iq4_nl tensors is sized at about a third | **confirmed**: `ds4.c:2086-2087` |
| #1126 `242da6b` | The queue keepalive thread calls `ds4_gpu_get_pipeline`, which reads and writes `g_pipeline_cache` (an `NSMutableDictionary`, no lock) while the main thread compiles pipelines | **confirmed**: `ds4_metal.m:11270`; start sites `:2363`, `:11253` |
| #1125 `a6fc294` | `clear_layer` forces the per-layer count to 0 although `clear_entry` skips in-flight entries, so the count drifts below the live entries | **confirmed and reachable**: `ds4_metal.m:16858`, called on `prepare_selected_batch`'s error paths, which `ds4_gpu_qwen4_moe_stream_tensor` calls |
| #1125 `a0fe413` | A slab slot that leaves the free list is lost when its lock fails, and on other load error paths | **confirmed in part**. Reachable: the failed lock in `alloc_slab_slot`, through `prepare_load_buffers`. The child's `prepare_selected_batch` already returns uninstalled reservations on its `gate_up_ready` path. The `load_selected_missing`, `get_protected` and pending-load parts are **not reachable from Qwen** |
| #1125 `6c41f9b` | `prune_global` spins on an in-flight coldest entry | **dropped**: its callers are the DeepSeek graph's seed paths and `ds4_gpu_routed_moe_one_tensor`, on `main` and on `b3f5018`. Qwen never calls it |
| #1145 `4fbba5d` | `model_find_tensor` is first-match and nothing rejects a GGUF that repeats a tensor name, so one weight can bind two roles. The missing-tensor error does not name the file | **confirmed**: no duplicate check in `parse_tensors` (`ds4.c:2389`); message at `ds4.c:3717` |
| #1128 `ad14a5f` | The indexer block-key kernels rope into `float tmp[64]` with `rope_freq[32]`. Nothing bounds `n_rot` to 64 or requires it even | **confirmed, latent**: the host checks at `ds4_metal.m:40452` and `:40750` test only `n_rot > idx_dim`; `n_rot` is 64 in the shipping model |
| #1128 `fa7bc8a` | The selector gets `g->tile_max` for every `n_sparse <= 2` batch, but only the vector scorer writes it. A shape outside the vector scorer's limits would select from stale maxima | **confirmed, latent**: `ds4.c:32412`/`32415`, `ds4_metal.m:40485`; the shipping shape (4 heads × 128) is inside the limits |

The #1128 commits `d7b0b31`, `82ffb0c` and `3cbbb19` and the #1125 commit
`2cf7986` are not reachable from Qwen (registry).

## What Changes

One step per fix, each ported by hand onto the synced tree, in the order of
the table:
- **#1326:** Qwen is the only model, so `ds4_prompt_prefix_append` stops
  pushing EOS after assistant turns. A model-backed `ds4_test` entry counts
  one close per turn.
- **#1156:** correct the two entries. A model-less `ds4_test --gguf-types`
  checks every quantized type's block geometry against ggml's block structs.
- **#1126:** resolve the keepalive pipeline on the starting thread, before
  `pthread_create`. Both keepalive threads use that copy.
- **#1125:** `a6fc294` whole (the forced reset goes, and victim scans skip
  empty layers); `a0fe413`'s `slab_claim_slot` (a slot whose lock fails goes
  back on the free list). The rest of `a0fe413` and all of `6c41f9b` are not
  ported.
- **#1145:** refuse a GGUF with a repeated tensor name, naming the file and
  the tensor; name the file in the missing-tensor error. A model-less test
  writes a header-only GGUF fixture and checks both messages in a forked child.
- **#1128:** the two guards (`n_rot > 64 || n_rot % 2`) and
  `ds4_gpu_qwen4_idx_score_emits_tile_max()`, with negative-call checks in
  `tests/test_qwen4_kernels.c`.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none) These are defects against behaviour the code already intends. No
specified capability covers GGUF loading, prompt-prefix import or pipeline
caching. The SSD fixes keep `ssd-streaming` as specified (bounded cache,
streamed tokens identical to resident). Each fix gets a test that pins it.

## Impact

- `ds4_prompt_prefix.h`, `ds4.c` (type table, tensor directory, idx
  selector), `ds4_metal.m` (keepalive, stream expert cache, idx guards),
  `ds4_gpu.h`, `tests/ds4_test.c`, `tests/test_qwen4_kernels.c`,
  `docs/upstream-prs.md`.
- **Output:** no change on the shipping packs. Prompt tokens change only for
  `--prefix-file` conversations with assistant turns, as intended.
- **Depends on `90`.** The sync rewrites the SSD cache and the Qwen graph
  code, so every site is re-checked on the synced tree before porting
  (task 1.2). The #1125 caller analysis already holds at `b3f5018`.
- **#1328 (`170`)** also returns failed reservations on the SSD path. `120`
  lands first, and `170` then rebases on it.
