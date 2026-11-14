# Proposal

## Why

The child is synced to upstream `fc80bd6` (2026-10-07). `upstream/main` is
`b3f5018` (2026-11-03), 267 commits ahead. Those commits include upstream's
merge of #1056, which the child had ported in part by hand in `40`, `50`,
`60`, `70`, `80` and `81`, and #1238, a series of Qwen decode kernels titled
"faster Metal decode (bit-exact)". This is the first sync across both, and
rerere has nothing recorded for them.

Three facts from 2026-11-14 decide how to do it:
- **A trial merge** (`git merge --no-commit upstream/main` in a scratch
  worktree, then aborted) leaves 28 files with content conflicts: 69 hunks in
  `ds4.c`, 44 in `ds4_metal.m`, 10 in `Makefile`, 8 in `metal/qwen4.metal`, 5
  in `ds4_server.c`, 4 in `ds4_gpu.h`, and 31 modify/delete conflicts for files
  the child removed (`tools/rm-deleted-conflicts.sh` handles those).
- **Plain greedy output did not move.** On Q4, upstream `b3f5018` and the
  child's `main` give byte-identical output on all 12 prompts of
  `tests/test_qwen4_mtp_identity.py` (upstream's three Qwen cases plus the
  parity set), and upstream's `--mtp` output equals its plain output on all 12.
  So both parity rules can hold after the sync: token-identical to upstream at
  the new merge-base, and the plain path bit-identical to the child's previous
  build.
- **Upstream is now faster.** On the same 12 CLI runs, upstream plain
  generation averaged about 58.8 t/s against 57.0 for the child. The
  `ds4-bench` sweep on *I Promessi Sposi* (Q4 resident, child-upstream-upstream-
  child, 180 s rests, mean of two runs each) gives:

  | context | prefill, child vs upstream | decode, child vs upstream |
  |---:|---:|---:|
  | 2048 | -5.1% (cold first run) | -5.2% |
  | 4096 | +0.7% | -4.4% |
  | 8192 | +0.5% | -4.2% |
  | 16384 | -1.3% | -5.0% |
  | 32768 | -5.8% | -4.4% |

  That is #1238 in decode and, at long contexts, probably the GPU embedding
  gather (`1c6d058`), the PLE overlap (`347c2e1`) and the dense-chunk indexer
  skip (`2960711`). A sync that kept only the child's M5 kernels would fail the
  parity oracle's 2% speed gate.

`sync-map.md` (in this change) maps every Qwen-relevant upstream commit to its
child counterpart, the relation between them, the resolution and the logit
risk.

## What Changes

A sync on `sync/b3f5018`, following StarForge `SYNC.md`, with these
resolutions (design D1-D8):
- **Shared code identical on both sides** (14 SSD-streaming host functions,
  constant 906, the `mid_iq2`/`down_q2k`/HC reuse kernel texts): take upstream's
  text, so the child stops carrying its own copy.
- **MTP: keep the child's design.** That means `30`'s priming plus `82`'s exact
  verify rows. Upstream lacks `82` and defaults resident runs to an empty
  predictor history (`cd1c550`). Delete upstream's MTP-prefill machinery that
  the child does not use (`92f57fc` tail state, `qwen4_graph_mtp_cache_*`,
  `mtp_project` kernels) with `sf-ablate(mtp)` markers. Re-apply `82`'s
  `qwen4_verify_attention_rows` call in `qwen4_graph_attention_tail`. Upstream
  moved the old 2/1 split into `qwen4_graph_attention_core_rows`, where it
  would compile and silently undo `82` for 2-row verifies.
- **Snapshot format: keep v2.** Upstream's v3 (`7bba0f7`) only carries the
  tail state the child rejects.
- **M5 low-bit decode.** Resolve with the child's kernels first. Then A/B
  #1238's M5 path (`mid_iq2xxs`, IQ2/Q2_K `mv_specialize`, fused
  `down_reduce`) and take it if it is byte-exact against the child's kernels
  and faster.
- **`metal/dense.metal` name collision** with `82`. Upstream's V4.1 work
  defines `kernel_mul_mv_q8_0_f32_rows_impl` and `kernel_mul_mv_t_t_4_rows`
  with other parameters. The child's 82 templates get new names, and the host
  names `kernel_mul_mv_*_r2/r3` stay. For F16, take upstream's exact multi-row
  kernel if `82`'s byte-exact test passes on it.
- **Low-bit remainder tails on M5: keep ours** (`81`, owner-approved
  trade-off), with an `sf-keep` note.
- **Take** the correctness and safety fixes that reach Qwen:
  - `c97964b`: token validation before staging;
  - `a4c922c`: Metal autorelease leak on `/ctx`;
  - `2768d0e`: JPEG SOS validation;
  - `a8ce74a`: blank reasoning;
  - `f5127df` and `67f2ca9`: 256 images per request, advertised modalities;
  - `b799c90`: parallel image resize;
  - `187f46b`: bench logits hash;
  - `e14d7f8`: `ds4_test` engine closing.
- **Drop** the code for removed areas (V4.1, GLM, CUDA, ROCm, DSpark, the
  V4.1-only idle prefill quantum), with markers where a live file keeps a cut.

Non-goals:
- #1115's template fix: it never landed upstream and gets its own change.
- The registry refresh: `87-pr-registry-refresh` does it.
- The dead-code sweep after the merge: `100-post-sync-ablation`.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: a sync keeps the child's specified behaviour; the gates below prove it)

## Impact

- Every kept source file. `ds4.c`, `ds4_metal.m` and `metal/qwen4.metal`
  carry the risk.
- New upstream tests that pin upstream's M5 dispatch, MTP design or v3
  payloads (`test_qwen4_mtp_policy.c`, `test_qwen4_mtp_prefill.c`,
  `test_metal_qwen4_moe_down.m`, ...) are taken, adapted or removed to match
  D2-D4. None is left failing.
- Gates:
  - `make -j8` with no warnings, and `make test -j8` naming its suites, with a
    `test:` rule check after the Makefile merge (StarForge rules 18-19);
  - the kernel tests, `tests/test_qwen4_mtp_identity.py` and
    `tests/test_qwen4_mtp_limits.py`;
  - the StarForge parity oracle at the new merge-base;
  - an A/B run with `--bitwise` against the old `main`.
- Q2 is not on this machine (only the Q4 pack is in the Hugging Face cache).
  The Q2 gates need the owner's approval for a 137 GiB download.
