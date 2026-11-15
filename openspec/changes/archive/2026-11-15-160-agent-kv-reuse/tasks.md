# Tasks

Starts from `main` with `90` and `130` landed. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`; `$SCR` is `~/.sf/q3-8flash/scratch`, and this
change's files go in `$SCR/c160/`. Model runs are strictly sequential.

## 1. Triage (design D1)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/160-agent-kv-reuse`. Fetch the eleven PR heads and save their diffs to `$SCR/c160/`.
  (2026-11-14 triage: done on `triage/130-160` without creating the branch; heads in `$SCR/c160/heads.txt`, diffs and patches `prN.*`, plus #1340, #903 and closed #1021; `$SCR` was the session scratchpad.)
- [x] 1.2 Write `$SCR/c160/triage.txt`: reachability with call chain, format effect, overlaps, verdict per PR. Verify that every PR in proposal.md's table has a line.
- [x] 1.3 If any kept PR changes a checkpoint or payload format: stop and put the compatibility choice to the owner, then add a spec delta for it before porting.
  Decided 2026-11-14 (owner delegated): no kept PR changes the checkpoint file, trailer or payload layout. #1200's reason value 7 in the existing header byte takes no version bump (old and new binaries read both). #1169 against #1325 (the same end-of-turn boundary, fixed in opposite ways) is chosen after step 2.2's workload figures, before either is ported; #1325 belongs to `130`, which waits for that choice at step 2.3.
  (2026-11-14: no candidate changes a file, trailer or payload layout; #1200's new reason value 7 and #1169's EOS-in-key semantics wait for the owner's acknowledgement, see the end of `$SCR/c160/triage.txt`.)
  Owner decision 2026-11-15: #1169's policy (evaluate `<|im_end|>` into the live KV after a
  stop or tool-call turn and keep it in the keys), for both turn kinds; its EOS-in-key semantics
  and #1200's reason value 7 are acknowledged. #1325 is dropped from `130`. Fallback: if step
  3.1's workload shows no gain for #1169 (and #1206 on top), drop both and port #1325 here
  instead. Port #1169 onto `131`'s key space (escaped spellings) and after `132` (answer-body
  whitespace rule).

## 2. Workload (design D2)

- [x] 2.1 Write `speed-bench/agent_reuse.py`. Verify that `--help` exits 0 without a model.
  (Committed to `main` with the open proposals on 2026-11-15; `131` used it for its cache-reuse figures.)
