# Proposal

## Why

The model-backed checks a sync or a PR must pass (AGENTS.md "Before a PR")
are typed by hand or kept in a session's scratch directory. At the sync to
`b3f5018` (`90`) they ran from a session-local script that logged each gate's
exit code and moved on. The MTP identity gate failed on its first prompt (MTP
output left plain output at word 21, 4.7 t/s against 59); the run was stopped
mid-way for an unrelated reason, and the failure was reported as "not
completed" instead of "failed". The bug cost a night and was found the next
morning by reading the log by eye.

A gate is only as good as the thing that reads it (AGENTS.md rule 19).

## What Changes

- `tests/model_gates.sh <model.gguf> [--mmproj FILE --image A --image B]`: the
  model-backed gates in a fixed order, one process at a time, stopping at the
  first failure with the gate's name and the last lines of its log:
  1. `tests/test_qwen4_mtp_identity.py --fail-fast` (all depths);
  2. `tests/test_qwen4_mtp_limits.py`;
  3. `DS4_TEST_MODEL=... DS4_TEST_GLM_MTP=1 ./ds4_test`, judged against the
     baseline table in `docs/TESTING.md` (known failures listed, any other one
     fails the gate);
  4. vision (`tests/test_qwen4_cli_vision.py`) when `--mmproj` is given;
  5. `make test-qwen4-host-paths QWEN4_GGUF=...`.
  It prints one summary line per gate (`PASS`/`FAIL`, seconds) and exits
  non-zero on the first `FAIL`. It never starts a gate while another model
  process holds `/tmp/sf-q3-8flash.lock`.
- The script builds `all` and `ds4_test` before the first gate. At the same
  sync, `make -j8` after a fix relinked the four binaries but not `ds4_test`,
  so the `ds4_test` gate ran the pre-fix code and reported two failures
  (`qwen4-restore-reuse`, `session-rewind`) that the fixed tree does not have.
- `tests/test_qwen4_mtp_identity.py --fail-fast`: stop at the first `DIFF`.
  A second check, independent of identity: an MTP run slower than half the
  plain run on the same prompt fails as `SLOW` (a replay per cycle or a CPU
  fallback shows up here even when output happens to match).
- `AGENTS.md` "Before a PR" names the script instead of the loose commands.
- StarForge's parity oracle stays in the orchestrator; the script does not
  replace it.

Non-goals: no new test content; Q2 runs stay opt-in (the script takes the
model path).

## Capabilities

### New Capabilities
(none: test tooling)

### Modified Capabilities
(none)

## Impact

- New `tests/model_gates.sh`; `tests/test_qwen4_mtp_identity.py`; `AGENTS.md`.
- Model-less `make test` gains a syntax and `--help` check of the script.
