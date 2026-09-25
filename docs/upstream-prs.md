# Upstream PR registry

This file records which unmerged [antirez/ds4](https://github.com/antirez/ds4)
pull requests were reviewed for this child, up to which head commit, and the
verdict on every commit. A later review reads it to pick out only new PRs and
new commits on PRs already judged. The head SHAs record what was reviewed; they
are not a sync base. The base stays in git: `sync-*` tags and
`git merge-base HEAD upstream/main`.

Last review: 2026-09-24

## Finding what changed

```sh
# new commits on a PR already analyzed (recorded head .. current head)
gh api repos/antirez/ds4/compare/<recorded-sha>...$(gh pr view <N> -R antirez/ds4 --json headRefOid -q .headRefOid) -q '.commits[] | .sha[0:7] + " " + (.commit.message | split("\n")[0])'
# PRs created or updated on or after the last review date
gh pr list -R antirez/ds4 --state all --search "updated:>=<YYYY-MM-DD>" --json number,title,headRefOid,updatedAt
```

If `compare` fails because the recorded head is gone (force push), list the
current commits and diff them by subject against the lines below:

```sh
gh pr view <N> -R antirez/ds4 --json commits -q '.commits[] | .oid[0:7] + " " + .messageHeadline'
```

Whether a commit already reached upstream is decided by patch, then by subject:

```sh
git fetch upstream && git fetch upstream pull/<N>/head
git cherry -v upstream/main FETCH_HEAD   # "-" = same patch in upstream/main
```

## Verdicts

| Verdict | Meaning |
|---|---|
| `adopt -> <change>` | port the commit in that change |
| `idea -> <change>` | take the idea, not the code, in that change |
| `drop` | not taken; the reason says why |
| `next sync` | a correctness fix to take at the next project sync, not in a perf branch |
| `superseded by <sha>` | another commit covers it |
| `already in main` | the same patch is in `upstream/main` |
| `in main, modified` | same subject in `upstream/main`, but the landed patch differs |
| `not reachable from Qwen` | touches code the Qwen graph never runs |
| `docs` | documentation or charts only |
| `merge` | merge commit, no content of its own |
| `open` | useful, not assigned to a change yet |

A change that adopts or rejects a commit updates that commit's line in the same
branch.

Rejection rule: performance changes must not lose precision. KV-cache or
activation quantization, and any route that changes greedy output, is `drop`.

## PRs

| PR | Title | State | Head analyzed | Commits | Updated | Analyzed | Summary |
|---|---|---|---|---|---|---|---|
| #1062 | Qwen3.8 Flash Next: batched decode and MTP across sessions on Metal | open | `1ab00b5` | 33 | 2026-09-16 | 2026-09-24 | 15 already in main, 8 in main modified; `30-mtp-cycle` took 4 (`acce8da`, `be4cec8`, `0a89a04`, `1cd83e3`) and dropped `926ee12` on measurement |
| #1056 | Metal: optimize Qwen3.8 kernels, MTP state and SSD MoE scheduling | open | `b1af94b` | 30 | 2026-09-23 | 2026-09-24 | `40` took the HC reuse only (plain decode +0.8%; Q8 commits measured and dropped), MTP ideas -> `30`, `13c53d9`'s shared Q8 loop -> `50` (plain decode +1.3%), SSD -> `80`, IQ2/Q2_K -> `70`, `496b153`'s tile widths -> `60` (bit-identical remainder tails); chunk-invariant prefill dropped |
| #1115 | Two fixes for Qwen3.8-Flash-Next | open | `c544020` | 3 | 2026-09-24 | 2026-09-24 | KV quantization dropped; template fix at next sync |
| #1118 | server: make the idle prefill quantum configurable | open | `25def38` | 1 | 2026-09-24 | 2026-09-24 | open |
| #1047 | Metal: add SSD expert streaming for Qwen3.8 Flash Next | closed | `d6cbc77` | 3 | 2026-09-19 | 2026-09-24 | folded into #1056 |
| #864 | metal: speed up IQ2_XXS MoE prefill with half LUT and split MPP | open | `482e246` | 1 | 2026-08-27 | 2026-09-24 | code targets DeepSeek `mul_mm_id`. Ideas: `60-q4-expert-prefill` measured double-buffered staging alone and dropped it (routed gate/up GPU time +29% at 2048 tokens; the split M=16 tiles and tail cull change accumulation and were not tried); `50-q4-expert-decode` measured FP4 decode from the code bits and dropped it (MXFP4 down +30% GPU time, plain decode -3.4%: the constant table is cheaper); `70-q2-kernels-m5` takes the half LUT |
| #959 | metal: prune top-k argsort merge rounds to top_k | open | `b4605a0` | 3 | 2026-09-14 | 2026-09-24 | not reachable from Qwen (argsort merge; Qwen uses radix select) |
| #1014 | Optimize Q8 decode projections on CUDA, Metal and ROCm | closed | `fe545fa` | 3 | 2026-09-10 | 2026-09-24 | not reachable from Qwen (DeepSeek HC compressors) |
| #947 | Withhold the automatic Metal 4 tensor enable on M5 until accumulate parity | closed | `a11bf74` | 1 | 2026-09-02 | 2026-09-24 | M5 Metal-4 tensor route: already in the baseline |

## Commits

### #1062 (head `1ab00b5`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `68cd651` | Add a session-concurrency benchmark for the engine and the server | in main, modified | landed as `147b263` |
| `5947b48` | Batch Qwen3.8 Flash Next decode natively across sessions | in main, modified | landed as `ba3b0c2` |
| `bad5d80` | Report the logit distance when a batched verify fails | already in main | same patch |
| `45758a4` | Batch Qwen3.8 attention rows into one dispatch per stage | already in main | same patch |
| `7518926` | Take F32 decode-batch projections through the tiled GEMM | already in main | same patch |
| `ff6f76c` | Keep F16 decode-batch projections on the fp32 tile | already in main | same patch |
| `0b6fb9e` | Group a decode batch's routed experts and run its shared expert densely | already in main | same patch |
| `9978573` | Multiply Q8 decode batches on fp32 simdgroup matrices | already in main | same patch |
| `c35509a` | Allocate the k-split scratch once | already in main | same patch |
| `b63d48d` | Speculate over a batch of Qwen3.8 sessions | in main, modified | landed as `a504136` |
| `4186e14` | Run the speculative batch's recurrent and attention steps as rows | already in main | same patch |
| `a7d8682` | Specialize the grouped MoE mid pass on its pair count | already in main | same patch |
| `70c4893` | Specialize the grouped MoE down pass on its pair count | already in main | same patch |
| `8fc7612` | Walk both rows of a grouped down simdgroup together | already in main | same patch |
| `20394dc` | Keep verify rows on the few-row matvec | already in main | same patch |
| `acce8da` | Prime the MTP predictor with the prompt during prefill | adopt -> `30-mtp-cycle` | taken. MTP decode on code +8.3% (tokens per cycle 1.83 -> 2.46), prose -1.5% (inside noise), MTP-mode prefill -4.0%. The tail flush runs in every trunk encoder, because the child's plain batch also takes MTP sessions |
| `822de06` | Let a speculative batch commit three tokens per item | drop | helps only a batched server with one active slot; CLI and non-batched server already commit depth-3 cycles |
| `832f4e4` | Read a decode token's n-gram rows concurrently | in main, modified | landed as `d0b7434` |
| `be4cec8` | Run the three-row predictor on the decode kernel geometry | adopt -> `30-mtp-cycle` | taken. At depth 3: MTP decode on code +2.4%, three-token cycles -3.2% |
| `926ee12` | Decide the draft depth from measured acceptance and cycle cost | drop | measured after priming: MTP decode on code -8.9% (tokens per cycle 2.46 -> 1.80), prose -0.4%. It probes depth 3 on two cycles in sixteen, so in 128-token generations it rarely learns that depth 3 pays, where the window policy engages it |
| `0a89a04` | Gather the predictor's next-token embeddings on the GPU | adopt -> `30-mtp-cycle` | taken. Bit-identical drafts, speed neutral; frees the 80 MiB priming arena. The batched predictor from `e2cba0b` was rewritten onto the id buffer |
| `1cd83e3` | Chain the second draft inside the predictor's submission | adopt -> `30-mtp-cycle` | taken. Bit-identical drafts, +0.6% at depth 3 (the PR's figure); one drafting helper instead of four copies |
| `13cccce` | Batch the predictor layer across a speculative batch's sessions | in main, modified | landed as `e2cba0b`; see `0a89a04` |
| `4d8b5dd` | Apply the draft head prefix to the batched head, report verify margins | drop | no effect by default (`DS4_QWEN4_MTP_DRAFT_ROWS` is the full vocabulary); needs the `1cd83e3` argmax signature |
| `b6c5936` | Give the batched output head the Q8 tile | in main, modified | landed as `643d4cb` |
| `aaba688` | Decide per cycle whether a speculative batch drafts | in main, modified | landed as `3077786` |
| `80e5eef` | Replace the shared session arena when a wider session finds it idle | in main, modified | landed as `65d2eb3` |
| `0237376` | Count a prefill chunk's token tiles in the k-split rule | already in main | same patch |
| `17d9b06` | Keep prefill chunks on the generic F16 tile | already in main | same patch |
| `8e13f1e` | Price the batched cycle kinds after eight drafted cycles, not sixteen | already in main | same patch |
| `c3fb60c` | Record the M5 Max context x concurrency sweep | docs | benchmark record |
| `472c869` | Render the sweep charts to PNG as well | docs | charts |
| `1ab00b5` | Guard the Metal session paths on the Metal build | drop | already in the child: `DS4_HAS_QWEN4_METAL` is defined in `ds4.c` |

