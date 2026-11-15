# Tasks

Starts from `main` with `130` and `160` landed. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`. Model runs strictly sequential.

## 1. Frequency (design D2)

- [ ] 1.1 Run `speed-bench/agent_reuse.py` on Q4 against `main`'s server with the KV-cache log on. Count the "after the last closed tool call dropped" lines, split by `finish`.
- [ ] 1.2 If no turn ends on the model's stop with trailing output: record the figures in tasks.md, then go to 3.3 and close.

## 2. Restore (design D1, D3)

- [ ] 2.1 Find the cheapest snapshot at a committed boundary after `</tool_call>`, with and without `--mtp`. Measure its cost per call.
- [ ] 2.2 Restore and commit `<|im_end|>` on a `calls_cut` turn that ends on the model's stop. Keep the fallback and its log.
- [ ] 2.3 Exactness check (D3); `make -j8`, `make test -j8`, `./ds4_test --server`.
- [ ] 2.4 Re-run 1.1: those turns now keep their live frontier; no request loses cached tokens.

## 3. Gates and closing

- [ ] 3.1 `tests/test_qwen4_checkpoint_replay.py --model <Q4>`; `tests/model_gates.sh` on Q4 and Q2.
- [ ] 3.2 Parity `PARITY OK`; `ab_bench.py --bitwise -m <Q4>` against `main` as a guard.
- [ ] 3.3 `docs/SERVER.md` (tool turns); `openspec validate 133-tool-turn-frontier --strict`.
