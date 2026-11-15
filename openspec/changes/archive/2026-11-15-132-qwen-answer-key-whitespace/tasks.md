# Tasks

Starts from `main` with `131` landed (2a4d621 or later). `<Q4>` is the child's
`qwen3.8-flash-next.gguf`; this change's files go in `$SCR/c132/`. Model runs
are strictly sequential.

## 1. Branch

- [x] 1.1 Worktree `.claude/worktrees/132-answer-key` on `fix/132-qwen-answer-key-whitespace` from `main`; `git config rerere.enabled true`. List every caller of `append_trimmed_text`, `build_qwen_assistant_suffix` and `build_thinking_visible_text` (`rg`) in `$SCR/c132/callers.txt`.
  Done: worktree and branch existed (from a6874cd), rerere on. `rg` is not installed, so `grep -n` over `*.c tests/*.c`: 32 sites in `$SCR/c132/callers.txt`. Builders that feed keys: `build_qwen_assistant_suffix` (through `build_tool_checkpoint_suffix`, `build_responses_visible_assistant_suffix`, `build_qwen_tool_turn_visible_text`) and `build_thinking_visible_text` (through `remember_thinking_checkpoint`, reached only without tool calls). The other `append_trimmed_text` callers (reasoning, user text, system text) are untouched.

## 2. Fix (design D1)

- [x] 2.1 Add `append_qwen_answer_body` with the renderer's rule, and call it from `append_qwen_assistant_message`, `build_qwen_assistant_suffix` and `build_thinking_visible_text`. Leave reasoning, user text and the `<|im_end|>` placement as they are.
  Done. The helper trims leading whitespace, trims trailing only with tool calls, and returns whether the body is non-empty (the renderer's `has_content`, the builder's separator flag). The builder writes the body straight into its masked buffer (untrusted, as `buf_puts` of the old temporary was). `build_thinking_visible_text` passes `has_calls=false`: its only caller runs for turns without calls. The existing `test_qwen_thinking_visible_text_matches_render` echoed `"The answer is 4."` for a sampled `"The answer is 4.\n"`, so it asserted the trimmed key; it now echoes the answer as the client received it.
- [x] 2.2 `92`'s render check (`./ds4_test --qwen-render` over `131`'s corpus, or a fresh one): every rendering byte-identical to `main`.
  Done. `131`'s corpus was deleted, so a fresh one (`$SCR/c132/corpus.py`): 144 conversations (answer endings none, `\n`, `\n\n`, `  `, `\t`, ` \n`, `\r\n`, `\n\n\n` x leading none/`\n`/`  ` x reasoning on/off x plain-answer, tool-loop and edge shapes: whitespace-only answers, in-content `<think>` block, parallel calls), rendered at effort high/none x preserve true/false x tools/none by main's `ds4_test` and this tree's: `renders=1152 identical=1152 differ=0 empty=0`.

## 3. Test (design D2)

- [x] 3.1 Add the key-prefix test to `./ds4_test --server`: answer endings `\n`, `\n\n`, `  `, none; tool calls on/off; think on/off; chat and Responses. Verify that it fails on `main`'s builders (revert 2.1 locally, run, restore) and passes with the fix.
  Done: `test_qwen_visible_keys_prefix_next_render`. Keys: chat without reasoning echo (thinking key without calls, tool-turn visible key with raw call text), chat with reasoning echo (tool checkpoint, calls only), Responses-visible (with and without calls). Each key is asserted a byte and trusted-mask prefix of the next request's rendering (`131`'s key space is a function of bytes and mask), 36 keys in all, the count asserted. Decision: the whole thinking key is asserted, `<|im_end|>\n` included, not only the body bytes: it is a prefix today, and a shorter key from `160` stays one. With main's builders (both call sites switched back to trim-both, rebuilt, run, restored): `ds4 tests: 13 failure(s)`, 9 of them this test (exactly the plain answers ending in `\n`, `\n\n`, `  `: thinking key and Responses key with thinking, Responses key without), 4 the old thinking-key test; with the fix `server: OK`. Output in `$SCR/c132/failmain.txt`.

## 4. Gates

