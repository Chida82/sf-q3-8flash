# Tasks

Starts from `main` with `131` landed (2a4d621 or later). `<Q4>` is the child's
`qwen3.8-flash-next.gguf`; this change's files go in `$SCR/c132/`. Model runs
are strictly sequential.

## 1. Branch

- [ ] 1.1 Worktree `.claude/worktrees/132-answer-key` on `fix/132-qwen-answer-key-whitespace` from `main`; `git config rerere.enabled true`. List every caller of `append_trimmed_text`, `build_qwen_assistant_suffix` and `build_thinking_visible_text` (`rg`) in `$SCR/c132/callers.txt`.

## 2. Fix (design D1)

- [ ] 2.1 Add `append_qwen_answer_body` with the renderer's rule, and call it from `append_qwen_assistant_message`, `build_qwen_assistant_suffix` and `build_thinking_visible_text`. Leave reasoning, user text and the `<|im_end|>` placement as they are.
- [ ] 2.2 `92`'s render check (`./ds4_test --qwen-render` over `131`'s corpus, or a fresh one): every rendering byte-identical to `main`.

## 3. Test (design D2)

- [ ] 3.1 Add the key-prefix test to `./ds4_test --server`: answer endings `\n`, `\n\n`, `  `, none; tool calls on/off; think on/off; chat and Responses. Verify that it fails on `main`'s builders (revert 2.1 locally, run, restore) and passes with the fix.

## 4. Gates

- [ ] 4.1 `make -j8` with no warnings; `make test -j8` naming its suites; `./ds4_test --server` OK.
- [ ] 4.2 `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>`: rc 0, turns 2-3 cached.
- [ ] 4.3 `speed-bench/agent_reuse.py` on `main` and on this tree, twice each (design D3): responses identical, no request with fewer cached tokens, and the trailing-newline shape hitting. Record per-request figures in `$SCR/c132/reuse.txt`.
- [ ] 4.4 `tools/parity-check.sh sf-q3-8flash <Q4>` (with `SF_CHILD_DIR` at the worktree): `PARITY OK`.

## 5. Closing

- [ ] 5.1 Review the diff and every function it touches.
- [ ] 5.2 `docs/SERVER.md`: state the body rule once where the visible tiers are described, if it is not already there.
- [ ] 5.3 `openspec validate 132-qwen-answer-key-whitespace --strict` passes.
- [ ] 5.4 Report to the user in Italian. Commit only when the owner asks: one signed commit, no `Co-authored-by` (child-only fix).
