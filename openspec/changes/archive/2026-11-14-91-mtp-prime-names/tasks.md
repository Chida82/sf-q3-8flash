# Tasks

Starts from `main` with `90` landed.

## 1. Rename

- [x] 1.1 `rg -n 'mtp_tail' ds4.c` and list every site; rename per the proposal table.
- [x] 1.2 Update the `sf-keep(mtp)` markers in `qwen4_session_replay_if_stale` and `qwen4_graph_native_session_batch_ready`.
- [x] 1.3 `make -j8` (no warnings); `rg -n 'mtp_tail' ds4.c` prints nothing.

## 2. Check

- [x] 2.1 `make test -j8`, `make test-qwen4-kernels`.
- [x] 2.2 `python3 tests/test_qwen4_mtp_identity.py --model <Q4> --depths auto` (all SAME).
- [x] 2.3 Add to `AGENTS.md` "Misleading-name traps": a field with an upstream twin of another meaning is renamed, never shared.