- [x] 4.1 `make -j8` with no warnings; `make test -j8` naming its suites; `./ds4_test --server` OK.
  Done: no warnings; `make test -j8` rc 0 naming MXFP4 4/4, Q4_K 4/4, GGUF refusals OK, session state ok, TP command ok, RDMA/Unix/TCP PASS, eval self-tests, gguf-types OK, `server: OK`, `ds4 tests: ok`, layer_pack 97/97, prompt prefix, sampling OK, sfctl.
- [x] 4.2 `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>`: rc 0, turns 2-3 cached.
  Done: rc 0; tool-less-omit 3110/3135 and 3150/3175, tools-omit 3350/3375 and 3390/3415, tools-echo 3349/3376 and 3399/3426 cached.
- [x] 4.3 `speed-bench/agent_reuse.py` on `main` and on this tree, twice each (design D3): responses identical, no request with fewer cached tokens, and the trailing-newline shape hitting. Record per-request figures in `$SCR/c132/reuse.txt`.
  Done (Q4, defaults). Clean workload: `responses: identical` for main1/main2, fix1/fix2, main/fix; every per-request cached count equal (total cached 312499 of 497900 on all four). No answer in it ends in whitespace. Spelled variant rebuilt (`$SCR/c132/spell.py`, `<|im_end|>` over chars 112648-112657, A's first slice): identical responses and per-request counts on all four runs (312057 of 497553), but no whitespace-ending answer either (`131`'s `a.resp3` newline did not recur). So design D3's scripted turn, in `$SCR/c132/ws_turns.py` (scratch, reusing `agent_reuse.py`'s plumbing; the workload itself is unchanged): six two-turn conversations, each through Responses and through chat without reasoning echo, effort low. Two prompts end the first answer in whitespace (`hello\n\n\n`, `... world \n`). Their follow-ups: main 0 cached on both runs (`live kv cache miss ... reason=token-mismatch`), the fix 409/432, 385/407, 419/442, 409/431 on both runs (`responses live continuation match=visible-prefix`, `thinking live continuation match=visible-prefix`), the same tier and the same 22-23 prefilled tokens as every answer without trailing whitespace. Each build's two runs are byte-identical. Every other request: identical response and cached count on all four runs; no request has fewer cached tokens on the fix. The follow-ups that now hit continue from the live KV with the hidden reasoning in it, as every visible-prefix hit does, so their prompt counts and 3 of their 4 responses differ from main's cold re-prefill: that is the tier's normal behaviour, now reached by these answers too.
- [x] 4.4 `tools/parity-check.sh sf-q3-8flash <Q4>` (with `SF_CHILD_DIR` at the worktree): `PARITY OK`.
  Done: `PARITY OK (10 prompts)`, all token-identical; speed within 2% except prompt 10 at +7.0% (faster) and prompt 5 re-sampled to +0.3% (`tools/parity/out/sf-q3-8flash-20261115-115015`). Also `tests/model_gates.sh` with the mmproj and `tests/vision-fixtures/qwen38/{orbit,maple}.png`, on Q4 and Q2: `PASS mtp-identity`, `PASS mtp-limits`, `PASS ds4_test`, `PASS vision`, `PASS host-paths`, `model gates: all PASS` on both.

## 5. Closing

- [x] 5.1 Review the diff and every function it touches.
  Done: renderer bytes unchanged (corpus), masks unchanged (body bytes were and are untrusted), `has_content` and the call separator computed as before, no other caller of the builders affected (`callers.txt`).
- [x] 5.2 `docs/SERVER.md`: state the body rule once where the visible tiers are described, if it is not already there.
  Done: one paragraph in "Disk KV cache" (it was not stated anywhere).
- [x] 5.3 `openspec validate 132-qwen-answer-key-whitespace --strict` passes.
  Done: `Change '132-qwen-answer-key-whitespace' is valid`.
- [x] 5.4 Report to the user in Italian. Commit only when the owner asks: one signed commit, no `Co-authored-by` (child-only fix).
  - Landed 2026-11-15 under the owner's standing permission (all gates green). Note: a client that strips a plain answer's trailing whitespace before echoing it now misses the visible key it used to match; that old hit was inexact (the live KV held the sampled whitespace). Described in `docs/SERVER.md`.
