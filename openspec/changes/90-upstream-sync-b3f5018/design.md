# Design

## Context

`sync-map.md` is the evidence: a three-way comparison of `fc80bd6`, the
child's `main` (`765e9a5`) and upstream `b3f5018`, commit by commit, made
without building. The decisions below take its recommendations, adjusted by
the measurements made on 2026-11-14 (proposal.md).

## Decisions

### D1. Gate on plain parity before merging: done for Q4
Upstream `b3f5018` and the child's `main` give byte-identical greedy output on
Q4 over the 12 identity prompts, and upstream `--mtp` equals upstream plain on
all of them. The commits the map could not prove order-preserving
(`4ed25e4`, `028b43f`, `1c6d058`, `2960711`, `6b7cb44`, `f768d14`) therefore
did not move Q4's output on these prompts. Q2 is not measured: it needs the
pack (137 GiB). The sync proceeds on Q4. The Q2 runs are a task that waits for
the owner's approval of the download.

### D2. MTP: the child's design
Keep `30`'s priming and `82`'s exact verify rows. Upstream lacks `82`; on Q2
that was the measured cause of MTP output leaving plain output. Upstream's
resident default (`cd1c550`, empty predictor history) throws away the priming
that gave MTP decode on code +8.3%. Remove the upstream MTP-prefill machinery
the child does not reach, with `sf-ablate(mtp)` markers:
- `mtp_tail_R` and its pending-row model;
- `qwen4_graph_mtp_cache_steps/cache_cold/boundary/project/input`;
- the `kernel_qwen4_mtp_project_q8*` kernels;
- `DS4_QWEN4_MTP_PREFILL`.

Re-apply `82`'s `qwen4_verify_attention_rows` branch in
`qwen4_graph_attention_tail`, and delete the 2/1 split that upstream moved into
`qwen4_graph_attention_core_rows`. `tests/test_qwen4_mtp_identity.py` must
pass at every depth.

### D3. Snapshot payload v2
v3 only exists to carry D2's rejected tail state. Keep v2, with one marker at
the version constant saying that upstream writes v3. The child's checkpoints
live in `~/.sf/q3-8flash` and are never shared with ds4.

### D4. M5 low-bit decode: merge with ours, then measure #1238
Resolve the merge with the child's M5 dispatch: `mid_iq2` and `down_q2k`
(their kernel text is upstream's now) and the separate reduce. Then, on the
sync branch, put #1238's M5 path through two gates:
- a byte-exact kernel test against the child's kernels, on random inputs at
  the decode sizes;
- an A/B run of the full path against the merge with ours (plain and MTP
  decode).

Take it if both pass. The speed gate needs it: upstream decode is about 3%
faster on CLI runs, and the parity oracle fails a child more than 2% slower.
If the fused `down_reduce` is not byte-exact, take only the parts that are
(`mid_iq2xxs`, `mv_specialize`), and record the rest in the registry.

### D5. `metal/dense.metal` names
Rename the child's 82 templates (`kernel_mul_mv_q8_0_f32_rows_impl` becomes
`..._vrows_impl`, and `kernel_mul_mv_t_t_4_rows` becomes
`kernel_mul_mv_t_t_4_vrows`), keeping the host names `kernel_mul_mv_*_r2/r3`.
For F16, use upstream's `exact_rows` multi-row kernel if `82`'s byte-exact
test passes on it. Then the child's F16 r2/r3 kernels go.

### D6. `028b43f`: take it
It pins in the source the F16 order the compiler already emitted, which makes
the plain/`_pf`/reuse/per-row equivalence a language guarantee. Accept it only
with the kernel byte-exact pins and parity passing. If it moves logits, report
that upstream changed arithmetic; do not revert it in the child.

### D7. Low-bit tails on M5: ours
`81` is an owner decision. Widen its device test to
`ds4_gpu_device_is_m5_or_m6_apple_silicon()` and add an `sf-keep` note.

### D8. Watch items
- `ef8e536` adds a Q2_K word-load branch to `qwen4_load_raw16_next`.
  `b3f5018` fixed the same pattern in the row dot for half-aligned rows. Before
  taking it, prove that MM prefill never sees a half-aligned Q2_K row (TP
  slices, SSD cache slots). Otherwise port it with `packed_uchar4`.
- `6b7cb44` reads a BF16 copy of the router's F32 rows. It is exact only if
  every router weight is BF16-representable: check both packs' router
  tensors.
- `f768d14` changes the attention decode geometry. The identity test must
  still pass, because `82`'s rows kernels and the decode kernel must agree.

## Risks / Trade-offs

- **The MTP core is the largest conflict zone.** Upstream and the child
  changed `qwen4_graph_forward_tokens` (169 differing lines),
  `ds4_session_qwen4_spec_cycle` (104) and `qwen4_graph_mtp_steps` (91). The
  identity and limits tests are the gate; a silent revert of `82` is the
  failure to look for.
- **Q2 stays unverified** until the owner approves the download, and Q2 is
  where `82`'s divergence first showed. Until then the sync is not landed with
  Q2 claims.
- **New upstream tests pin upstream's choices.** Each one is adapted or removed
  with a reason in the commit message, never left failing.

## Migration Plan

One branch, `sync/b3f5018`, uncommitted until the owner asks. rerere records
every resolution, so the next sync replays them.
