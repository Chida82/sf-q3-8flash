# Tasks

Starts from `main` with `90` and `92` landed. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`; `$SCR` is `~/.sf/q3-8flash/scratch`, and this
change's files go in `$SCR/c130/`. Model runs are strictly sequential.

"The step checks" (design D4): `make -j8` with no warnings; `./ds4_test
--server`, with the step's new unit tests named in its output.

## 1. Branch, sources, reachability

- [x] 1.1 `git config rerere.enabled true`; `git switch -c fix/130-server-protocol-batch`. Fetch each PR head (`git fetch upstream pull/<N>/head`) and save the diffs to `$SCR/c130/`.
  (2026-11-14 triage: done on `triage/130-160` without creating the branch; heads in `$SCR/c130/heads.txt`, diffs and patches `prN.*`; `$SCR` was the session scratchpad.)
- [x] 1.2 For each PR, find the child function each hunk targets (`rg` on the names) and confirm that the Qwen path reaches it, from the request parser or the stream writer down. Record per PR "reachable" with the call chain, or "drop" with the reason, in `$SCR/c130/reach.txt`. A dropped PR leaves the batch and goes to the registry.
- [x] 1.3 Owner: decide masking (#1288) against `92`'s trace-only policy (design D1), and #1226 against #815 (design D3). Until answered, steps 2.1 and 2.10 wait.
  Decided 2026-11-14 (owner delegated), from `$SCR/c130/decisions.md`:
  - D1: the owner chose option C on 2026-11-14 (mask plus trust-aware cache keys), as its own change `131-trusted-marker-masking`; until it lands, `92`'s trace-only policy holds. Earlier note: option B, `92`'s trace-only policy. #1288's mask as written keeps `session_ambiguous` set and turns off the visible-text and disk cache tiers for the whole session whenever client text holds a marker spelling, which an agent reading this repository hits on most turns. Step 2.1 ports nothing from #1284/#1288. Option C (mask plus cache keys that record which bytes are trusted) is a possible later change of its own, with its own design.
  - D3: #1226 (valid JSON at every output, internal text, keys and KV untouched); #815 stays an idea, superseded.
  - #1134 (mid-conversation system turn): the model's template refuses it ("System message must be at the beginning"), so step 2.2 waits for a live A/B on Q4 and is not ported blind.

## 2. Ports, in design D2's order

- [ ] 2.1 #1284 base and #1288 Qwen mask (`def0f60`, `138cb39`, `e66797e`, `6ee4a73`, `0252371`). Verify that the injection unit tests pass and that `92`'s render corpus renders unchanged outside the marker cases. Step checks.
- [ ] 2.2 #1134. Step checks.
- [x] 2.3 #1325. Step checks.
  Dropped 2026-11-15 (owner): `160` takes #1169's end-of-turn policy, which fixes the same
  boundary the other way; #1325 is the fallback there if #1169 shows no gain.
- [ ] 2.4 #1088. Step checks.
- [ ] 2.5 #1163. Step checks.
- [ ] 2.6 #1140 + #1251, GLM/DSML parts dropped. Step checks.
- [ ] 2.7 #1157. Verify a unit test that places the anchor in a ChatML prompt. Step checks.
- [ ] 2.8 #1155 (`8a8b2a2`, `8922c81` squashed with `8f61ece`). Step checks.
- [ ] 2.9 #1175. Step checks.
- [ ] 2.10 #1226. Add a unit test where a length cut splits a multibyte character. Step checks.
- [ ] 2.11 #1131, #1161, #1162, each with its unit test. Step checks.
- [ ] 2.12 After each step: a short review of its diff, fixing only what would make it wrong or break a child rule (no predicate on `server_model_syntax` left dead; `sf-ablate` markers where a GLM/DeepSeek part was cut inside a kept function).

## 3. Gates (design D4)

- [ ] 3.1 `make test -j8`; check that its output names the suites.
- [ ] 3.2 Live protocol pass on Q4 with `sf-q3-8flash-server`: one request per endpoint (OpenAI chat streamed and not, Responses, Anthropic, completions) covering the scenarios of the spec delta. Record each request and verdict in `$SCR/c130/live.txt`.
- [ ] 3.3 `DS4_TEST_MODEL=<Q4> ./ds4_test --tool-call-quality` passes; the full `DS4_TEST_MODEL=<Q4> ./ds4_test` shows no new failure against `docs/TESTING.md`.
- [ ] 3.4 `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>` passes.
- [ ] 3.5 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. Then `ab_bench.py --a <worktree at main> --b . --bitwise --budget 600`: `PASS (tokens; bitwise)`. Guards only, no record row.

## 4. Closing

- [ ] 4.1 Final pass over `ds4_server.c`'s touched regions: AGENT.md, dead code the ports left, one idiom for each repeated pattern.
- [ ] 4.2 `docs/SERVER.md` (masking, tool calls, UTF-8, fields) and `docs/CLIENTS.md` where client behaviour changed.
- [ ] 4.3 `docs/upstream-prs.md`: each ported commit to `adopt -> 130-server-protocol-batch`, each dropped one with its reason.
- [ ] 4.4 `openspec validate 130-server-protocol-batch --strict` passes.
- [ ] 4.5 Report to the user in Italian. Commit only when the owner asks: one signed commit, with each PR author as `Co-authored-by`.
