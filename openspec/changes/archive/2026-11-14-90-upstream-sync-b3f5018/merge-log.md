# Merge log (night of 2026-11-14)

What was done on `sync/b3f5018` in the child's main checkout: the merge was
prepared overnight and committed on 2026-11-14 after the model gates below.

## Method

A line-based merge could not resolve `ds4.c` (69 hunks) or `ds4_metal.m` (44):
the child deleted about 41K lines of the base, and git aligned the Qwen graph
against unrelated text, so `qwen4_graph_attention_tail` and
`qwen4_graph_forward_tokens` appeared three times in the result. No diff
algorithm (myers, histogram, patience, minimal) fixed it.

The merge of these files was therefore done item by item. Each version (base
`fc80bd6`, child `765e9a5`, upstream `b3f5018`) was split into top-level items
(functions, structs, globals with their leading comments and preprocessor
lines), items were matched by their first code line, and each matched item was
merged three-way with `git merge-file`. The tools are in the overnight
scratchpad (`fmerge.py`, `compose_q4m2.py`, `compose_dm.py`, `fixloop.py`).
Reordering items moved a few `#if` openers away from their `#endif`; the
three cases found by the compiler were repaired by hand (`#ifndef DS4_NO_GPU`
around the DSpark-named frontier helpers, the GLM helper block, and a stray
`#endif`), and the CPU-reference build (`-DDS4_NO_GPU`, `make test`) passes.

## Resolutions, by design decision

- **D2, MTP: the child's design.** Kept `30`'s priming
  (`qwen4_graph_mtp_prime`, `mtp_next`/`mtp_tail`, the GPU id gather) and `82`'s
  exact verify rows. Removed upstream's MTP-prefill machinery:
  `qwen4_graph_mtp_cache_steps/cache_cold/boundary/project/input`,
  `qwen4_mtp_prefill_resolve`, `mtp_tail_R` and the snapshot tail tensors,
  `kernel_qwen4_mtp_project_q8*`, `ds4_gpu_qwen4_mtp_project_tensor`, and the
  tests that pin them (`test_qwen4_mtp_policy.c`, `test_qwen4_mtp_prefill.c`).
  `qwen4_graph_moe_last` (MoE for the last MTP row only) is not taken: a
  separate, measured MTP change can adopt it.
  - Upstream moved attention into `qwen4_graph_attention_cache` → `prepare` →
    `core_rows`. `core_rows` now carries `82`'s branch
    (`g->verify_rows_exact && T > 1` → `qwen4_verify_attention_rows`) in place
    of upstream's 2/1 split, with an `sf-keep(mtp)` marker.
  - The child's priming cache pass is `qwen4_graph_attention_prime` (the name
    `qwen4_graph_attention_cache` is upstream's now).
  - The priming's tail flush and next-token staging moved into
    `qwen4_graph_stage_embeddings`, where both the plain and the new
    PLE-prefetch staging paths pass.
  - The HC mixer keeps `82`'s rule: the pair kernel is not used for verify rows.
- **D3, payload v2.** `qwen4_session_save/load_payload` and the payload size
  are the child's; one `sf-keep(mtp)` marker at the tag says upstream writes v3.
- **D4, M5 low-bit decode: upstream's path taken directly** (deviation from the
  design, which asked to merge with the child's kernels first). Upstream's
  routed-expert kernels and host dispatch are the parity reference and
  #1238 builds on them; their text is equivalent to the child's `50`/`70`
  kernels where the child had ported them. The child's `qwen4_moe_mid_q4k_pass`,
  `qwen4_moe_shared_q8_mid/rows`, `qwen4_q2k_block_rows`, the
  `qwen4_moe_down_mxfp4_pass` refactor of `70` and `g_qwen4_routed_pipelines`
  went with them. Evidence that this is exact: upstream's standalone Metal tests
  pass (`make test-qwen4-metal-units`), the child's kernel suite passes
  (`make test-qwen4-kernels`, `-q2`, `-prefill-reuse`, `-ngrams`), and the model
  gates below. Speed is measured by the A/B run.
- **D5, `metal/dense.metal`.** The child's `82` row kernels and upstream's V4.1
  multi-row templates coexist as template overloads; the library compiles and
  `MTP verify rows ... byte-exact vs single rows` passes. The `82` matmul entry
  points in `ds4_metal.m` (`ds4_gpu_matmul_q8_0_legacy_tensor`,
  `ds4_gpu_matmul_f16_tensor(_impl)`, `ds4_gpu_matmul_f32_tensor`) are the
  child's. Renaming the child's templates for clarity is left as a follow-up.
- **D7, low-bit tails on M5: the child's.** `qwen4_moe_mm_tails` keeps types
  10/16 on M5/M6, and the 16- and 8-token NAX tiles (`60`/`81`) were re-applied
  to upstream's `nax_t` kernels, with their four instantiations and host
  dispatch (inside the routed-MM kernel range, so streaming binds them with
  constant 906).