### #1056 (head `b1af94b`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `e37f185` | Metal: add bounded SSD expert streaming for Qwen3.8 Flash Next | adopt -> `80-qwen-ssd-streaming` | phase A: bounded expert cache; lift only the `ssd_streaming` rejection |
| `85d37ae` | Metal: stage only selected Qwen experts for MTP and cache overflow | adopt -> `80-qwen-ssd-streaming` | phase B, needed for the Q2 pack |
| `d6cbc77` | Metal: overlap Qwen decode expert reads with cached gate/up | adopt -> `80-qwen-ssd-streaming` | phase B, with `81b9ebb` |
| `cdfc0d5` | Metal: reuse Qwen IQ2 and HC inputs on M1 Max | adopt -> `40-dense-decode-kernels` (HC part); adopt -> `70-q2-kernels-m5` (IQ2 part) | `40` took the HC gate-mix reuse kernel for one decode token on M5 (F16, rank 320): byte-exact, plain decode +0.8% (12 pairs, bootstrap 95% CI +0.3..+1.5%), MTP unchanged. Not taken: the M1 Max gate, T >= 3 selection, the M1 benchmark scaffolding. The IQ2 part is gated to M5 after an A/B in `70` |
| `496b153` | Metal: adapt Qwen SSD MoE tiles and specialize low-bit prefill | idea -> `60-q4-expert-prefill` | `60` took tile width by tokens per expert as 16- and 8-token tails for each expert's remainder on the half tiles: bit-identical; routed expert GPU time at about 540 tokens moe_mid -1.2%, moe_down -4.9%, about 0 at 2050 tokens, an end-to-end effect below what the A/B harness resolves (most of `60`'s prefill gain comes from its Q4_K staging loads); `70` checks the low-bit part |
| `92f57fc` | Qwen: prepare MTP prefix caches and preserve predictor state | superseded by `acce8da` | #1062 primes the predictor during prefill |
| `b86c8ae` | Metal: remove redundant Qwen MTP projections and expert work | idea -> `30-mtp-cycle` | taken as cache-only priming with the existing kernels: bit-identical, MTP-mode prefill +2.1%. Its M1 Max Q8 EH projection kernel is not taken |
| `9e1429b` | Qwen: bound MTP staging to recover SSD expert cache capacity | adopt -> `80-qwen-ssd-streaming` | phase B |
| `e2b4a47` | Metal: plan Qwen SSD expert cache evictions once per batch | adopt -> `80-qwen-ssd-streaming` | phase B |
| `81b9ebb` | Metal: overlap Qwen MoE down and MTP verification with SSD reads | adopt -> `80-qwen-ssd-streaming` | phase B, with `d6cbc77` |
| `5cbdb6e` | Metal: pipeline Qwen SSD MoE prefill and reuse Q2_K down rows | adopt -> `80-qwen-ssd-streaming` | phase B; the Q2_K down-row reuse is ported by `70-q2-kernels-m5` |
| `2960711` | Qwen: skip unused indexer queries in dense attention prefixes | open | Qwen prefill: drops the indexer query projection for chunks that stay entirely dense; chunks that cross the boundary keep the full projection, so rounding is preserved. No change covers attention prefill yet |
| `2ba92ab` | Metal: compact streamed MoE prefill dispatches by active expert | adopt -> `80-qwen-ssd-streaming` | phase B |
| `a50fecc` | Metal: streamline Q8 matrix-vector loads and reduction | drop | measured in `40` with `04c0867`: bit-identical on M5 (both oracles 0 bit differences) but neutral, plain decode +1.1% (4 pairs, CI -0.5..+3.2%). Kept only as the base of `9bff1ca`, then removed with its oracles in the final pass |
| `bbbc012` | Metal: tune Qwen hyper-connection dispatches for M1 Max | drop | its HC-down tile is M1 Max prefill only. The M5 analogue of its 16-SIMD-group pair default, measured in `40`: MTP decode on code -1.7% (11 pairs), prose +0.3% |
| `a37fd7f` | Metal: reuse IQ2 headers when staging MoE prefill tiles | adopt -> `70-q2-kernels-m5` | device-independent |
| `13c53d9` | Metal: specialize Qwen IQ2 decode and reuse shared Q8 gate/up inputs | adopt -> `50-q4-expert-decode` (shared Q8 loop); adopt -> `70-q2-kernels-m5` (IQ2 part) | `50` took the shared Q8 gate/up loop as `qwen4_moe_shared_q8_mid` in the Q4_K per-token kernel: byte-exact, MoE mid -5.8% GPU time, plain decode +1.3% (14 pairs, 95% CI +1.0..+1.7%). `70` reuses the helper for the IQ2 kernel and the generic kernel's Q8 shared slot, and gates the IQ2 part to M5 after an A/B |
| `9a8462a` | Metal: streamline Qwen Q2 down loads and shared expert row reuse | adopt -> `70-q2-kernels-m5` | gate to M5 after an A/B |
| `f47db4f` | Merge antirez/main at 8db1d1d into qwen-kernel-opt | merge | - |
| `0024ca0` | fix(qwen): unify prefill chunk resolution and test generation parity | drop | chunk-invariant prefill changes logits |
| `2d6a207` | fix(qwen): preserve reference prefill arithmetic with explicit projections | drop | chunk-invariant prefill changes logits |
| `04c0867` | fix(metal): preserve Q8 dot arithmetic to eliminate late decode drift | drop | repairs `a50fecc`; dropped with it |
| `89986c3` | fix(qwen): retain prefill attention arithmetic across Metal partitions | drop | chunk-invariant prefill changes logits |
| `9bff1ca` | perf(metal): reuse Qwen decode activations across four Q8 output rows | drop | measured in `40` with the gate widened to M5: bit-identical and selected for 2560->10240/6144 and 6144->2560, but plain decode +0.3% (14 pairs, CI -0.5..+1.9%). The Q8 projections do not limit M5 decode |
| `11811b9` | perf(metal): reuse half operands for large Qwen SSD MoE prefill | idea -> `70-q2-kernels-m5` | M1 Max SSD-only upstream; check against the M5 tensor path |
| `fd0c24a` | test(qwen): repair compact MoE checks after half-kernel extraction | idea -> `80-qwen-ssd-streaming` | test for the `2ba92ab` compact dispatch and the `11811b9` extraction; taken only with them |
| `a6ad636` | test(qwen): add sparse and long-context MTP replay diagnostics | drop | as written it needs SSD streaming; in `30-mtp-cycle` the bitwise draft gate of the harness covers the cache-only priming it was meant to check |
| `47ca2eb` | Metal: enable Qwen SSD prefill overlap on all devices | adopt -> `80-qwen-ssd-streaming` | phase B |
| `028b43f` | Metal: stabilize Qwen HC arithmetic and extend M5 tuning to M6 | drop | the child's `_pf` kernel already spells the F16 op order, and `cdfc0d5`'s reuse kernel is byte-exact against it without this commit (checked in `40`); the M6 gate does not matter on M5 |
| `b1af94b` | Merge antirez/main into qwen-kernel-opt | merge | - |

### #1115 (head `c544020`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `485902a` | qwen4: TurboQuant KV cache for the Qwen3.8 attention caches (2..8-bit) | drop | quantizes the KV cache: loses precision |
| `f5e419d` | server: render Qwen prompts the way the fixed template does | next sync | Qwen prompt rendering fix; correctness, not performance |
| `c544020` | tests: plumb the disk budget the retention test claims to set | next sync | fixes the retention test added with `f5e419d` |

### #1118 (head `25def38`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `25def38` | server: make the idle prefill quantum configurable | open | reachable here: with `--batched-session` the server feeds Qwen prompts in 2048-token quanta (`server_prefill_quantum_for`), below the engine's 8192-row prefill chunk. The PR only adds an env knob and keeps the 2048 default; measured on CUDA TP |

## Excluded

Not reachable from the Qwen graph, or not Metal: #1090 #1073 #1041 #1042 #1060
#1061 #954 #953 #952 #794 #830 #831 #758 #206 #371 #381 #385 #797 #1000 #396 #261
#846 #850 #1063 #1070 #1100 #990 #1068 #1117 #1116 #1011.

Qwen support itself landed with #991 (2026-09-06); older PRs cannot touch the
Qwen path.
