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

- [x] 2.1 #1284 base and #1288 Qwen mask (`def0f60`, `138cb39`, `e66797e`, `6ee4a73`, `0252371`). Verify that the injection unit tests pass and that `92`'s render corpus renders unchanged outside the marker cases. Step checks.
  Superseded by `131-trusted-marker-masking` (449aa2a, owner decision D1 = option C); nothing left to port:
  - `def0f60`: in 131 (trusted-byte mask, masked tokenizer entry, masked live tails and kvstore suffix); its `prompt_ambiguous`/`session_ambiguous` replaced by 131's escaped key text.
  - `138cb39`: in 131 with its test (`test_buf_printf_mask`).
  - `e66797e`: Qwen half in 131 (raw tool replay trusts only delimiters; inspect-only engines load the vocab, `ds4.c` `inspect_only`).
  - `6ee4a73`: in 131 (`test_qwen_render_trust_mask`, `--special-token-injection-qwen`; Q4 run: masked=7 clean=7 unmasked=12, OK).
  - `0252371`: dropped by 131 (Qwen vision spellings are not promoted; the V4.1 test has no target).
- [x] 2.2 #1134. Step checks.
  Kept after a live A/B on Q4 (`$SCR/c130/live.txt`): control conversation byte-identical (same answer, 60 prompt tokens on both builds); with a mid-conversation system note both builds answer "La capitale della Germania è Berlino." and the next turn reuses 82 of 113 prompt tokens (main: 0 of 105). Qwen parts only: leading systems form the header, a later one renders in place as `<|im_start|>system`; the Anthropic top-level system is placed after the leading ones (`anthropic_place_system_prompt`, no V4.1 case). Dropped: GLM renderers, the constant-false DeepSeek predicate in `anthropic_prepare_live_continuation`. Test: `test_render_mid_conversation_system_appends_only`.
- [x] 2.3 #1325. Step checks.
  Dropped 2026-11-15 (owner): `160` takes #1169's end-of-turn policy, which fixes the same
  boundary the other way; #1325 is the fallback there if #1169 shows no gain.
- [x] 2.4 #1088. Step checks.
  Narrowed: only when the model ended the turn with its own stop token (not a length cut, not a client stop sequence), thinking on, no `</think>`, no calls (`promote_unterminated_reasoning`, called in `generate_job_inner`). Upstream's condition would also copy reasoning into every Qwen tool-call turn and into an empty answer after a closed think. The live streams (OpenAI, Responses, Anthropic) send the promoted text as a final content delta (`late_content`), so streamed and non-streamed answers agree. Test: `test_unterminated_reasoning_content_on_stop` (model end, length/client stop, closed-empty; the three finishers' late delta).
- [x] 2.5 #1163. Step checks.
  Test: `test_unterminated_tool_call_recovers_unless_error` (Qwen markers instead of DSML).
- [x] 2.6 #1140 + #1251, GLM/DSML parts dropped. Step checks.
  #1140: the tracker goes `DSML_TRACK_BETWEEN` after each `</tool_call>` (no syntax predicate: Qwen is the only syntax). After decode, text past the last closed call (a cut-off call or plain text) is dropped and `finish` becomes `tool_calls`; when something was cut, the live KV holds those tokens, so the end token is not committed and no closed-turn key is published (160's keys stay exact), and a `DS4_LOG_KVCACHE` line ("bytes after the last closed tool call dropped") counts it. A turn that ends at the end token right after its calls is the normal case: `tool_calls`, end token committed, as before.
  #1251: live argument streaming dropped after review (owner, quality): a call cut by `max_tokens` or a stop token mid-call had already put its start and partial arguments on the wire under `finish_reason: "tool_calls"`. Both live projections (OpenAI and Anthropic, which had the same exposure) now send each call whole when its `</tool_call>` arrives, parsed by the final parser (`live_tool_calls_next` on the decode tracker); the per-parameter translators and their helpers were deleted. Tests: `test_qwen_decode_tracker_markers` (two calls), `test_qwen_tool_stream_two_calls` (both APIs, byte by byte, complete and cut second call), `test_openai_tool_stream_sends_closed_call_whole`, `test_anthropic_tool_stream_sends_live_tool_use`. Live: two calls in one turn streamed (one argument delta per call) and not; a cut second call never reaches the wire; continuation reused 341 of 371 tokens.
