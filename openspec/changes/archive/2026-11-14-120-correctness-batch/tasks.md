# Tasks

Starts from `main` with `90-upstream-sync-b3f5018` landed. `<Q4>` is the
child's `qwen3.8-flash-next.gguf`; `$SCR` is `~/.sf/q3-8flash/scratch`, and
this change's files go in `$SCR/c120/`. Model runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites (check `grep -c '^test:' Makefile` is 1 after any Makefile
edit).

## 1. Branch and sources

- [x] 1.1 `git config rerere.enabled true`; `git switch -c fix/120-correctness-batch`. Fetch each PR head (`git fetch upstream pull/<N>/head`) for 1326, 1156, 1126, 1125, 1145 and 1128, and save `git show` of the ported commits to `$SCR/c120/`.
- [x] 1.2 Re-check every site of proposal.md's table on the synced tree, by `rg` on the cited function names, not on line numbers. Verify, and record in `$SCR/c120/sites.txt`, that each defect is still present, and that `ds4_gpu_qwen4_moe_stream_tensor` still reaches the stream cache only through `prepare_selected_batch`. Drop any fix whose defect the sync already removed, and say so in the report.

## 2. Fixes, one step each

- [x] 2.1 #1326: drop the EOS push for assistant turns in `ds4_prompt_prefix_append`. Add a model-backed `ds4_test` entry (`--prompt-prefix-qwen`) that counts EOS tokens after importing one user and one assistant turn: 2, and the last token is not EOS. Run the step checks. *(Entry written and built; its model run is gate 3.1, pending the GPU.)*
- [x] 2.2 #1156: fix `iq1_s` and `iq4_nl` in `gguf_types`. Add the model-less `--gguf-types` entry and `ds4_test_gguf_type_sizes()`, limited to the types the child's table lists. Verify that it fails on the old table, by a temporary revert of the two lines, and passes on the new one. Run the step checks.
- [x] 2.3 #1126: add `g_keepalive_pipeline`, resolved by `ds4_gpu_resolve_keepalive_pipeline()` before each `pthread_create`, and cleared in `ds4_gpu_cleanup` when no TP keepalive runs. Both threads read the copy. Verify that `rg -n 'get_pipeline\("kernel_dsv4_tp_keepalive"\)' ds4_metal.m` finds only the resolver and the warm-up call on the main thread. Run the step checks. *(Builds with no warnings; runtime check pending the GPU.)*
- [x] 2.4 #1125: port `a6fc294` (no forced count reset, empty-layer skips) and `a0fe413`'s `ds4_gpu_stream_expert_slab_claim_slot`, used at both `alloc_slab_slot` return sites. Run the step checks and `make` the SSD unit tests (`tests/test_qwen4_ssd_experts`, `tests/test_metal_ssd_experts`), reading their pass lines. *(Code done, step checks pass, both SSD tests build with no warnings; running them needs Metal: pending the GPU.)* (`make test-qwen4-ssd-experts` and `make test-metal-ssd-experts` pass, 2026-11-14.)
- [x] 2.5 #1145: duplicate-name refusal in `parse_tensors`, `ds4_model.path`, and the file name in `required_tensor`'s message. Add a model-less test with a header-only GGUF fixture (a repeated name, then a missing required tensor), checked in a forked child through a stderr pipe, with fixture files under `$TMPDIR`. Run the step checks.
- [x] 2.6 #1128: `n_rot > 64 || (n_rot % 2) != 0` in `ds4_gpu_qwen4_idx_block_key_tensor` and `_rows_tensor`; `ds4_gpu_qwen4_idx_score_emits_tile_max()` in `ds4_metal.m`/`ds4_gpu.h`, used by the scorer and by `qwen4_graph_attention_core`. In `tests/test_qwen4_kernels.c`, a call with `n_rot = 66` and one with `n_rot = 63` return 0. Verify that `make test-qwen4-kernels` ends with `all qwen4 kernel tests passed`. *(Code and the two negative calls done; `make` and `make test` pass and the kernel test builds; its run is pending the GPU.)* (`make test-qwen4-kernels`: `all qwen4 kernel tests passed`.)
- [x] 2.7 After each step: a short review of the step's diff, fixing only what would make it wrong or break a child rule.

- [x] 2.8 Owner questions from the step reviews, decided 2026-11-14 (owner delegated): `q8_1` in `gguf_types` is corrected to 36 bytes (ggml's `block_q8_1`: two halves plus 32) and added to `ds4_test_gguf_type_sizes()`; the attention-prep kernels' `float tmp[64]` needs no change, since `ds4_gpu_qwen4_attn_prep_tensor`, `_attn_cache_prep_tensor` and `_attn_prep_rows_tensor` already refuse `n_rot > 64`. Verify: `make test` prints `gguf-types: OK`.

## 3. Gates

- [x] 3.1 `DS4_TEST_MODEL=<Q4> ./ds4_test --prompt-prefix-qwen` passes. The full `DS4_TEST_MODEL=<Q4> ./ds4_test` shows no new failure against `docs/TESTING.md`'s baseline. (`--prompt-prefix-qwen: OK`; full ds4_test PASS against the five known failures inside `tests/model_gates.sh`, with MTP identity, limits, vision and host paths.)
- [x] 3.2 SSD: streamed tokens identical to resident, as in `80` (`ab_bench.py --a . --b . --b-bench-arg --ssd-streaming`, Q4). Never emulate used memory on a resident run; keep scratch out of `/tmp`. (PASS (tokens), plain and mtp-code, streamed against resident.)
- [x] 3.3 `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout: `PARITY OK`. (PARITY OK, 10 prompts.)
- [x] 3.4 `python3 speed-bench/ab_bench.py --a <worktree at main> --b . --bitwise --budget 600`: `PASS (tokens; bitwise)`, no metric's pooled CI wholly below zero. Guard only; no record row. (PASS (tokens; bitwise), 18 pairs; no CI wholly below zero. MTP decode read +7..+10% because the A side (main) ran at 80 t/s where it ran 87.6 an hour earlier: a measurement mode, not a gain, so nothing is claimed.)

## 4. Closing

- [x] 4.1 Final pass over the touched regions (AGENT.md, surrounding idiom). (Read the whole diff: keepalive resolution, slot claim and give-back, empty-layer skips, the tile-max predicate, which keeps the scorer's earlier MM branch as its first test.)
- [x] 4.2 `docs/upstream-prs.md`: the ported commits to `adopt -> 120-correctness-batch`, `a0fe413` with "reachable part only", and any fix dropped in 1.2 with its reason.
- [x] 4.3 `openspec validate 120-correctness-batch --strict` passes.
- [x] 4.4 Report to the user in Italian. Commit only when the owner asks: one signed commit, with each PR author as `Co-authored-by`. (Reported 2026-11-14; commit waits for the owner.)
