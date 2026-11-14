# Tasks

Follow StarForge `SYNC.md`, one step at a time. Model runs are strictly
sequential, and no build or test runs beside one. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`.

## 0. Before the merge (done 2026-11-14)

- [x] 0.1 Trial merge in a scratch worktree, then `git merge --abort`: 28 content conflicts, 31 modify/delete (proposal.md).
- [x] 0.2 D1 on Q4: upstream `b3f5018` and the child's `main` agree byte for byte on the 12 identity prompts; upstream `--mtp` equals upstream plain on all 12.
- [x] 0.3 Speed: upstream decode +4..+5% over the child at every context of the `ds4-bench` sweep, prefill +6% at 32768 (proposal.md table).
- [x] 0.4 Owner: approve or refuse the Q2 download (137 GiB) for the Q2 gates. Approved 2026-11-14; downloaded into the HF cache.

## 1. Merge

- [x] 1.1 `tools/sync-start.sh sf-q3-8flash`; `tools/rm-deleted-conflicts.sh sf-q3-8flash`. Verify there are no `DU` entries left.
- [x] 1.2 Resolve `Makefile`, `.gitignore`, the docs and the tests (SYNC.md step 4). Verify `grep -c '^test:' Makefile` is 1, the `-cpu` binary names are kept, and `make -n test | head` lists the suites.
- [x] 1.3 Resolve `metal/qwen4.metal` and `metal/dense.metal` (D5, D7, D8).
- [x] 1.4 Resolve `ds4_metal.m` and `ds4_gpu.h` (map section 7, D4 with our M5 dispatch).
- [x] 1.5 Resolve `ds4.c`. For the MTP core, apply D2: re-apply `qwen4_verify_attention_rows`, and delete the upstream MTP-prefill machinery with markers. Keep the v2 payload (D3).
- [x] 1.6 Resolve `ds4_server.c`, `ds4_tp.*` and the rest. Drop the V4.1-only idle quantum with a marker.
- [x] 1.7 SYNC.md step 5: remove new files and code for removed areas. Verify `make -j8` has no `unused-function` warnings.
- [x] 1.8 Post-merge fix (2026-11-14): `qwen4_session_replay_if_stale` and `qwen4_graph_native_session_batch_ready` read upstream's `mtp_tail_valid` meaning; the child's predicates are back with `sf-keep(mtp)` markers (merge-log.md, "Post-merge fix"). Follow-up: `91-mtp-prime-names`.

## 2. Model-less gates

- [x] 2.1 `make clean && make -j8 && make test -j8`; read the suite names.
- [x] 2.2 The kernel tests (`make test-qwen4-kernels`, `test-qwen4-q2`, `test-qwen4-prefill-reuse`, `test-qwen4-ngrams`) and every new upstream test that is kept.

## 3. Model gates (Q4)

- [x] 3.1 `python3 tests/test_qwen4_mtp_identity.py --model <Q4>`: all prompts and depths identical (36/36, after the post-merge fix 1.8; before it, every MTP run differed).
- [x] 3.2 `python3 tests/test_qwen4_mtp_limits.py --model <Q4>` (one-row, two-rows-depth-three, unfused: PASS).
- [x] 3.3 `DS4_TEST_MODEL=<Q4> DS4_TEST_GLM_MTP=1 ./ds4_test`, compared against the baseline in `docs/TESTING.md`: the five listed failures, same assertions (Priya 9 vs 97). A first run used a `ds4_test` built before 1.8 and failed two more tests; see merge-log.
- [x] 3.4 Vision: `python3 tests/test_qwen4_cli_vision.py` with two images: PASS; ordinary and MTP outputs each equal old `main`'s (their mutual difference is `110`).
- [x] 3.5 SSD streaming: streamed tokens identical to resident (the `80` check): 3/3 prompts identical.

## 4. D4: #1238's M5 path (taken directly at merge time; see merge-log.md)

- [x] 4.1 Byte-exact kernel tests (upstream's `test-qwen4-metal-units`, the child's kernel suite): `mid_iq2xxs` against `mid_iq2`, and `down_reduce` against `down_q2k` plus the reduce, at the decode sizes.
- [x] 4.2 (superseded: upstream's dispatch taken at merge time) Switch the M5 dispatch to #1238's path for the kernels that pass, and run `python3 speed-bench/ab_bench.py --bitwise` against the merge with ours.
- [x] 4.3 Keep it if tokens and logits are identical and decode gains. Rerun 3.1. (Tokens: G1 and parity; decode: parity and `mtp-compare.md`; logits: 5.2.)

## 5. Parity and record

- [x] 5.1 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`, 10/10 token-identical, every prompt within 2% or faster.
- [x] 5.2 A/B against the old `main` with `--bitwise`: PASS (tokens and logit bits), plain decode +4.1%, MTP decode -0.1% (code) / +0.3% (prose), prefill -0.3..-1.0% (follow-ups `95`, `97`). Greedy output did not change, so no new segment: the row against segment 1's start `91f225a` is in `speed-bench/perf-record.md` (plain decode +6.1%, MTP code +22.3%).
- [x] 5.3 Q2 gates (3.1, 5.1) if 0.4 was approved: plain output identical to upstream on the 12 prompts, `test_qwen4_mtp_identity` 36/36, `PARITY OK` 10/10 within 2% (one prompt +6.2%).
- [x] 5.4 Commit and tag only when the owner asks (`tools/sync-finish.sh`). Commit and merge asked 2026-11-14; tag and push not asked.

## 6. Follow-ups written as their own changes

- `95-sync-deferred-perf`: `1c6d058` embedding gather, MTP last-row MoE, the `70` MXFP4 down pass, D5 template names.
- `100-post-sync-ablation`: V4.1/GLM declarations and helpers that compile but are unreachable.