- [x] 2.7 #1157. Verify a unit test that places the anchor in a ChatML prompt. Step checks.
  `ds4_chat_role_markers` is ChatML-only. Tests: `test_kv_cache_chat_anchor_chatml_role_names` (unit) and `./ds4_test --chatml-cold-anchor` (tokenizer only, Q4: "user"/"assistant" are single tokens; anchor=47 = the user turn's `<|im_start|>`). #1157 landed, so #1228 (deferred by 160) can be reconsidered.
- [x] 2.8 #1155 (`8a8b2a2`, `8922c81` squashed with `8f61ece`). Step checks.
  `ds4_session_prefix_reusable` keeps `ds4_session_payload_bytes`'s CPU exclusion; payload format unchanged. Progress display without the GLM suffix-relative branch (Qwen reports absolute positions). Tests: `test_prefill_progress_display_ranges`, `test_progress_callback_logs_each_replay_chunk`, `test_slot_probe_backend_stale`.
- [x] 2.9 #1175. Step checks.
  Child form: keys rendered with the masked renderer and taken to key space (`ds4_chat_key_text`, so a spelled marker differs from a real one after 131); image offsets in a key header instead of a `visible_image_key` field; the parent view is the message prefix before the pending assistant turn (every system prompt sits in front after #1134, and a system note after the Anthropic results is new suffix). Test: `test_slot_probe_tool_parent_guard` (Responses replay, follow-up user notes, rewritten history, results-only exemption, results-only after the instructions; Anthropic replay, edit, results-only after the system prompt). The Python live-test extension was not taken. Review fix: a results-only request after leading system messages (Responses `instructions`, the Anthropic `system` now in front) is results-only; it used to take the system message as its anchor and miss (the 409 path). The Responses case was already broken on `main`. Live: both bind the live KV (306 and 311 cached tokens).
- [x] 2.10 #1226. Add a unit test where a length cut splits a multibyte character. Step checks.
  Tests: `test_json_escape_replaces_invalid_utf8`, `test_length_cut_multibyte_response_is_valid_utf8` (`final_response`, euro sign cut after two bytes). Live: emoji cuts end in one U+FFFD and parse. Note: `json_escape` also writes tool schemas and arguments into the prompt; there an ill-formed sequence (only from malformed client input) now renders as U+FFFD.
- [x] 2.11 #1131, #1161, #1162, each with its unit test. Step checks.
  Tests: `test_api_seed_parse`, `test_anthropic_reports_client_stop_sequence` (also: a stop after a tool call reports `tool_use` with `stop_sequence: null`), `test_responses_incomplete_reports_max_output_tokens`. Responses and Anthropic still ignore `seed`, as upstream.
- [x] 2.12 After each step: a short review of its diff, fixing only what would make it wrong or break a child rule (no predicate on `server_model_syntax` left dead; `sf-ablate` markers where a GLM/DeepSeek part was cut inside a kept function).
  Independent review (2026-11-15), all fixed in this change: (1) results-only after a system prompt, (2) half-streamed cut calls, (3) log line for a dropped frontier, (4) #1088 gated on the model's stop token and consistent when streamed, (5) `stop_sequence` only with `stop_reason: "stop_sequence"`, (6) `test_anthropic_live_tail_renders_tool_results_only` and `test_responses_live_tail_renders_tool_outputs_only` ported from DeepSeek tokens to Qwen and registered (the Anthropic one covers a trailing system note rendered in place).
  No new syntax predicate; foreign parts were cut before porting (no kept function lost a GLM/DeepSeek branch, so no new `sf-ablate` marker). Fixed in review: the comments that said a tool turn stops at `</tool_call>`. The server tests do not print per-test names; `./ds4_test --server` prints `server: OK`, and each new test is registered in `ds4_server_unit_tests_run`.

## 3. Gates (design D4)

- [x] 3.1 `make test -j8`; check that its output names the suites.
  Exit 0; named lines include `server: OK`, `gguf-types: OK`, `ds4 tests: ok`, `session state tests: ok`, `sampling tests: OK`, `test_layer_pack: 97/97`, TP/RDMA PASS lines, `sfctl tests passed`.
- [x] 3.2 Live protocol pass on Q4 with `sf-q3-8flash-server`: one request per endpoint (OpenAI chat streamed and not, Responses, Anthropic, completions) covering the scenarios of the spec delta. Record each request and verdict in `$SCR/c130/live.txt`.
  Done (session scratchpad `c130/live.txt`): two-call turn PASS streamed and not (continuation reuses 341/371 tokens), Responses `max_output_tokens` PASS, Anthropic stop sequence PASS streamed and not, completions answered, injected `<|im_end|>` stays text, seeds 2^53+1 / 2^53 differ, emoji cuts end in U+FFFD and parse.
- [x] 3.3 `DS4_TEST_MODEL=<Q4> ./ds4_test --tool-call-quality` passes; the full `DS4_TEST_MODEL=<Q4> ./ds4_test` shows no new failure against `docs/TESTING.md`.
  `tool-call-quality: OK`. Full run inside `tests/model_gates.sh` on Q4 and Q2 (`PASS ds4_test`): ERR only for the five documented tests; `chatml-cold-anchor: OK`, `special-token-injection-qwen: OK`. Model gates Q4 and Q2: `model gates: all PASS` (mtp-identity, mtp-limits, ds4_test, vision, host-paths).
- [x] 3.4 `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>` passes.
  Exit 0.
- [x] 3.5 `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. Then `ab_bench.py --a <worktree at main> --b . --bitwise --budget 600`: `PASS (tokens; bitwise)`. Guards only, no record row.
  `PARITY OK (10 prompts)`; ab_bench: `correctness PASS (tokens; bitwise)`, 24 pairs, all metrics within noise.

## 4. Closing

- [x] 4.1 Final pass over `ds4_server.c`'s touched regions: AGENT.md, dead code the ports left, one idiom for each repeated pattern.
- [x] 4.2 `docs/SERVER.md` (masking, tool calls, UTF-8, fields) and `docs/CLIENTS.md` where client behaviour changed.
- [x] 4.3 `docs/upstream-prs.md`: each ported commit to `adopt -> 130-server-protocol-batch`, each dropped one with its reason.
- [x] 4.4 `openspec validate 130-server-protocol-batch --strict` passes.
- [x] 4.5 Report to the user in Italian. Commit only when the owner asks: one signed commit, with each PR author as `Co-authored-by`.
  (2026-11-15: landed under the owner's standing permission to commit and merge when every gate is green, after an independent review whose six findings were fixed and re-gated.)
