# Tasks

Starts from `main` with `130` and `160` landed. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`. Model runs strictly sequential.

## 1. Frequency (design D2)

- [x] 1.1 Run `speed-bench/agent_reuse.py` on Q4 against `main`'s server with the KV-cache log on. Count the "after the last closed tool call dropped" lines, split by `finish`.
- [x] 1.2 If no turn ends on the model's stop with trailing output: record the figures in tasks.md, then go to 3.3 and close.

### Result (2026-11-15, main `ceccded`)

`agent_reuse.py` with `DS4_LOG_KVCACHE=1`, 16 requests per run (server-side
finish: 10 `tool_calls`, 6 `stop`, 0 `length`):

| Run | Tool turns | "after the last closed tool call dropped" lines |
|---|---|---|
| Q4 | 10 | 0 |
| Q4 `--mtp` | 10 | 0 |
| Q2 | 10 | 0 |

No line at all, so none by `finish` (stop: 0, length: 0) in 48 turns, 30 of
them tool turns. The log category was on (12 "checkpoint remembered"
lines per run). The gate of D2 is not met: section 2 is not built and the
log line stays as the sentinel. Q4 `--mtp` and Q2 were added to the task's
Q4 run to widen the sample.

## 2. Restore (design D1, D3)

Not built: the frequency gate (1.2) closed the change.

- [ ] 2.1 Find the cheapest snapshot at a committed boundary after `</tool_call>`, with and without `--mtp`. Measure its cost per call.
- [ ] 2.2 Restore and commit `<|im_end|>` on a `calls_cut` turn that ends on the model's stop. Keep the fallback and its log.
- [ ] 2.3 Exactness check (D3); `make -j8`, `make test -j8`, `./ds4_test --server`.
- [ ] 2.4 Re-run 1.1: those turns now keep their live frontier; no request loses cached tokens.

## 3. Gates and closing

3.1 and 3.2 apply only to the restore, which was not built.

- [ ] 3.1 `tests/test_qwen4_checkpoint_replay.py --model <Q4>`; `tests/model_gates.sh` on Q4 and Q2.
- [ ] 3.2 Parity `PARITY OK`; `ab_bench.py --bitwise -m <Q4>` against `main` as a guard.
- [x] 3.3 `docs/SERVER.md` (tool turns); `openspec validate 133-tool-turn-frontier --strict`.
