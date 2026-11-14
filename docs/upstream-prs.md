# Upstream PR registry

This file records which unmerged [antirez/ds4](https://github.com/antirez/ds4)
pull requests were reviewed for this child, up to which head commit, and the
verdict on every commit. A later review reads it to pick out only new PRs and
new commits on PRs already judged. The head SHAs record what was reviewed; they
are not a sync base. The base stays in git: `sync-*` tags and
`git merge-base HEAD upstream/main`.

Last review: 2026-11-14. The PR list was taken on 2026-11-13, so the next
search starts from `updated:>=2026-11-13`.

Verdicts are relative to the child's `main`, synced to `b3f5018` by
`90-upstream-sync-b3f5018` (2026-11-14). `already in main` and `in main,
modified` commits came in with that sync; its `sync-map.md` and `merge-log.md`
(`openspec/changes/archive/2026-11-14-90-upstream-sync-b3f5018/`) record how
each one met the child's own ports. A `next sync`
commit that is not in `upstream/main` does not arrive by merging: its reason
names the change that ports it.

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
| #1062 | Qwen3.8 Flash Next: batched decode and MTP across sessions on Metal | open | `1ab00b5` | 33 | 2026-10-17 | 2026-11-13 | 15 already in main, 8 in main modified; `30-mtp-cycle` took 4 (`acce8da`, `be4cec8`, `0a89a04`, `1cd83e3`) and dropped `926ee12` on measurement; `82` made the MTP verify rows exact after `acce8da` exposed a greedy divergence. 2026-11-13: no new commits (title edit only). The four commits `30` took are not in `upstream/main` (no patch or subject match), so they stayed child-only conflict sites at the sync to b3f5018 (90). Upstream `cd1c550` starts resident `--mtp` with an empty predictor history; 90 kept the child's priming (D2), and `91` renamed its fields so they no longer share names with upstream's MTP tail |
| #1056 | Metal: add Qwen3.8 SSD expert streaming and optimize inference | merged (`4ef9e4d`, 2026-11-03) | `9eb4a12` | 42 | 2026-11-03 | 2026-11-13 | `40` took the HC reuse only (plain decode +0.8%; Q8 commits measured and dropped), MTP ideas -> `30`, `13c53d9`'s shared Q8 loop -> `50` (plain decode +1.3%), SSD -> `80` (routed-expert streaming for both packs, token-identical to resident; I/O overlap, eviction planning and compact MTP staging taken, streamed prefill +6..+20% and MTP decode +6..+9% over the foundation; `4642526`'s Q4 decode and `089d966` left for later changes), IQ2/Q2_K -> `70` (its IQ2 gate/up and Q2_K down decode kernels on M5: Q2 decode +9.0%, MTP decode +8.1-8.7% against main, from the two kernels and the specialization they superseded; Q2 tails measured and dropped by the MTP-decode guard, then landed by `81` under the owner's prefill trade-off), `496b153`'s tile widths -> `60` (bit-identical remainder tails); chunk-invariant prefill dropped. 2026-11-13: merged upstream; all 42 commits are in `upstream/main` and came in with the sync to b3f5018 (90), including the ones the child dropped. 9 new commits (`ee79f22`, `b96a12b`, `0231312`, `37f66ba`, two research archives, three merges). `37f66ba` and `a279860` put upstream back on resident arithmetic; 90 took upstream's routed-expert kernels and dispatch (D4) and removed the child's equivalent `50`/`70` copies; `70`'s MXFP4 down pass waits in `95-sync-deferred-perf` |
| #1115 | Two fixes for Qwen3.8-Flash-Next | open | `c544020` | 3 | 2026-09-24 | 2026-11-13 | KV quantization dropped. No new commits. The template fix `f5e419d` is not in `upstream/main`, so no sync brings it: `92-qwen-template-fix-1115` ports it with `c544020` |
| #1118 | server: make the idle prefill quantum configurable | open | `25def38` | 1 | 2026-09-24 | 2026-11-13 | open. Upstream `7da9535` sets the idle quantum to the engine's prefill cap, but `cad7933` then limits that to DeepSeek V4.1, so Qwen keeps the 2048-token quantum after the sync to b3f5018 (90) |
| #1047 | Metal: add SSD expert streaming for Qwen3.8 Flash Next | closed | `d6cbc77` | 3 | 2026-09-19 | 2026-09-24 | folded into #1056 |
| #864 | metal: speed up IQ2_XXS MoE prefill with half LUT and split MPP | open | `482e246` | 1 | 2026-08-27 | 2026-09-24 | code targets DeepSeek `mul_mm_id`. Ideas: `60-q4-expert-prefill` measured double-buffered staging alone and dropped it (routed gate/up GPU time +29% at 2048 tokens; the split M=16 tiles and tail cull change accumulation and were not tried); `50-q4-expert-decode` measured FP4 decode from the code bits and dropped it (MXFP4 down +30% GPU time, plain decode -3.4%: the constant table is cheaper); `70-q2-kernels-m5` did not take the IQ2 half LUT: the bit-identical form still multiplies in f32, and the half x half form double-rounds (14% of 1.5 M cases differ) |
| #959 | metal: prune top-k argsort merge rounds to top_k | open | `b4605a0` | 3 | 2026-09-14 | 2026-11-13 | not reachable from Qwen (argsort merge; Qwen uses radix select). Upstream `82aa7e8` (#1192, in `upstream/main`) also changes argsort; Qwen does not call it |
| #1014 | Optimize Q8 decode projections on CUDA, Metal and ROCm | closed | `fe545fa` | 3 | 2026-09-10 | 2026-09-24 | not reachable from Qwen (DeepSeek HC compressors) |
| #947 | Withhold the automatic Metal 4 tensor enable on M5 until accumulate parity | closed | `a11bf74` | 1 | 2026-09-02 | 2026-09-24 | M5 Metal-4 tensor route: already in the baseline |
| #1238 | Qwen3.8 Flash Next: faster Metal decode (bit-exact) | merged | `6946209` | 13 | 2026-11-03 | 2026-11-13 | all 13 commits are in `upstream/main` and came in with the sync to b3f5018 (90). Upstream reports Q2 decode +10-17% and prefill -4..-7% from 14K tokens (M5 Max). 90 (D4) took its M5 path in place of the child's `70` kernels: tokens and logits identical, Q4 plain decode +4.1% against the pre-sync `main`, MTP decode unchanged (`97-mtp-verify-speed`), prefill -0.3..-1.0% (`95-sync-deferred-perf`). `b3f5018` fixes its `a3a7e2d` |
| #1154 | Metal: overlap Qwen3.8 PLE reads with prefill | open (landed by hand) | `a3f3744` | 2 | 2026-10-30 | 2026-11-13 | in `upstream/main` as `347c2e1`/`64baaa0`, plus `c97964b`; came in with the sync to b3f5018 (90). Prefill +3.9% (M5 Max Q4 16K), logits exact (author) |
| #1198 | Metal: reuse Q4_K raw loads in Qwen NAX prefill | open (landed by hand) | `1fbcf8b` | 1 | 2026-10-30 | 2026-11-13 | in `upstream/main` as `e73e516`, derived from the child's `08ea4d7`; came in with the sync to b3f5018 (90), which keeps one copy |
| #1179 | Speed up Qwen3.8 Flash Next on Metal | open (body "WIP") | `79c914c` | 18 | 2026-10-24 | 2026-11-13 | no description; large kernel and MTP rewrites. Bit-exactness is claimed only in some subjects and was not verified. Everything after the sync to b3f5018 (90) |
| #1149 | Metal: run Qwen3.8 QSA prefill attention on the tensor units | open | `c97a1a9` | 2 | 2026-09-29 | 2026-11-13 | drop: changes logits (max \|dlogit\| up to 1.68 at 64K; top-1 identical) for +3..+7% prefill |
| #1150 | Metal: defer hyper-connection residual writes into the next stream norm | open | `04dbebe` | 2 | 2026-10-02 | 2026-11-13 | open, planned in `140-deferred-hc-residual`: bit-exact claimed (memcmp R/xn/inj), prefill +2.4% at 8K and +1.3% at 32K (M5 Max Q4, author) |
| #1185 | Qwen3.8 exact MTP: draft from the sampled token, defer the residual, allow depth 3 | open | `777f4e3` | 1 | 2026-10-17 | 2026-11-13 | open, planned in `150-exact-sampling-mtp`: changes only `--mtp-exact-sampling` at temperature > 0; greedy byte-identical claimed; +11-15% code/list at forced depth 3 (author) |
| #1328 | Overlap streamed Qwen decode layers with their expert loads on Metal | open | `2d48e3b` | 6 | 2026-11-13 | 2026-11-13 | open, planned in `170-ssd-decode-handshake` (after 90; built on `b3f5018`): bit-identical claimed, steady streamed decode +8-12% (M4 Pro 48 GB, Q2) |
| #1184 | Enable measured M4 Metal choices | open | `62ba62c` | 3 | 2026-11-02 | 2026-11-13 | drop: adds M4 to device gates only; no effect on M5 |
| #1125 | Metal: fix SSD-streaming expert cache slot leaks, in-flight recycling and prune hang | open | `6c41f9b` | 4 | 2026-10-25 | 2026-11-13 | 2 of 4 commits reach the Qwen SSD path, `a0fe413` only in part; planned in `120-correctness-batch` |
| #1126 | Metal: resolve keep-alive pipeline before starting keep-alive threads | open | `242da6b` | 1 | 2026-09-25 | 2026-11-13 | correctness: `NSMutableDictionary` race at startup, present in the child; planned in `120-correctness-batch` |
| #1128 | Metal: reject unsupported shapes in five kernels | open | `fa7bc8a` | 5 | 2026-10-25 | 2026-11-13 | 2 latent Qwen guards reachable (indexer `n_rot`, tile maxima), planned in `120-correctness-batch`; the other 3 not reachable |
| #1347 | Run the Metal queue keepalive every 250 ms | open | `2f0a0aa` | 1 | 2026-11-12 | 2026-11-13 | open: idle-mapping drop measured on M5 Ultra with 205 GB of views; needs an M5 Max measurement |
| #1324 | metal: select the shader language version explicitly | open | `bfaa6a2` | 1 | 2026-11-06 | 2026-11-13 | open, low priority: only for hosts linked against an older SDK |
| #575 | Resolve Metal shader sources relative to the executable | open | `6860463` | 1 | 2026-09-29 | 2026-11-13 | open, low priority: the child loads `metal/*.metal` from the cwd; sfctl runs from the serve worktree |
| #873 | tokenizer: fix bpe_emit_piece's O(n^2) merge loop | open | `142d95b` | 1 | 2026-10-16 | 2026-11-13 | reachable (Qwen BPE); superseded by #1219 if that one is taken |
| #1219 | Make the BPE tokenizer and detokenizer linear | open | `b3f552f` | 1 | 2026-10-16 | 2026-11-13 | open: token-identical claimed (4.29 M pieces per vocab), 3-11 -> 15-53 MB/s, unbroken runs 1.4 s -> 1 ms |
| #942 | Detach tokenizer storage from model mmap | open | `4104bd0` | 1 | 2026-09-24 | 2026-11-13 | open, low priority: avoids late page faults on tokenization; overlaps #1219's arena |
| #1145 | Refuse duplicate tensor names and name the file of a missing tensor | open | `4fbba5d` | 1 | 2026-09-28 | 2026-11-13 | correctness at the GGUF trust boundary; planned in `120-correctness-batch` |
| #1156 | Fix the iq1_s and iq4_nl block sizes in the GGUF type table | open | `f63ae1d` | 1 | 2026-10-01 | 2026-11-13 | correctness: wrong entries in the child (`ds4.c:2086-2087`); planned in `120-correctness-batch` |
| #1326 | prompt prefix: close imported Qwen assistant turns once | open | `7b0e2aa` | 1 | 2026-11-06 | 2026-11-13 | correctness: `--prefix-file` imports get a second `<\|im_end\|>` after assistant turns (`ds4_prompt_prefix.h:44`); planned in `120-correctness-batch` |
| #1325 | server: evaluate Qwen's `<\|im_end\|>` after a thinking answer | open | `46374b0` | 1 | 2026-11-06 | 2026-11-13 | correctness (Qwen live-KV continuation); planned in `130-server-protocol-batch` |
| #1140 | Let Qwen and GLM make several tool calls per turn | open | `480f2ae` | 1 | 2026-10-03 | 2026-11-13 | correctness (Qwen tool calls); planned in `130-server-protocol-batch` with #1251 |
| #1251 | server: stream Qwen tool-call arguments over OpenAI SSE | open | `c98b444` | 1 | 2026-10-22 | 2026-11-13 | protocol (Qwen tool calls); planned in `130-server-protocol-batch` |
| #1284 | Server: do not let chat content inject control tokens | open | `138cb39` | 2 | 2026-10-26 | 2026-11-13 | base of #1288; its own renderer part is DeepSeek V4.1 |
| #1288 | Server: mask GLM and Qwen chat renderers | open | `0252371` | 6 | 2026-11-06 | 2026-11-13 | security (Qwen prompt injection), stacked on #1284; supersedes #197, #1159 and #1327; planned in `130-server-protocol-batch` |
| #1134 | Keep mid-conversation system messages in place | open | `1074193` | 1 | 2026-09-27 | 2026-11-13 | correctness and KV reuse (Qwen renderer); planned in `130-server-protocol-batch` |
| #1088 | server: recover unterminated reasoning as content when the turn completed | open | `00df8df` | 1 | 2026-10-31 | 2026-11-13 | correctness; planned in `130-server-protocol-batch` |
| #1163 | Unterminated tool call: defer to the parse-failure recovery | open | `115ec43` | 1 | 2026-10-01 | 2026-11-13 | correctness (protocol); planned in `130-server-protocol-batch` |
| #1155 | Fix misleading prefill progress and false live cache hits after a backend state reset | open | `8f61ece` | 3 | 2026-10-01 | 2026-11-13 | correctness, reported on Qwen3.8; planned in `130-server-protocol-batch` |
| #1157 | Find the cold KV anchor in ChatML prompts | open | `24c6197` | 1 | 2026-11-02 | 2026-11-13 | correctness: `user_id`/`assistant_id` are -1 in the Qwen vocabulary (`ds4.c:29724`), so the anchor is never found; planned in `130-server-protocol-batch` |
| #1212 | Reload evicted Qwen tool turns for clients that send reasoning back | open | `5cc8f27` | 1 | 2026-11-10 | 2026-11-13 | KV reuse (Qwen tool turns); planned in `160-agent-kv-reuse` |
| #1206 | server: preserve Qwen Responses final-answer cache reuse | open | `c7a0d8a` | 1 | 2026-10-30 | 2026-11-13 | KV reuse; needs #1169 first; planned in `160-agent-kv-reuse` |
| #1169 | Preserve exact tool-call replay across KV checkpoint restores | open | `83b3e88` | 2 | 2026-10-31 | 2026-11-13 | KV reuse and EOS commitment; planned in `160-agent-kv-reuse` |
| #1175 | server: honor rewritten history in live tool continuations | open | `4e113c7` | 2 | 2026-10-30 | 2026-11-13 | correctness: live tool reuse could substitute cached history; planned in `130-server-protocol-batch` |
| #1194 | responses: heal the forked live checkpoint on a token-mismatch miss | open | `ce9fd0b` | 1 | 2026-10-07 | 2026-11-13 | KV reuse; planned in `160-agent-kv-reuse` |
| #1200 | Metal: retain bounded Qwen Responses prompt checkpoints | open | `06d48c0` | 1 | 2026-10-30 | 2026-11-13 | KV reuse: returning to a 73K conversation 38.4 s -> 0.98 s (author); planned in `160-agent-kv-reuse` |
| #1228 | server: retain bounded cold cache prefixes for long prompts | open | `659889d` | 1 | 2026-10-25 | 2026-11-13 | KV reuse; planned in `160-agent-kv-reuse` |
| #1058 | Key tool-conversation KV checkpoints by the client-visible transcript | open | `889b2c0` | 5 | 2026-10-14 | 2026-11-13 | KV reuse after a restart (reported on Qwen) |
| #1059 | server: find token-text disk stores by the request's rendered tokens | open | `0e4d448` | 2 | 2026-10-27 | 2026-11-13 | KV reuse |
| #903 | kvstore: save continued checkpoints after crossed interval frontiers | open | `fd7eda0` | 1 | 2026-10-18 | 2026-11-13 | same problem as #1342; take one |
| #1020 | kvstore: stamp checkpoints with a behavioral tokenizer fingerprint | open | `9cbf7e5` | 4 | 2026-11-06 | 2026-11-13 | safety: rejects checkpoints from another tokenizer; changes the checkpoint trailer |
| #1170 | Keep the disk KV checkpoint the next request loads when storing an evict snapshot | open | `80db39c` | 3 | 2026-10-03 | 2026-11-13 | KV reuse; planned in `160-agent-kv-reuse` |
| #1216 | kvstore: find the longest text-prefix checkpoint in one pass | open | `402c80b` | 1 | 2026-10-15 | 2026-11-13 | lookup speed, same choice; planned in `160-agent-kv-reuse` |
| #1258 | kvstore: skip store attempts when the session has no checkpoint | open | `4ca5111` | 1 | 2026-10-23 | 2026-11-13 | log noise and wasted work; planned in `160-agent-kv-reuse` |
| #1280 | server: continued KV checkpoints that actually land during a long read | open | `caad877` | 1 | 2026-10-25 | 2026-11-13 | KV reuse; measured on V4.1; check the Qwen chunk listener first |
| #1281 | server: a short live prefix no longer hides a longer disk-cache hit | open | `296a512` | 2 | 2026-10-25 | 2026-11-13 | KV reuse; planned in `160-agent-kv-reuse` |
| #1340 | server: align the continued KV checkpoint step with the prefill chunk schedule | open | `702d273` | 1 | 2026-11-10 | 2026-11-13 | KV reuse; alternative to #1342 |
| #1342 | server: write a continued KV checkpoint at the first chunk past each step | open | `88ac7a1` | 1 | 2026-11-10 | 2026-11-13 | KV reuse; alternative to #1340; planned in `160-agent-kv-reuse` |
| #1323 | server: `--kv-cache-cold-anchor last-user` | open | `78ec082` | 1 | 2026-11-11 | 2026-11-13 | opt-in KV policy |
| #815 | server: drop a partial trailing UTF-8 sequence from finished text | open | `130f3e2` | 1 | 2026-10-09 | 2026-11-13 | correctness; overlaps #1226; `130-server-protocol-batch` takes one of the two |
| #1226 | Replace invalid UTF-8 with U+FFFD in server JSON output | open | `4a02767` | 1 | 2026-10-18 | 2026-11-13 | correctness; overlaps #815; `130-server-protocol-batch` takes one of the two |
| #1131 | Read integer request seeds without rounding them through a double | open | `a9decfb` | 1 | 2026-09-28 | 2026-11-13 | correctness (seeded sampling): the child reads `seed` as a double (`ds4_server.c:3426`); planned in `130-server-protocol-batch` |
| #1139 | Reject malformed chunked HTTP request framing | open | `3373b75` | 10 | 2026-10-10 | 2026-11-13 | HTTP trust boundary plus chunked bodies; supersedes closed #423 |
| #1161 | server: report Anthropic stop_sequence when a client stop matches | open | `88c1c83` | 1 | 2026-10-01 | 2026-11-13 | protocol; planned in `130-server-protocol-batch` |
| #1162 | server: report max_output_tokens as the Responses incomplete reason | open | `15852d8` | 1 | 2026-10-01 | 2026-11-13 | protocol; planned in `130-server-protocol-batch` |
| #1137 | Close reasoning at the tail when an Anthropic budget is tiny | open | `e320fd7` | 3 | 2026-09-27 | 2026-11-13 | protocol and behaviour: injects a think-close in tight budgets |
| #1304 | server: accept OpenAI token-ID prompt arrays in /v1/completions | open | `5fb2ce1` | 1 | 2026-10-30 | 2026-11-13 | protocol |
| #1309 | Raise the server request body cap to 256 MiB | open | `6f9d7d1` | 1 | 2026-11-02 | 2026-11-13 | limit at a trust boundary (images) |
| #1017 | server: add --reasoning and --alias CLI options | open | `7bf7c48` | 1 | 2026-09-25 | 2026-11-13 | feature; overlaps #1307 |
| #1307 | server: add -a/--alias to rename the OpenAI model id | open | `7ad2a44` | 1 | 2026-10-31 | 2026-11-13 | feature |
| #1086 | server: in-process Prometheus metrics via GET /metrics | open | `4b16c78` | 3 | 2026-10-21 | 2026-11-13 | feature |
| #1203 | server: live prefill/decode status via GET /v1/status + macOS menu bar | open | `c4becb5` | 1 | 2026-10-10 | 2026-11-13 | feature |
| #1319 | server: add --loop-guard | open | `24bbd1d` | 1 | 2026-11-04 | 2026-11-13 | opt-in feature that changes output when engaged; reported on V4.1 |
| #186 | Compressed KV disk cache via streaming LZ4 | open | `1709dd5` | 2 | 2026-10-09 | 2026-11-13 | idea: lossless; vendors LZ4 (about 6K lines) |
| #302 | Structured outputs via llguidance | open | `667aeb9` | 39 | 2026-10-20 | 2026-11-13 | idea: a feature with an external Rust library |
| #1022 | server: opt-in auto-reduction of over-budget image histories | open | `8da90ed` | 3 | 2026-11-10 | 2026-11-13 | opt-in vision policy |
| #1153 | server: --image-prefix-snapshot reuses the text before a request's image | open | `ca9df3a` | 1 | 2026-09-29 | 2026-11-13 | vision KV reuse, written with Qwen's recurrent state in mind |
| #1221 | server: let the memory-text tier survive images | open | `2b720e8` | 1 | 2026-11-07 | 2026-11-13 | vision KV reuse |
| #1322 | server: let a request with an image use the disk KV cache | open | `15b7216` | 1 | 2026-11-05 | 2026-11-13 | vision KV reuse |
| #1343 | Save image conversations in the disk KV cache | open | `fffc283` | 2 | 2026-11-10 | 2026-11-13 | vision KV reuse; changes the stored payload |
| #1344 | Keep the images of a conversation in the embedding cache | open | `481e07c` | 1 | 2026-11-10 | 2026-11-13 | vision: no re-encoding of resent images |
| #1197 | Accept WebP images on macOS via ImageIO | open | `11f40b6` | 2 | 2026-10-20 | 2026-11-13 | vision input format; preferred over #1348 |
| #1348 | feat(image): decode WebP images | open | `ba65d95` | 2 | 2026-11-12 | 2026-11-13 | vision input format; vendors a decoder (about 2.7K lines) |
| #1182 | agent: persist Qwen3.8 Flash Next image sessions on Metal | open | `8cfbd22` | 2 | 2026-10-20 | 2026-11-13 | the agent part is removed in the child; the engine and kvstore save/restore of vision state is reachable |
| #1278 | server: persistent vision embedding cache | open | `deb6764` | 5 | 2026-10-28 | 2026-11-13 | idea only: stacked on #1277/#1276 (V4.1 image budgets) |
| #1229 | docs: add Qwen API client setup and diagnosis guide | open | `abd9b8b` | 1 | 2026-10-18 | 2026-11-13 | docs; compare with the child's `docs/CLIENTS.md` |
| #1350 | Agent: Option/Alt/Ctrl + arrows/backspace | open | `af03a2f` | 1 | 2026-11-13 | 2026-11-13 | open, low priority: linenoise word navigation, which the child CLI also uses |
| #1312 | ci: add a model-free pull request gate | open | `fa308b3` | 6 | 2026-11-11 | 2026-11-13 | idea: the child's own CI gate |
| #987 | Introduce welcome screen with DwarfStar logo | open | `383593f` | 9 | 2026-11-12 | 2026-11-13 | drop: CLI cosmetics, mostly `ds4-agent` |
| #1004 | Ignore the build outputs tests and benchmarks leave behind | open | `9932596` | 1 | 2026-11-02 | 2026-11-13 | drop: the child keeps its own ignore list |
| #1021 #106 #274 #374 #423 #489 #764 #811 #1159 #1327 | (closed, reachable) | closed | - | - | - | 2026-11-13 | closed unmerged and not in `upstream/main` (checked by patch and subject). No action. Superseded: #423 by #1139; #1159 and #1327 by #1284/#1288; #1021 by #1194/#1170 |

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
| `acce8da` | Prime the MTP predictor with the prompt during prefill | adopt -> `30-mtp-cycle` | taken. MTP decode on code +8.3% (tokens per cycle 1.83 -> 2.46), prose -1.5% (inside noise), MTP-mode prefill -4.0%. The tail flush runs in every trunk encoder, because the child's plain batch also takes MTP sessions. `82` found that the new drafts exposed verify rows whose arithmetic differed from single-token decode (F16/F32/Q8_0 matvec paths, the paired HC mixer, attention split geometry): on Q2 one prompt's MTP output left plain greedy output after 152 words. `82` made every verify row compute as a single decoded token (MTP == plain on both packs over 12 prompts and every depth), with MTP decode unchanged within noise (Q2 +0.0%, Q4 -1.3%) |
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

### #1056 (head `9eb4a12`, merged as `4ef9e4d`)

Every commit below is an ancestor of `upstream/main` and came in with the sync
to b3f5018 (90). The verdicts record what the child did with each before the
sync; 90's `sync-map.md` (sections 1-2) resolves each against the child's port.

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `e37f185` | Metal: add bounded SSD expert streaming for Qwen3.8 Flash Next | adopt -> `80-qwen-ssd-streaming` | `80` took it (phase A): routed-expert cache, admission, function constant 906 extended to all eleven of the child's routed kernels (IQ2 and Q2_K decode, Q4_K and MXFP4 rows, grouped rows, simdgroup and tensor-op tiles) with every routed row kernel built through the constant path; resident bitwise identical on both packs, streamed tokens identical to resident at 128 GiB and emulated 48 and 40 GB; only the `ssd_streaming` part of the engine-open refusal lifted. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `85d37ae` | Metal: stage only selected Qwen experts for MTP and cache overflow | adopt -> `80-qwen-ssd-streaming` | `80` took it: the Q2 pack's Q4/MXFP4 MTP layer stages only the selected experts; streamed Q2 MTP decode 13.4 -> 31.5 t/s (code) and 13.7 -> 35.0 (prose). In `upstream/main`: came in with the sync to b3f5018 (90) |
| `d6cbc77` | Metal: overlap Qwen decode expert reads with cached gate/up | adopt -> `80-qwen-ssd-streaming` | `80` took it within one I/O-overlap step with `81b9ebb`, `5cbdb6e`, `2ba92ab` and `47ca2eb` (alone, and with `81b9ebb`, it read neutral); slot masks also in the child's IQ2 mid kernel. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `cdfc0d5` | Metal: reuse Qwen IQ2 and HC inputs on M1 Max | adopt -> `40-dense-decode-kernels` (HC part); adopt -> `70-q2-kernels-m5` (IQ2 part) | `40` took the HC gate-mix reuse kernel for one decode token on M5 (F16, rank 320): byte-exact, plain decode +0.8% (12 pairs, bootstrap 95% CI +0.3..+1.5%), MTP unchanged. Not taken: the M1 Max gate, T >= 3 selection, the M1 benchmark scaffolding. `70` took the IQ2 part as `kernel_qwen4_moe_mid_iq2` (NR1 for one or two tokens, NR2 above) on M5, without the M1 gate and SSD slot plumbing: byte-exact against the generic kernel, Q2 decode moe_mid GPU time -17.9% after the specialization of the step before, Q2 plain decode +1.6%, MTP decode +2.1-2.6%. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `496b153` | Metal: adapt Qwen SSD MoE tiles and specialize low-bit prefill | idea -> `60-q4-expert-prefill` | `60` took tile width by tokens per expert as 16- and 8-token tails for each expert's remainder on the half tiles: bit-identical; routed expert GPU time at about 540 tokens moe_mid -1.2%, moe_down -4.9%, about 0 at 2050 tokens, an end-to-end effect below what the A/B harness resolves (most of `60`'s prefill gain comes from its Q4_K staging loads); `61` measured a 48-token tile for remainders 33..48 on GPU section time and dropped it (routed MoE time +1.1% at 8192, +3.3% at +2048, +5.1% at +512: the extra tail dispatch costs more than the narrower tile saves); `70` measured its low-bit M5 counterpart, remainder tails for IQ2_XXS/Q2_K, three times: bit-identical, Q2 prefill +2..+3% at 8192, +19..+22% at +512, +6..+8% at +2048, MTP prefill +8..+11% (code) and +5..+8% (prose), but every campaign read one decode metric wholly below zero (MTP-code decode -0.53% on the P1 tree, plain decode -0.77% on the final tree; a variant limited to batches under 4096 tokens read plain decode -1.1%, MTP decode -0.3%), while the same tails off in both builds and two same-binary runs with only prefill speed changed read 0; the tails cannot run in decode (the tiled path needs more than 64 tokens) and decode GPU time per pass was not slower, so the cost is in wall-clock decode after a denser prefill, about -0.3% on average, and the step was dropped; `81` landed them on M5 under a trade-off clause the owner approved (bitwise, prefill +10% or more, decode loss at most 2%): against `main` with `80`, Q2 prefill +18.5% at +512, +6.7% at +2048, +2.1% at 8192, MTP prefill +9.2% (code) and +9.6% (prose), decode -0.1% (plain), -0.9% (MTP-code), -0.7% (MTP-prose); the source of the decode cost is left open; the SSD sparse-tile part is M1 Max-only (33..128-token batches); `80` took only the routing-frequency field `5cbdb6e` needs. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `92f57fc` | Qwen: prepare MTP prefix caches and preserve predictor state | superseded by `acce8da` | #1062 primes the predictor during prefill. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `b86c8ae` | Metal: remove redundant Qwen MTP projections and expert work | idea -> `30-mtp-cycle` | taken as cache-only priming with the existing kernels: bit-identical, MTP-mode prefill +2.1%. Its M1 Max Q8 EH projection kernel is not taken. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `9e1429b` | Qwen: bound MTP staging to recover SSD expert cache capacity | adopt -> `80-qwen-ssd-streaming` | `80` took it for capacity: Q2 staging reserve 2.59 -> 1.42 GiB with MTP (1.17 GiB more cache, and less minimum RAM); speed neutral on the harness. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `e2b4a47` | Metal: plan Qwen SSD expert cache evictions once per batch | adopt -> `80-qwen-ssd-streaming` | `80` took it: eviction planned once per batch; streamed Q4 at emulated 48 GB decode +11.8% plain, +13.4%/+5.8% MTP, prefill +8..+19%; resident bitwise identical. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `81b9ebb` | Metal: overlap Qwen MoE down and MTP verification with SSD reads | adopt -> `80-qwen-ssd-streaming` | `80` took it within the I/O-overlap step (see `d6cbc77`); masks also in the child's Q2_K down kernel. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `5cbdb6e` | Metal: pipeline Qwen SSD MoE prefill and reuse Q2_K down rows | adopt -> `80-qwen-ssd-streaming` | `70` took the Q2_K down-row reuse as `kernel_qwen4_moe_down_q2k`; `80` took the SSD prefill pipeline within the I/O-overlap step: streamed prefill +6..+11% (Q4) and +10..+12% (Q2), MTP prefill +10..+20%, MTP decode +6..+9%; resident bitwise identical; its M1 Max Q2_K kernel dropped (the child has its own). In `upstream/main`: came in with the sync to b3f5018 (90) |
| `2960711` | Qwen: skip unused indexer queries in dense attention prefixes | open | Qwen prefill: drops the indexer query projection for chunks that stay entirely dense; chunks that cross the boundary keep the full projection, so rounding is preserved. No change covers attention prefill yet. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `2ba92ab` | Metal: compact streamed MoE prefill dispatches by active expert | adopt -> `80-qwen-ssd-streaming` | `80` took it within the I/O-overlap step: streamed MM dispatch over active experts; resident MM args grow to 2112 bytes, resident speed unchanged (pooled CIs across 0). In `upstream/main`: came in with the sync to b3f5018 (90) |
| `a50fecc` | Metal: streamline Q8 matrix-vector loads and reduction | drop | measured in `40` with `04c0867`: bit-identical on M5 (both oracles 0 bit differences) but neutral, plain decode +1.1% (4 pairs, CI -0.5..+3.2%). Kept only as the base of `9bff1ca`, then removed with its oracles in the final pass. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `bbbc012` | Metal: tune Qwen hyper-connection dispatches for M1 Max | drop | its HC-down tile is M1 Max prefill only. The M5 analogue of its 16-SIMD-group pair default, measured in `40`: MTP decode on code -1.7% (11 pairs), prose +0.3%. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `a37fd7f` | Metal: reuse IQ2 headers when staging MoE prefill tiles | drop | the M5 tensor path (`qwen4_load_raw16`) already reads the IQ2 header once per 16 values; the `stage16` branch it changes runs only with `DS4_QWEN4_MOE_MM_NAX=0`. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `13c53d9` | Metal: specialize Qwen IQ2 decode and reuse shared Q8 gate/up inputs | adopt -> `50-q4-expert-decode` (shared Q8 loop); adopt -> `70-q2-kernels-m5` (IQ2 part) | `50` took the shared Q8 gate/up loop as `qwen4_moe_shared_q8_mid` in the Q4_K per-token kernel: byte-exact, MoE mid -5.8% GPU time, plain decode +1.3% (14 pairs, 95% CI +1.0..+1.7%). `70` took the IQ2 part (see `cdfc0d5`), whose shared Q8 slot calls the same helper. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `9a8462a` | Metal: streamline Qwen Q2 down loads and shared expert row reuse | adopt -> `70-q2-kernels-m5` | `70` took its shared Q8 row reuse as `qwen4_moe_shared_q8_rows`, first in the Q4 MXFP4 down kernel (Q4 decode moe_down GPU time -2.5%, bit-identical), then with the packed loads and tail-free blocks in `kernel_qwen4_moe_down_q2k` (Q2 decode moe_down -2.0%, plain decode +0.3%, MTP decode +1.2%). In `upstream/main`: came in with the sync to b3f5018 (90) |
| `f47db4f` | Merge antirez/main at 8db1d1d into qwen-kernel-opt | merge | - |
| `0024ca0` | fix(qwen): unify prefill chunk resolution and test generation parity | drop | chunk-invariant prefill changes logits. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `2d6a207` | fix(qwen): preserve reference prefill arithmetic with explicit projections | drop | chunk-invariant prefill changes logits. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `04c0867` | fix(metal): preserve Q8 dot arithmetic to eliminate late decode drift | drop | repairs `a50fecc`; dropped with it. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `89986c3` | fix(qwen): retain prefill attention arithmetic across Metal partitions | drop | chunk-invariant prefill changes logits. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `9bff1ca` | perf(metal): reuse Qwen decode activations across four Q8 output rows | drop | measured in `40` with the gate widened to M5: bit-identical and selected for 2560->10240/6144 and 6144->2560, but plain decode +0.3% (14 pairs, CI -0.5..+1.9%). The Q8 projections do not limit M5 decode. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `11811b9` | perf(metal): reuse half operands for large Qwen SSD MoE prefill | drop | already in the M5 tensor path: level 2 converts x to half once and the mid epilogue writes the half copy the down tiles read. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `fd0c24a` | test(qwen): repair compact MoE checks after half-kernel extraction | drop | not taken: it adapts the compact test to `11811b9`'s half-kernel extraction, which the child did not take; `80` runs `2ba92ab`'s version of the test. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `a6ad636` | test(qwen): add sparse and long-context MTP replay diagnostics | drop | as written it needs SSD streaming; in `30-mtp-cycle` the bitwise draft gate of the harness covers the cache-only priming it was meant to check. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `47ca2eb` | Metal: enable Qwen SSD prefill overlap on all devices | adopt -> `80-qwen-ssd-streaming` | `80` took it within the I/O-overlap step: the prefill overlap on every device. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `028b43f` | Metal: stabilize Qwen HC arithmetic and extend M5 tuning to M6 | drop | the child's `_pf` kernel already spells the F16 op order, and `cdfc0d5`'s reuse kernel is byte-exact against it without this commit (checked in `40`); the M6 gate does not matter on M5. In `upstream/main`: came in with the sync to b3f5018 (90) as upstream code; on M5 resident it is not selected (90's sync map, section 1) |
| `b1af94b` | Merge antirez/main into qwen-kernel-opt | merge | - |
| `089d966` | Qwen: make MTP prompt preparation configurable | idea -> later MTP change | `DS4_QWEN4_MTP_PREFILL` can skip historical predictor rows; it changes the draft context and can lower acceptance, and its author keeps the default on until acceptance and wall time are measured. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `81ee4ba` | Qwen: honor Metal's SSD streaming memory budget | adopt -> `80-qwen-ssd-streaming` | `80` took it by hand (it sits on later PR commits): budget = min(87.5% RAM, Metal's recommendation), one Qwen admission for automatic and explicit cache requests, admitted statics stay lockable. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `4642526` | Metal: optimize Qwen Q4 decode and verify SSD parity | split: Q4 decode -> later Q4 change | `80` took none of it: its SSD tests pin the PR's own Q4 decode rewrite and test scaffolding from untaken commits; the child checks Q4 addressed against resident at T 1, 17, 32, 33 and 128. The Q4 decode loads stay an idea for a later Q4 change. In `upstream/main`: came in with the sync to b3f5018 (90) |
| `ee79f22` | Metal: accelerate Qwen MXFP4 prefill and batched down rows | already in main | came in with the sync to b3f5018 (90). MXFP4 prefill half-block staging with byte-aligned loads; LUT and accumulation unchanged (1,048,576-case oracle). The NR2 down-row reuse is M1 Max only (function constant 907). Overlaps the child's `60` Q4 prefill tiles; bit-identity against them not checked |
| `b96a12b` | Metal: optimize Qwen Q4 SSD prefill on M1 Max | already in main | came in with the sync to b3f5018 (90). Not on M5: K32 NT4 tiles, half shadows at 8192+ and Q8 unpack are gated to M1 Max (M2-M4 since `0231312`) |
| `f32a16a` | Research: archive Qwen Q4 SSD scheduling and decode experiments | docs | `misc/qwen-radical-2026-09-30`; upstream `5c9ed63` removes the research dumps again |
| `0231312` | Metal: extend Qwen M1 Max tuning to M2, M3 and M4 | already in main | came in with the sync to b3f5018 (90). Not on M5: M5/M6 keep their defaults |
| `575369b` | Research: isolate Qwen prefill arithmetic and token drift | docs | shows that `2d6a207`'s policy changed greedy tokens (step 59 / step 20), which confirms the child's drop |
| `37f66ba` | Metal: restore main arithmetic for resident Qwen prefill | already in main | came in with the sync to b3f5018 (90). Resident prefill back on main's arithmetic; `a279860` later did the same for SSD, which is what the child's `80` already guarantees |
| `8d543ec` | Merge antirez/main into qwen-kernel-opt | merge | - |
| `f2e6030` | Merge upstream/main into qwen-kernel-opt | merge | - |
| `9eb4a12` | Merge upstream/main into qwen-kernel-opt | merge | - |

### #1115 (head `c544020`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `485902a` | qwen4: TurboQuant KV cache for the Qwen3.8 attention caches (2..8-bit) | drop | quantizes the KV cache: loses precision |
| `f5e419d` | server: render Qwen prompts the way the fixed template does | adopt -> `92-qwen-template-fix-1115` | Qwen branches only, GLM/DeepSeek renderers and markers dropped. A 38-case render corpus: 24 byte-identical, 14 differ only in the PR's four classes (reasoning inside content, `preserve_thinking=false`, tool-schema escapes, effort aliases). Two PR bugs fixed in the port: escaped printable ASCII in schemas was re-escaped, and the closing tool-response marker in the trace table was misspelled. `chat_template_kwargs` wins over the top-level key in any order. `tests/template_parity_ab.py` not ported (its section in `docs/TESTING.md` became `--qwen-render` usage). Not in `upstream/main` |
| `c544020` | tests: plumb the disk budget the retention test claims to set | adopt -> `92-qwen-template-fix-1115` | with `f5e419d`'s retention test. Q4 run: 15 checks pass, 1 inconclusive (D1, neither arm replayed the opener); live reuse 1279/1281 tokens, 1281/1290 after a restart (the PR reports 1279/1281 and 1281/1281) |

### #1118 (head `25def38`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `25def38` | server: make the idle prefill quantum configurable | open | reachable here: with `--batched-session` the server feeds Qwen prompts in 2048-token quanta (`server_prefill_quantum_for`), below the engine's 8192-row prefill chunk. The PR only adds an env knob and keeps the 2048 default; measured on CUDA TP. Upstream `7da9535` (in `upstream/main`) makes the idle quantum the engine's prefill cap, but `cad7933` limits that to DeepSeek V4.1: after the sync to b3f5018 (90) Qwen still gets 2048-token quanta |

### #1238 (merged, head `6946209`)

Every commit is an ancestor of `upstream/main` (same SHAs) and came in with the
sync to b3f5018 (90). Upstream measured on M5 Max Q2: decode +10-17% at 2-32K,
prefill +4..+23% up to 8K and -4..-7% from 14K; teacher-forced decode logits
reported bit-exact on 112 rows. In this child (Q4 on M5, A/B against the
pre-sync `main`, `--bitwise`): plain decode +4.1%, MTP decode unchanged
(`97-mtp-verify-speed`), prefill -0.3..-1.0% (`95-sync-deferred-perf`).

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `47c34fb` | Qwen IQ2_XXS decode mid: stage grid/sign tables in threadgroup memory | already in main | came in with the sync to b3f5018 (90). Same kernel family as the child's `kernel_qwen4_moe_mid_iq2` (`70`); 90 (D4) took it as the M5 path, byte-exact against `mid_iq2` in the kernel suites |
| `fd16a72` | Specialize Qwen IQ2_XXS/Q2_K decode expert rows on M5 | already in main | came in with the sync to b3f5018 (90). M5 function constants nsg 8 / nr 1; replaced the child's `70` specialization on M5 (90 D4) |
| `d2ae13e` | Qwen decode: read PLE n-grams while the GPU runs layer 0 | already in main | came in with the sync to b3f5018 (90). The child already reads n-gram rows concurrently (`d0b7434`, in its base) |
| `b440c3c` | Qwen F32 row dot: unroll so decode GDN alpha/beta loads issue ahead | already in main | came in with the sync to b3f5018 (90); in-order sum kept |
| `4ed25e4` | Qwen single-token MoE: fold the weighted reduce into the down kernel | already in main | came in with the sync to b3f5018 (90). Touches the child's `kernel_qwen4_moe_down_q2k` and MXFP4 down; byte-exact against the child's down + reduce (90 D4 kernel tests), whose separate path was removed |
| `a3a7e2d` | Qwen Q2_K row dot: two aligned word loads per lane | already in main | came in with the sync to b3f5018 (90). Its half-alignment bug is fixed by `b3f5018`; both came in together |
| `6b7cb44` | Qwen decode router: read a BF16 copy of the BF16-valued F32 rows | already in main | came in with the sync to b3f5018 (90). Same values, half the traffic, if every router weight is BF16-representable (90's gates: tokens identical on both packs, Q4 logits bitwise) |
| `9000fb7` | Qwen decode: hc norm prefetches its down projection into the system cache | already in main | came in with the sync to b3f5018 (90) |
| `0f12ea4` | Qwen prefetch: factor the pending-range binding | already in main | came in with the sync to b3f5018 (90); refactor |
| `6605c3c` | Qwen attention merge: load the split maxima sixteen at a time | already in main | came in with the sync to b3f5018 (90) |
| `f768d14` | Qwen attention decode: two query heads per simdgroup over six simdgroups | already in main | came in with the sync to b3f5018 (90); `82`'s identity test passes after it (36/36 on Q4 and Q2) |
| `b5aedb9` | Qwen hyper-connections: load the norm squares and inject partials ahead of their in-order sums | already in main | came in with the sync to b3f5018 (90). Touches the HC kernels of the child's `40` |
| `6946209` | DS4_QWEN4_NO_PLE_OVERLAP restores up-front PLE staging | already in main | came in with the sync to b3f5018 (90); diagnostic switch |

### #1154 (head `a3f3744`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `c6b42b7` | Overlap Qwen PLE reads with prefill GPU work | in main, modified | landed as `347c2e1`, plus `c97964b` (token validation before prefetched staging); came in with the sync to b3f5018 (90). Prefill +3.9% (8-run A/B, M5 Max Q4 16K), logits exact (author) |
| `a3f3744` | Test Qwen PLE prefetch parity and recovery | in main, modified | landed as `64baaa0`; came in with the sync to b3f5018 (90) |

### #1198 (head `1fbcf8b`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `1fbcf8b` | metal: reuse Q4_K raw loads in Qwen NAX prefill | in main, modified | landed as `e73e516`; came in with the sync to b3f5018 (90). It ports the register-reuse part of the child's `08ea4d7`: 90 keeps one implementation. Upstream `ef8e536` extends it to Q2_K (90 D8 checks row alignment first) |

### #1179 (head `79c914c`, WIP, no description)

None of these commits exists locally or in `upstream/main`. Per-commit stats
came from the GitHub API, and the diffs of the small commits were read. The
base predates #1238 and the #1056 merge. Comments in `5c41319` show the author
tests a Q8_0-expert GGUF.

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `bb42a6d` | Keep the one-token arithmetic in Qwen3.8 verify rows | superseded by `f25afe0` | the child's `82` already makes every verify row compute as single-token decode |
| `b716e67` | Test Qwen3.8 verify rows against plain decoding bit for bit | idea -> later MTP change | `tests/test_qwen4_verify_exact.c` could complement `82`'s identity check; not compared to it |
| `7e6ab2f` | Draft Qwen3.8 MTP cycles from prompt lookups | open | prompt-lookup drafting inside the MTP cycle (+429 lines in `ds4.c`). Verification decides acceptance, so greedy output should not change; not verified. Needs MTP decode on code and prose and acceptance, after 90 |
| `af2b98c` | Tune Qwen3.8 decode kernels on M3 Ultra | open | edits `qwen4.metal` kernel bodies (+29/-30), not only gates; not checked whether M5 paths change |
| `4022f65` | Batch Qwen3.8 sessions with the one-token arithmetic | open | `--batched-session` path; compare with `82` |
| `7cd48a9` | Speed up Qwen3.8 prefill reads and expert tiles | open | no description; prefill chunk and tile changes. Bit-identity unknown |
| `360af6b` | Fuse the Qwen3.8 one-token decode kernels | open | 726 new lines in `qwen4.metal` (`kernel_qwen4_gdn_fused`, `hc_ssp/apply/down/up`, `moe_mid_route`, `moe_down_reduce`, `q8_concat_conv`), each behind a `DS4_QWEN4_*` kill switch; `87ff38f` later restores mixer bit-exactness. The largest decode idea here: re-measure after #1238 lands, with a bitwise gate |
| `78aaa7b` | Run Qwen3.8 verify-row delta nets in one kernel | open | MTP verify cost; must keep `82`'s single-token arithmetic |
| `4496b80` | Draft Qwen3.8 MTP tokens inside the verify pass | open | MTP cycle restructure (+417 lines in `ds4.c`); conflicts with the predictor chain of `30` and `82` |
| `a4d4804` | Replay Qwen3.8 lookup states and re-anchor copy drafts | open | depends on `7e6ab2f` |
| `b15e31d` | Speed up Qwen3.8 decode attention | open | overlaps #1238 `f768d14`/`6605c3c`; take whichever measures faster with bitwise logits |
| `29eed36` | Commit Qwen3.8 decode work every two layers | open | despite its subject it changes prefill (`qwen4_graph_forward_tokens`): flushes every 2 layers after `flush_layer`. Scheduling only |
| `967ed75` | Poll Metal command buffers before blocking on them | drop | spin-wait; reverted by `79c914c` in the same PR |
| `7b8ae4a` | Draft Qwen3.8 MTP rows from BF16 token tables | open | lets `qwen4_graph_mtp_spec` run with a BF16 `token_embd`; check which embedding type the child's packs use |
| `5c41319` | Keep the Qwen3.8 prefill head to Q8_0 experts | open | disables the short prefill "head" chunk unless every expert is Q8_0, because other types "round by chunk size". Not checked whether the child's head chunking changes Q2/Q4 logits: a possible correctness lead |
| `87ff38f` | Keep the Qwen3.8 decode mixer bit-exact with the original kernels | open | fix for `360af6b` |
| `b7093a2` | Fix Qwen Metal grouped-expert pointer address space (#5) | open | address-space qualifier in `qwen4_q8_group`, the PR's own new code; not present in the child |
| `79c914c` | Block on Metal command buffers instead of spinning a CPU core | drop | net effect with `967ed75` is none |

### #1149 (head `c97a1a9`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `2c860eb` | Metal: run Qwen3.8 QSA prefill attention on the tensor units | drop | changes logits: max \|dlogit\| 1.14 / 0.91 / 1.68 at 8K / 32K / 64K (top-1 identical). Rejection rule. Prefill +6.9% / +2.8% / +7.4% on M5 Max |
| `c97a1a9` | Metal: compare tensor-unit attention against the classic mm kernel | drop | test for the dropped kernel |

### #1150 (head `04dbebe`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `ce6d991` | Metal: defer hyper-connection residual writes into the next stream norm | open | planned in `140-deferred-hc-residual`. New `kernel_qwen4_hc_combine_norm_rows`, memcmp-exact for T = 3..256 (author). Prefill +2.4% at 8K, +1.3% at 32K (M5 Max Q4). Eager writes kept for T <= 3, PLE-feeding layers and the last trunk layer. Needs a check against the child's `40` HC reuse kernel, `30`'s priming and the steering FFN flush |
| `04dbebe` | fix(qwen4): keep CUDA builds linking with the deferred HC write | drop | CUDA only |

### #1185 (head `777f4e3`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `777f4e3` | Qwen3.8 exact MTP: draft from the sampled token, defer the residual, allow depth 3 | open | planned in `150-exact-sampling-mtp`. Reachable through `--mtp --mtp-exact-sampling` at temperature > 0. Greedy output byte-identical (author, 3 prompts, both depths); distribution permutation test p = 0.57. Measured on a Q8_0-down GGUF on base `0aaea5a`: +11-15% code/list at forced depth 3, +1-3% with the adaptive policy, prose -1.3%. It removes `qwen4_session_draft`, so it conflicts with the drafting of `30`/`82` |

### #1328 (head `2d48e3b`)

All six commits form one change, built on `b3f5018`; planned in
`170-ssd-decode-handshake`, after 90.

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `43d4bb9` | Overlap streamed Qwen decode layers with their expert loads on Metal | open | encodes the layer before its experts are known; the CPU loads them between two `MTLSharedEvent`s. Bit-identical claimed (full-vocab frontier logits, 64-token greedy). M4 Pro 48 GB Q2 streamed decode 17.4-18.2 -> 19.5-19.7 t/s at 4K; MTP neutral. Allocates the whole expert-cache budget's slabs on first use |
| `d1f6d00` | Block on the handshake's arrival event; match the ordinary path on failure | open | part of the same change |
| `9b7b1da` | Drop the early-commit switch | open | part of the same change |
| `e11a04e` | Harden the handshake's failure exits and mark released experts in flight | open | part of the same change |
| `fcbd38f` | Retire in-flight marks by sequence at arrival | open | part of the same change |
| `2d48e3b` | Return a failed load's reservations everywhere; retire marks on completion | open | part of the same change; overlaps #1125's slot-leak fixes |

### #1184 (head `62ba62c`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| (3 commits) | Enable measured Qwen / DeepSeek Metal choices on M4 | drop | each edit adds M4 to an existing device check; M5 paths unchanged |

### #1125 (head `6c41f9b`)

Checked on the child's `main` and on `upstream/main`: the Qwen SSD path
(`ds4_gpu_qwen4_moe_stream_tensor`) calls `prepare_selected_batch` and no other
cache entry point. `load_selected_missing` and `prune_global` are reached only
from the DeepSeek graph's seeding (`metal_graph_seed_streaming_expert_cache_*`)
and from `ds4_gpu_routed_moe_one_tensor`.

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `a0fe413` | Return streamed-expert slab slots on every load error path | adopt -> `120-correctness-batch` (reachable part only) | not in `upstream/main`; `120-correctness-batch` ported the Qwen-reachable part as `ds4_gpu_stream_expert_slab_claim_slot`, with the give-back loop of `prepare_selected_batch` as the shared `ds4_gpu_stream_expert_give_back_buffers` (`170` reuses it). Reachable: a failed slot lock in `alloc_slab_slot` (through `prepare_load_buffers`) loses the slot for the process. The child's `prepare_selected_batch` already returns uninstalled reservations on its `gate_up_ready` error path. The `load_selected_missing`, `get_protected` and pending-load parts are not reachable from Qwen |
| `2cf7986` | Mark GPU-copy expert entries in flight until their blit runs | not reachable from Qwen | the GPU-copy source is used only by the seed paths, which only the DeepSeek graph calls |
| `a6fc294` | Keep per-layer expert cache counts in sync with live entries | adopt -> `120-correctness-batch` | not in `upstream/main`; ported by `120-correctness-batch` (Q4 gates, parity and bitwise A/B pass). `clear_layer` forces the count to 0 under in-flight entries; `prepare_selected_batch` calls it on its error paths |
| `6c41f9b` | Skip in-flight entries when pruning the global expert cache | not reachable from Qwen | `prune_global`'s callers are the seed paths and `ds4_gpu_routed_moe_one_tensor`, on the child's `main` and on `upstream/main` |

### #1126 (head `242da6b`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `242da6b` | Resolve the keep-alive pipeline before starting keep-alive threads | adopt -> `120-correctness-batch` | not in `upstream/main`; ported by `120-correctness-batch` (Q4 gates, parity and bitwise A/B pass). `ds4_gpu_queue_keepalive_thread` calls `ds4_gpu_get_pipeline`, which reads and writes `g_pipeline_cache` (an `NSMutableDictionary`) while the main thread compiles pipelines for the first prefill (`ds4_metal.m:11270`) |

### #1128 (head `fa7bc8a`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `d7b0b31` | Use the BF16 mat-vec kernel when in_dim is not a multiple of 16 | not reachable from Qwen | GLM/DeepSeek vision patch embeddings; Qwen's is `3*P*P` (a multiple of 16) |
| `82ffb0c` | Reject partial head groups in indexed mixed-batch attention | not reachable from Qwen | `ds4_gpu_attention_indexed_mixed_batch_heads_tensor` is DeepSeek graph only |
| `3cbbb19` | Reject visual masks with more raw keys than positions | not reachable from Qwen | no caller in the child |
| `ad14a5f` | Bound n_rot in the Qwen4 indexer block-key kernels | adopt -> `120-correctness-batch` | not in `upstream/main`; ported by `120-correctness-batch` (Q4 gates, parity and bitwise A/B pass). Latent guard: the kernels rope into `float tmp[64]` (`metal/qwen4.metal:1370`, `1532`); `n_rot` is 64 in the shipping model |
| `fa7bc8a` | Only hand the Qwen4 selector tile maxima the scorer actually wrote | adopt -> `120-correctness-batch` | not in `upstream/main`; ported by `120-correctness-batch` (Q4 gates, parity and bitwise A/B pass). Latent: the selector gets `g->tile_max` for every `n_sparse <= 2` batch (`ds4.c:32412`), while only the vector scorer writes it. Adds `ds4_gpu_qwen4_idx_score_emits_tile_max()` |

### #1288 (head `0252371`, includes #1284)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `def0f60` | Server: do not let chat content inject control tokens | next sync | not in `upstream/main`; planned in `130-server-protocol-batch`. #1284 base: tracked trusted-byte mask, `ds4.c` and kvstore plumbing. Its renderer part is DeepSeek V4.1 (deleted in the child) |
| `138cb39` | Server: keep buf_printf output untrusted in the tracked mask | next sync | #1284; planned in `130-server-protocol-batch` |
| `e66797e` | Server: generalize raw tool replay and inspect-only vocab | next sync | needed by the Qwen mask; planned in `130-server-protocol-batch` |
| `aa982ec` | Server: mask GLM renderer syntax | not reachable from Qwen | GLM renderer removed |
| `6ee4a73` | Server: mask Qwen renderer syntax and test GLM/Qwen injection | next sync | Qwen prompt-injection fix (`<\|im_end\|>` and other markers in message data); planned in `130-server-protocol-batch`. Supersedes closed #1327 and open #197 (DeepSeek only) |
| `0252371` | Server: test vision-token spellings and image-marker counts | next sync | tests; planned in `130-server-protocol-batch` |

### #1155 (head `8f61ece`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `8a8b2a2` | server: report rebuilt prefill progress against the full prompt | next sync | reported on Qwen3.8 (#1114); planned in `130-server-protocol-batch` |
| `8922c81` | server: treat detached backend state as a live cache miss | next sync | false live-cache hit after a backend reset; planned in `130-server-protocol-batch` |
| `8f61ece` | fixup! server: treat detached backend state as a live cache miss | next sync | squash with the previous one |

### #1169 (head `83b3e88`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `6752300` | Preserve exact tool-call replay across KV checkpoint restores | open | planned in `160-agent-kv-reuse`. Tool memory, EOS commitment, checkpoint serialization; Qwen-heavy. Required by #1206 |
| `83b3e88` | Match both tool-turn checkpoint log spellings in replay test | open | test |

### #1175 (head `4e113c7`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `bc41bb5` | server: validate parent history before live tool KV reuse | next sync | planned in `130-server-protocol-batch`. The live tool-output tier reused the whole KV without checking earlier history |
| `4e113c7` | server: retain user follow-ups in Responses tool continuations | next sync | same area |

### #1058 (head `889b2c0`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `bd641ab` | Key tool-conversation KV checkpoints by the client-visible transcript | open | restart reuse (reported on Qwen, #1053) |
| `355a803` | Add a restart KV restore smoke test for tool conversations | open | test |
| `2381398` | Keep Qwen visible keys byte-identical to the echoed answer | open | Qwen-specific |
| `37b5d54` | Log why a longer KV cache entry was skipped at lookup | open | logging |
| `889b2c0` | Let the KV restore smoke test run GLM and from any cwd | drop | GLM test variant |

### #1059 (head `0e4d448`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `2d206c2` | server: find token-text disk stores by the request's rendered tokens | open | token-text tier lookup |
| `0e4d448` | kv cache: load the longer of the prompt-text and rendered-token disk hits | open | same |

### #1020 (head `9cbf7e5`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `07e0478` | kvstore: stamp checkpoints with a behavioral tokenizer fingerprint | open | new trailer section; old checkpoints need a compatibility decision |
| `aa0b462` | engine: hash tokenizer content, never struct bytes, in fingerprint | open | same |
| `5915b7b`, `9cbf7e5` | merges | merge | - |

### #1170 (head `80db39c`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `b46cff2` | Keep the disk KV checkpoint the next request loads when storing an evict snapshot | open | eviction order; planned in `160-agent-kv-reuse` |
| `fd827a2` | Test that the protected KV checkpoint survives earlier victims | open | test |
| `80db39c` | Drop the evict-snapshot grace period and tighten protection tests | open | same |

### #1281 (head `296a512`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `e9be611` | server: a short live token-prefix stub no longer hides the disk cache | open | KV tier order; planned in `160-agent-kv-reuse` |
| `296a512` | server: persist a live session before a rewind discards most of it | open | not checked how rewind applies to Qwen's recurrent state (snapshots only) |

### #1137 (head `e320fd7`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `7084696` | Close reasoning at the tail when an Anthropic budget is tiny | open | adds `--anthropic-thinking-min-budget`; changes output only when the budget is <= 1024 |
| `efaaba7` | Keep the closed tail in the tool checkpoint transcript | open | same |
| `e320fd7` | Close reasoning only when the prompt tail is inside a think block | open | same |

### #1139 (head `3373b75`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `bdec260` … `3373b75` (10) | chunked transfer decoding and strict framing/header validation | open | HTTP trust boundary. Adds chunked bodies (closed #423's feature) with strict rejection. Take it as one unit, with the server unit tests |

### #1086 (head `4b16c78`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `beb1093` | server: in-process Prometheus metrics via GET /metrics | open | low priority; feature |
| `3821076` | gitignore: ignore tests/test_metrics binary | open | low priority |
| `4b16c78` | server: count prefill tokens on the per-chunk display callback | open | low priority |

### #1022 (head `8da90ed`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `fa0af86` | server: opt-in auto-reduction of over-budget image histories | open | low priority; opt-in (`DS4_VISION_KEEP_IMAGES`), default unchanged |
| `aba2f94` | Merge origin/main | merge | - |
| `8da90ed` | server: size the vision embedding cache to the KEEP budget | open | low priority; overlaps #1344 |

### #1343 (head `fffc283`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `097e980` | Keep the live text tier when the checkpoint holds an image | open | image identity in rendered markers |
| `fffc283` | Save image conversations in the disk KV cache | open | the payload gains image identities; check checkpoint-format compatibility |

### #1197 / #1348 (alternatives)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `fd79d59` (#1197) | Accept WebP images on macOS via ImageIO | open | small, macOS-native, no vendored code; preferred over #1348 for this child |
| `11f40b6` (#1197) | Keep WebP ImageIO draws upright and test pixel orientation | open | same |
| `3963d5a` (#1348) | feat(image): decode WebP images | drop | vendors a 2.7K-line decoder; #1197 covers macOS with ImageIO |
| `ba65d95` (#1348) | test(image): fail the WebP truncation check if it tries no cut | drop | with the above |

### #1182 (head `8cfbd22`)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `85429f6` | Preserve Qwen3.8 Flash Next image sessions on Metal | idea -> later vision change | the child has no `ds4-agent`. The engine and kvstore save/restore of Qwen vision state (`ds4.c` +114) could back server-side image checkpoints. Overlaps #1343 |
| `8cfbd22` | Keep visual session file identities stable across macOS remounts | idea -> later vision change | same |

### #186, #302, #1278, #1312 (multi-commit ideas)

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `7213dd9`, `1709dd5` (#186) | Compressed KV disk cache via streaming LZ4 | idea -> later change | lossless LZ4 on the disk KV payload; vendors LZ4 (about 6K lines) and touches `ds4_agent.c`. Measure checkpoint size, write/read time and SSD wear against reuse latency |
| 39 commits (#302) | Structured outputs via llguidance | idea -> later change | external Rust dependency; a feature, not performance |
| 5 commits (#1278) | server: persistent vision embedding cache | idea -> later vision change | only the last commit (persistent vision embedding cache on disk) is model-agnostic; the rest is V4.1 (#1276/#1277) |
| 6 commits (#1312) | ci: add a model-free pull request gate | idea -> later change | adapt it to the child's `make test` target list (StarForge rule 19: check that the named tests ran) |

### Single-commit PRs

| Commit | Subject | Verdict | Reason |
|---|---|---|---|
| `7b0e2aa` (#1326) | prompt prefix: close imported Qwen assistant turns once | adopt -> `120-correctness-batch` | not in `upstream/main`; ported by `120-correctness-batch` (Q4 gates, parity and bitwise A/B pass). Bug in the child: `ds4_prompt_prefix_append` pushes EOS (`<\|im_end\|>`, `ds4.c:29722`) after `qwen4_chat_close` already closed the turn. Changes prompt tokens for `--prefix-file` only |
| `46374b0` (#1325) | server: evaluate Qwen's `<\|im_end\|>` after a thinking answer | next sync | planned in `130-server-protocol-batch`. The reasoning-free live key ends with an `<\|im_end\|>\n` that was never evaluated, so the next turn sees an unclosed answer |
| `480f2ae` (#1140) | Let Qwen and GLM make several tool calls per turn | next sync | planned in `130-server-protocol-batch`. Generation stops after the first Qwen tool call; the GLM parts drop out. Check together with #1251 |
| `c98b444` (#1251) | server: stream Qwen tool-call arguments over OpenAI SSE | next sync | planned in `130-server-protocol-batch`. Qwen `<function=…>` syntax in the live translator; the DSML/GLM parts drop out |
| `1074193` (#1134) | Keep mid-conversation system messages in place | next sync | planned in `130-server-protocol-batch`. Qwen renderer; reported 14.8K re-prefill -> 17 tokens with Claude Code |
| `00df8df` (#1088) | recover unterminated reasoning as content when the turn completed | next sync | planned in `130-server-protocol-batch`. A completed turn without `</think>` lost its answer |
| `115ec43` (#1163) | unterminated tool call defers to parse-failure recovery | next sync | planned in `130-server-protocol-batch`. `finish_reason: "error"` on an HTTP 200 |
| `24c6197` (#1157) | Find the cold KV anchor in ChatML prompts | next sync | planned in `130-server-protocol-batch`. The Qwen vocabulary sets `user_id`/`assistant_id` to -1, so the anchor is never found |
| `5cc8f27` (#1212) | Reload evicted Qwen tool turns for clients that send reasoning back | open | KV reuse (Pi-style clients); planned in `160-agent-kv-reuse` |
| `c7a0d8a` (#1206) | preserve Qwen Responses final-answer cache reuse | open | needs #1169; planned in `160-agent-kv-reuse` |
| `ce9fd0b` (#1194) | heal the forked live checkpoint on a token-mismatch miss | open | KV reuse; planned in `160-agent-kv-reuse` |
| `06d48c0` (#1200) | retain bounded Qwen Responses prompt checkpoints | open | KV reuse, 38.4 s -> 0.98 s return in the author's workflow; planned in `160-agent-kv-reuse` |
| `659889d` (#1228) | Preserve bounded cold cache prefixes for long API prompts | open | KV reuse; planned in `160-agent-kv-reuse` |
| `fd7eda0` (#903) | save continued checkpoints after crossed frontiers | superseded by `88ac7a1` | same rule as #1342; take one of #903/#1340/#1342 |
| `702d273` (#1340) | align the continued KV checkpoint step with the prefill chunk schedule | open | changes the default interval to 8192; the Qwen prefill chunk is 8192, so check its `ds4_test_default_prefill_caps` values for Qwen |
| `88ac7a1` (#1342) | write a continued KV checkpoint at the first chunk past each step | open | independent of the chunk schedule; preferred over #903; planned in `160-agent-kv-reuse` |
| `78ec082` (#1323) | `--kv-cache-cold-anchor last-user` | open | low priority; opt-in |
| `402c80b` (#1216) | find the longest text-prefix checkpoint in one pass | open | same result, faster lookup; planned in `160-agent-kv-reuse` |
| `4ca5111` (#1258) | skip store attempts when the session has no checkpoint | open | planned in `160-agent-kv-reuse` |
| `caad877` (#1280) | continued checkpoints that actually land during a long read | open | measured on V4.1; verify the Qwen chunk listener first |
| `130f3e2` (#815) | drop a partial trailing UTF-8 sequence from finished text | next sync | invalid UTF-8 in final JSON; `130-server-protocol-batch` takes one of #815/#1226 |
| `4a02767` (#1226) | Replace invalid UTF-8 with U+FFFD in server JSON output | next sync | broader than #815 (all escapers); `130-server-protocol-batch` takes one of the two |
| `a9decfb` (#1131) | Read integer request seeds without rounding through a double | next sync | planned in `130-server-protocol-batch`. Seeds above 2^53 and negative values; the child parses `seed` with `json_number` into a double |
| `88c1c83` (#1161) | report Anthropic stop_sequence when a client stop matches | next sync | protocol field; planned in `130-server-protocol-batch` |
| `15852d8` (#1162) | report max_output_tokens as the Responses incomplete reason | next sync | protocol field; planned in `130-server-protocol-batch` |
| `5fb2ce1` (#1304) | accept OpenAI token-ID prompt arrays in completions | open | protocol; validate ids against the vocabulary (trust boundary) |
| `6f9d7d1` (#1309) | Raise the server request body cap to 256 MiB | open | needed with 256 images per request (`f5127df`, in `upstream/main`); adds `DS4_SERVER_MAX_BODY_MB` |
| `4fbba5d` (#1145) | Refuse duplicate tensor names and name the file of a missing tensor | adopt -> `120-correctness-batch` | not in `upstream/main`; ported by `120-correctness-batch` (Q4 gates, parity and bitwise A/B pass). GGUF trust boundary: `model_find_tensor` is first-match and nothing rejects a repeated name |
| `f63ae1d` (#1156) | Fix the iq1_s and iq4_nl block sizes in the GGUF type table | adopt -> `120-correctness-batch` | not in `upstream/main`; ported by `120-correctness-batch` (Q4 gates, parity and bitwise A/B pass). Bug in the child (`ds4.c:2086-2087`): iq4_nl tensors are sized at about a third |
| `b3f552f` (#1219) | Make the BPE tokenizer and detokenizer linear | open | Qwen BPE reaches `bpe_emit_piece`. Token-identical claimed. Gate: token identity on a large corpus plus `make test-qwen4-ngrams` |
| `142d95b` (#873) | fix bpe_emit_piece's O(n^2) merge loop | superseded by `b3f552f` | the same heap approach, smaller; take it if #1219 is too large |
| `4104bd0` (#942) | Detach tokenizer storage from model mmap | open | low priority; overlaps #1219's arena |
| `2f0a0aa` (#1347) | Run the Metal queue keepalive every 250 ms | open | measure idle-request latency on M5 Max with the Q4 (about 145 GB of views) and Q2 packs; the author saw drops every ~6 s at 1000 ms on M5 Ultra |
| `bfaa6a2` (#1324) | select the shader language version explicitly | open | low priority; only matters when embedded in a host linked against an older SDK |
| `6860463` (#575) | Resolve Metal shader sources relative to the executable | open | low priority; the child CLI started from another cwd falls back to CPU silently |
| `ca9df3a` (#1153) | `--image-prefix-snapshot` | open | vision KV reuse designed around Qwen's non-rewindable recurrent state |
| `2b720e8` (#1221) | let the memory-text tier survive images | open | vision KV reuse |
| `15b7216` (#1322) | let a request with an image use the disk KV cache | open | vision KV reuse; overlaps #1343 |
| `481e07c` (#1344) | Keep the images of a conversation in the embedding cache | open | cache sizing for 256-image requests |
| `7bf7c48` (#1017) | `--reasoning` and `--alias` | open | low priority; overlaps #1307 |
| `7ad2a44` (#1307) | `-a/--alias` | open | low priority |
| `c4becb5` (#1203) | `GET /v1/status` and menu bar | open | low priority; feature |
| `24bbd1d` (#1319) | `--loop-guard` | open | low priority; opt-in, changes output only when engaged |
| `abd9b8b` (#1229) | docs: Qwen API client setup and diagnosis guide | docs | compare with `docs/CLIENTS.md` |
| `af03a2f` (#1350) | linenoise word navigation | open | low priority; CLI UX |
| `9932596` (#1004) | Ignore build outputs | drop | the child keeps its own ignores |
| `383593f` (#987, 9 commits) | Introduce welcome screen with DwarfStar logo | drop | CLI cosmetics, mostly `ds4-agent` |

## Excluded

Not reachable from the Qwen graph, or not Metal:
#105 #121 #196 #197 #206 #261 #279 #371 #373 #381 #383 #385 #396 #573 #583 #758
#770 #794 #797 #813 #822 #830 #831 #835 #846 #850 #869 #919 #920 #924 #939 #952
#953 #954 #963 #972 #981 #982 #985 #990 #1000 #1005 #1010 #1011 #1018 #1024
#1033 #1034 #1035 #1036 #1041 #1042 #1055 #1060 #1061 #1063 #1068 #1070 #1073
#1079 #1083 #1089 #1090 #1093 #1097 #1098 #1099 #1100 #1116 #1117 #1120 #1121
#1122 #1123 #1124 #1127 #1129 #1130 #1135 #1138 #1142 #1143 #1144 #1147 #1148
#1152 #1158 #1160 #1167 #1168 #1172 #1174 #1177 #1178 #1180 #1183 #1187 #1190
#1191 #1192 #1193 #1199 #1204 #1205 #1207 #1208 #1210 #1213 #1217 #1218 #1220
#1222 #1225 #1227 #1230 #1232 #1233 #1234 #1236 #1237 #1241 #1242 #1246 #1247
#1248 #1250 #1252 #1253 #1254 #1256 #1257 #1261 #1262 #1263 #1264 #1265 #1267
#1269 #1270 #1272 #1273 #1274 #1275 #1276 #1277 #1279 #1282 #1283 #1285 #1286
#1287 #1289 #1290 #1291 #1293 #1295 #1298 #1299 #1300 #1306 #1310 #1313 #1314
#1315 #1320 #1321 #1331 #1334 #1337 #1338 #1339 #1345 #1346 #1349.

Notes on the ones a name or a file could make look reachable (2026-11-13):

- Merged, came in with the sync to b3f5018 (90), touch only non-Qwen paths:
  #1034, #1073, #1127, #1135 (DeepSeek visual attention), #1147, #1213, #1261,
  #1262, #1270; also #1192 (`82aa7e8`), #1234, #1236 and #1267 (`345d7f4`),
  landed by hand. Not checked: #1073 also edits shared `dense.metal` and
  `dsv4_*` kernels, some of which Qwen reuses; the parity oracle at the sync is
  the check.
- Shared-looking Metal code that Qwen does not call: #1123 (SWA ring,
  `dsv4_hc_expand` barrier, pair-swiglu, FP8 KV), #1124 (FP8 KV), #1286 (Q8 rows,
  DeepSeek graph only), #1290 (V4.1), #1331 (selected-readback drain, DeepSeek
  graph only), #1269 (`metal_graph_use_streaming_decode_prefill`), #1192 and
  #1267 (argsort and the dsv4 indexer score; Qwen uses `qwen4_idx_*`).
- Tokenizer: #1346 changes only the DeepSeek `joyai` pre-tokenizer; it states
  the Qwen unicode tables are byte-identical after regeneration.
- Device gates: #770 (pre-M5 only), #1120 (V4/V4.1/PRO/GLM shapes).
- Removed features: #1167/#1168 (DSpark verifier), #835/#919 (pipeline split;
  Qwen rejects pipeline, rule 5 keeps the plumbing), #197 and #1310 (DeepSeek
  renderers), #985/#1093/#1152/#1160 (GLM/DeepSeek renderers), #1099 (the
  second-reasoning guard, dead in this child), #1005 (GLM rewind), #1010
  (compressed KV).
- Other models, backends or docs: #1191 (qwen35moe CPU), #1207 (CUDA and
  requantization tools), #1246/#1287/#1320/#1349 (new models; their
  `qwen4.metal` changes are additive), #1070 (ROCm Qwen), #1142/#1227 (M4/M3
  Ultra speed-bench data), #1275 (superseded by merged #1165), #1276/#1277 (V4.1
  image budgets, ffmpeg video), #1274 (DeepSeek ViT), #981 (already in the
  child's base as `ac43e90`).

Qwen support itself landed with #991 (2026-09-06); older PRs cannot touch the
Qwen path.