- [x] 2.2 Run it twice on `main`'s build. Verify that the two runs' responses are byte-identical and their cached-token counts equal, to establish that the workload is deterministic. Record the baseline.
  (2026-11-15, Q4, defaults: both runs identical per request; totals cached 312499, prefilled 185401, wall 187.46 s; `$SCR/c160/baseline.txt`. Misses: a.resp1 (chat -> Responses renders the tools differently, common=55; a workload property), b.return1 (B's checkpoints evicted by A's evict store, and B's tool-turn key omitted the reasoning B echoes), a.return2 and b.return2 after the restart.)

## 3. Ports, in dependency order

- [x] 3.1 For each PR kept by triage (#1169 before #1206; one of #1342/#1340/#903 by design D3): port it, run `make -j8`, `./ds4_test --server`, and the workload. Keep it by design D2's rule, or drop it with its figures.
  Each step against the step before (runs in `$SCR/c160/runs/`; every build deterministic, #1170's build checked twice):
  - #1169, end-of-turn half (owner policy): kept. +1 cached token per continuation (the end token), no request loses cached tokens; totals cached 312499 -> 312237, wall 187.46 -> 190.78 s because conversation A drifts. a.tool4 differs with identical prompt tokens: the end token's KV row now comes from a one-token decode step instead of the next request's prefill chunk, and decode and prefill are not bitwise equal; A's later requests follow from that answer. The baseline continued every Responses-visible and every reasoning-free answer key from a KV without the turn's `<|im_end|>` (and `\n`); #1325 would fix only the second. Tool-memory half not ported: no request depends on it (single Qwen calls, which the child's scanner already writes). The thinking key drops its trailing `\n` so it ends where the KV does (one more prefilled token on those hits).
  - #1206: dropped, no target (the workload never asks for or replays reasoning summaries); fallback to #1325 not taken, see #1169.
  - #1170: kept. b.return1 cached 0 -> 16384 (16.49 -> 4.99 s), b.return2 0 -> 16384 (22.24 -> 11.78 s); totals cached 312237 -> 345005, wall 190.78 -> 164.80 s. b.return1 differs: same tokens, but the cold prefill splits at the 20480 cold-store boundary while the restore prefills 16384..20814 in one chunk; b.return2 follows. a.return2 (cold in both) differs because the shutdown store now evicts A's Responses checkpoint (B's cold one has a hit), so its tool-call map no longer reaches the restarted server: the #1170 build's trace shows `tool_replay: disk=6 canonical=1 missing_ids=1` for a.return2, one call rendered from its JSON arguments (the #1169 build was not traced, so its count is inferred from the surviving files).
  - #1212: kept. b.return1 16384 -> 19930 (4.99 -> 2.44 s, same response), b.return2 16384 -> 19930 (11.78 -> 9.68 s; differs, resumes at 19930); totals cached 345005 -> 352097, wall 164.80 -> 159.29 s.
  - #1342: dropped. Cached unchanged (352097), responses identical, wall 159.29 -> 162.28 s: 13 continued stores instead of 1, evicting each other in the 4 GiB budget, none loaded. #903 (same crossing rule) and #1340 dropped with it.
  - #1281 `e9be611`: dropped, no target (the only memory-token hit with prompt > live + 512 is b.tool3, whose best disk entry is shorter than live); `296a512` unreachable.
  - #1194: dropped. Its trigger matches a.resp1 (Responses, common=55 < live), where it would skip the evict store of A's 39867-token chat checkpoint; nothing to heal in the workload.
  - #1200: dropped. Near-tail files are admitted up to budget/8 (512 MiB at 4 GiB, about 14K tokens); the workload's Responses prompts are >= 40K tokens, and no request would load the one frontier it targets (a.resp1).
  - #1216 (at most 5 entries, no lookup cost) and #1258 (zero staging failures in every run): dropped. #1228: deferred until `130` lands #1157.
  Final build: cached 312499 -> 352097, prefilled 185401 -> 145458, wall 187.46 -> 159.60 s (-14.9%); a second run of it is identical (`$SCR/c160/final.txt`).
- [x] 3.2 After each kept port: `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>` passes.
  (Run on the final build, which contains all three kept ports: exit 0, nine turns, cached = previous turn's prompt + completion + 1, the committed end token.)
- [x] 3.3 After each port: a short review of its diff.

## 4. Closing

- [x] 4.1 Final pass over the touched regions.
  (The model-backed `special-token-injection-qwen` in `tests/ds4_test.c` counted the live tool tail's leading `<|im_end|>`; it now expects the tail to start after it.)
- [x] 4.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. Then `ab_bench.py --bitwise` against `main` as a guard. The gain is in the server workload, which the harness does not measure, so the workload's figures go in the commit message.
  (2026-11-15: `PARITY OK (10 prompts)`. A/B against main 89b8501: correctness PASS (tokens; bitwise), 20 valid pairs, thermal Nominal, every metric within noise (plain decode +0.0%, prefill 8192 -0.0%). Model gates: Q4 and Q2 `model gates: all PASS` (mtp-identity, mtp-limits, ds4_test, vision, host-paths); `make test -j8` and `./ds4_test --server` OK; checkpoint replay on Q4 exit 0.)
- [x] 4.3 `docs/SERVER.md` (cache tiers) and `docs/upstream-prs.md` (each PR's verdict, with the figures).
- [x] 4.4 `openspec validate 160-agent-kv-reuse --strict` passes.
- [x] 4.5 Report to the user in Italian. Commit only when the owner asks: one signed commit, with the PR authors as `Co-authored-by`.
  (2026-11-15: landed under the owner's standing permission to commit and merge when every gate is green.)
