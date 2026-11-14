# Tasks

## 1. Identity test

- [x] 1.1 `--fail-fast` in `tests/test_qwen4_mtp_identity.py`.
- [x] 1.2 `SLOW` verdict: MTP t/s below half of the same prompt's plain t/s fails the run, with both speeds printed.

## 2. Gate script

- [x] 2.1 `tests/model_gates.sh` per the proposal: lock check, sequential gates, one summary line each, stop at the first failure.
- [x] 2.2 `ds4_test` gate: compare the failing test names with the baseline table in `docs/TESTING.md`; unknown failures fail the gate.
- [x] 2.3 Model-less check in `make test`: `bash -n tests/model_gates.sh` and `tests/model_gates.sh --help`.

## 3. Prove it

- [x] 3.1 Run on `<Q4>` on a clean `main`: every gate PASS (2026-11-14: identity 131 s, limits 11 s, ds4_test 69 s with the five known failures, vision 39 s, host paths 33 s).
- [x] 3.2 Revert `90`'s `qwen4_session_replay_if_stale` fix in a scratch worktree and run gate 1: it stops with `DIFF` on prompt 1 (and `SLOW`). Discard the worktree. (2026-11-14: `DIFF SLOW` at 4.42 t/s on prompt 1, exit 1 after 27 s.)
- [x] 3.3 `AGENTS.md` "Before a PR" points at the script.