- **`1c6d058` not taken yet.** The device gather of BF16 prompt embeddings needs
  `kernel_glm53_embedding_bf16` and the HC row repeat, which the child removed
  with GLM; host staging gives the same rows (`sf-keep(sync)` marker). Adopting
  it is a measured follow-up (prefill at long contexts).
- **Taken:** PLE prefill prefetch and decode overlap, dense-chunk indexer-query
  skip (`2960711`), token validation before staging (`c97964b`), the Metal
  autorelease fix, JPEG SOS validation, blank reasoning, 256 images and
  advertised modalities (documented in `docs/SERVER.md`), `ds4_metal_device.h`.
- **Dropped:** every V4.1, GLM, CUDA, ROCm and DSpark addition the compiler
  reached (logged item by item), the V4.1-only idle prefill quantum in the
  server (`sf-ablate(ds41)` marker), the V4.1 TP verify ack in `ds4_tp.c`
  (marker), upstream's measurement records for M1 and M2 Ultra.
- **Docs:** the child's; the PR-provenance note `docs/QWEN38_Q4_REGISTER_REUSE.md`
  was dropped (its code arrived as `e73e516`, derived from the child's `08ea4d7`).
- **Makefile:** the child's, with `ds4_metal_device.h` dependencies and two new
  targets: `test-qwen4-metal-units` (upstream's standalone Metal tests) and
  `test-qwen4-host-paths QWEN4_GGUF=...` (PLE prefetch, generation, resident
  arithmetic; model-backed).

## Post-merge fix: MTP replayed the whole context every cycle (2026-11-14)

G2 failed on the first merge: `--mtp` output differed from plain from word 21
on, at 4.7 t/s against 59 plain, and slower on longer prompts (2.9 t/s). The
night run stopped G2 mid-way and the failure was not read before it stopped;
it was there already.

Cause: a name with two meanings. Upstream's `mtp_tail_valid` means "the
predictor's state is current through `mtp_pos`" and stays set while decoding.
The child's field of the same name (`30`'s priming) means "one primed prompt row
waits for its next token" and is cleared by the first decode. The merge took
upstream's test in `qwen4_session_replay_if_stale`
(`pos == checkpoint.len && (... mtp_tail_valid && mtp_pos + 1 >= len)`), which
under the child's meaning is false after the first token: every MTP cycle
replayed the kept context through `ds4_session_sync`. Prefill numerics are not
decode numerics, hence the divergence; a full prefill per cycle, hence the
speed. The same test sat in `qwen4_graph_native_session_batch_ready` and
refused batched MTP decode for every session past its first token.

Fix: the child's predicates back in both functions, each with an
`sf-keep(mtp)` marker. One CLI run: Hamlet prompt `--mtp` byte-identical to
plain, 71.7 t/s. Follow-up `91-mtp-prime-names` renames the child's fields so a
future merge of upstream code that reads upstream's meaning fails to compile
instead of compiling into this.

## Checks run

| Check | Result |
|---|---|
| `make -j8` | no warnings |
| `make test -j8` | passes, suites named (server, ds4 tests, layer pack, prompt prefix, sampling, TP link, sfctl) |
| `make test-qwen4-kernels` | `all qwen4 kernel tests passed`, including `MTP verify rows ... byte-exact vs single rows` |
| `make test-qwen4-q2`, `-prefill-reuse`, `-ngrams` | pass |
| `make test-qwen4-metal-units` | Q8 reduction and GEMV reference, MoE half/mid/down, HC, MXFP4 staging, device policy: all PASS |
| G1 plain identity vs upstream `b3f5018` (Q4, 12 prompts) | 12/12 byte-identical, at upstream's speed |
| G2 `test_qwen4_mtp_identity.py` (Q4) | 36/36 SAME (after the post-merge fix) |
| G3 `test_qwen4_mtp_limits.py` | one-row, two-rows-depth-three, unfused: PASS |
| G4 `test_qwen4_cli_vision.py`, two images | PASS; ordinary and MTP outputs equal old `main`'s |
| G5 `make test-qwen4-host-paths` | PLE prefetch/rollback/fallback, generation bit-exact: PASS |
| G6 `tools/parity-check.sh` | PARITY OK, 10/10 token-identical, all within 2% or faster |
| G7 `ds4_test` with Q4 and MTP | the five `docs/TESTING.md` failures, same assertions |
| G8 `--ssd-streaming` vs resident, 3 prompts | identical |
| MTP against upstream | `mtp-compare.md` |
| A/B `--bitwise` against old `main` (Q4) | PASS; plain decode +4.1%, MTP decode +-0.3%, prefill -0.3..-1.0% |
| Q2: plain vs upstream, MTP identity, parity | 12/12 identical, 36/36 SAME, PARITY OK 10/10 |

The first G7 run reported two more failures (`qwen4-restore-reuse`,
`session-rewind`): MTP never drafted. That `ds4_test` had been built before the
post-merge fix; `make -j8` relinks the four binaries, not `ds4_test`. Rebuilt,
both pass. `88-model-gates-script` builds what the gates run.
