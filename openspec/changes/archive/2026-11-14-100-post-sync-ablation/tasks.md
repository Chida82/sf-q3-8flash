# Tasks

Starts from `main` with `90-upstream-sync-b3f5018` landed. Model runs are
strictly sequential; nothing else runs beside one.

## 1. Candidates

- [x] 1.1 `git switch -c perf/100-post-sync-ablation`; `make -j8 2>&1 | grep unused-function` and list functions with no referrer (`nm` on the four binaries and `ds4_test`).
  Done statically at `75fc4c4`. The build has no warnings, but 45 `DS4_MAYBE_UNUSED` and 4 `DS4_SERVER_MAYBE_UNUSED` functions hide them; a scratch compile with the attribute off (Metal and `DS4_NO_GPU`) found 2 + 2 that are truly unused. Instead of `nm`: `-dead_strip` link maps of all 41 binaries that link or include the core (4 Metal, 4 `-cpu`, `ds4_test`, every test and bench), at -O0 (no caller chain) and at -O1 -fno-inline (callers folded). The -O0 link also showed 11 GPU functions that are declared but never defined, and are called only from code -O3 folds away.
- [x] 1.2 Coverage build of `sf-q3-8flash` and `sf-q3-8flash-server`; one session each covering plain, `--mtp`, `--vision`, `--dir-steering-file`, `--kv-disk-dir` and `--ssd-streaming`. List never-executed functions added by the sync (`git diff <old main>..main` names them).
  Not run here: nothing removed by 100 depends on it (every cut has a static proof). The two items that need a runtime probe (`kernel_mul_mv_ext_*_r1_{2..5}`, `kernel_mul_mm_id_map0_ne20_{10,16,22}`) moved to `101-legacy-ablation`, which runs the coverage session.
- [x] 1.3 For each candidate: proof of unreachability (SPEC.md §F), checked against `AGENTS.md` "Names that lie". Write the list with its proof in `$SCR/c100/candidates.txt`.
  Closed 2026-11-14: part A and B1 removed with these proofs; B2-B6 written as `101-legacy-ablation`.
  Partial: the static proofs are written. Sync-added candidates (part A, ~2.3K lines) cover Metal host functions, kernels with no live literal, their device helpers, prototypes, `qwen4_graph_moe_impl`'s constant-false `last_only`, and the 2.2 guard inventory. Pre-existing dead code is listed apart (part B, ~11K lines; init-only GLM pipelines alone are ~4.8K) for an owner decision on scope. Still open: the probes that wait for 1.2 (part D), the follow-on template check (A12), and the owner questions Q1-Q5.

## 2. Removal

- [x] 2.1 Remove the proven whole functions and blocks; one `sf-ablate` marker at each non-obvious cut. Verify `make -j8` with no warnings and `make test -j8` naming its suites.
  Built 2026-11-14: `make -j8 all ds4_test` with no warnings, `make cpu`, `make test` (`server: OK`, `ds4 tests: ok`), `make test-qwen4-kernels`, `test-qwen4-metal-units`, `test-qwen4-ssd-experts`, `test-metal-ssd-experts` pass, so the Metal library compiles without the removed kernels.
  Edited, build pending (owner decisions applied; written while a model queue ran, so nothing was compiled). Part A, code the sync added: the A1-A8 host functions and their `ds4_gpu.h` prototypes (with the now-unused `DS4_GPU_TEST_INDEX_SCORE_*`/`COUNT_KERNELS` bits, the never-set `g_dsv4_indexer_fast_math` path and V4.1 parallel-FFN bf16/K-slice flags, and four unused statics/typedefs); the A10 kernels with no literal, their A11 helpers, plus three found on the way (`kernel_dsv41_indexer_score_rows_split{2,4}_bf16`, instantiated by macro, and `dsv41_coherent_load/load4/store4`). Kept by decision: A9 `ds4_gpu_tp_full_expert_bind`, A13 test-only kernels, A15 `last_only`, D1 coverage items, the A12 multi-row templates (now without instantiation), and `kernel_dsv4_indexer_score_one_heads`, whose literal sits in `ds4_gpu_indexer_score_one_tensor` (101). Part B1, separately: the 63 GLM and 7 generic init-only pipelines (globals, init, null checks, releases, unused GLM host arg typedefs) and every `kernel_glm*` kernel in `dsv4_misc.metal` and `moe.metal` with the helpers only they used. The 7 generic kernels (`get_rows_{q8_0,q4_0,q4_K}`, `cpy_f16_f16`, `swiglu_f32`, `add3_f32`, `add_rms_norm_mul_f32_4`) lost their last literal but stay in their files for 101.
- [x] 2.2 Remove the second-reasoning-pass guard in `ds4_server.c` (predicate, fields, two consumer blocks) with one marker. Verify `./ds4_test --server`.
  `./ds4_test --server` passes inside `make test`.
  Edited, build pending: predicate, both `guard_second_reasoning` fields, their setters and the OpenAI and Anthropic text-mode blocks, one `sf-ablate(server)` marker where the predicate was.
- [x] 2.3 Add any new finding to `AGENTS.md` "Names that lie".
  Edited, build pending: the `dsv4_*.metal` row now says referenced is not dispatched; the guard paragraph under "Misleading-name traps" records the removal. The rest of the legacy sweep (part B2-B6) is change `101-legacy-ablation`.

## 3. Gates

- [x] 3.1 `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout: `PARITY OK`. PARITY OK, 10 prompts, after `tests/model_gates.sh` on Q4 (MTP identity, limits, ds4_test, vision, host paths: all PASS).
- [x] 3.2 `python3 speed-bench/ab_bench.py --a <worktree at main> --b . --bitwise`: tokens and logits identical, no metric's pooled CI wholly below zero. PASS (tokens; bitwise), 24 pairs; every median within +-0.7%, no pooled CI wholly below zero.
- [x] 3.3 Line counts of `ds4.c`, `ds4_metal.m`, `ds4_server.c` and `metal/` before and after, in the commit message. `ds4_metal.m` 43352 -> 42183, `ds4_server.c` 19146 -> 19096, `ds4_gpu.h` 2519 -> 2462, `metal/` 36439 -> 27870, `ds4.c` unchanged (the `last_only` path stays for `95`).
