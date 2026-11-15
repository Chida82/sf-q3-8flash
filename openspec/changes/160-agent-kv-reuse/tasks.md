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
- [ ] 2.2 Run it twice on `main`'s build. Verify that the two runs' responses are byte-identical and their cached-token counts equal, to establish that the workload is deterministic. Record the baseline.

## 3. Ports, in dependency order

- [ ] 3.1 For each PR kept by triage (#1169 before #1206; one of #1342/#1340/#903 by design D3): port it, run `make -j8`, `./ds4_test --server`, and the workload. Keep it by design D2's rule, or drop it with its figures.
- [ ] 3.2 After each kept port: `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>` passes.
- [ ] 3.3 After each port: a short review of its diff.

## 4. Closing

- [ ] 4.1 Final pass over the touched regions.
- [ ] 4.2 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. Then `ab_bench.py --bitwise` against `main` as a guard. The gain is in the server workload, which the harness does not measure, so the workload's figures go in the commit message.
- [ ] 4.3 `docs/SERVER.md` (cache tiers) and `docs/upstream-prs.md` (each PR's verdict, with the figures).
- [ ] 4.4 `openspec validate 160-agent-kv-reuse --strict` passes.
- [ ] 4.5 Report to the user in Italian. Commit only when the owner asks: one signed commit, with the PR authors as `Co-authored-by`.
