# Tasks

GPU: section 2. Model runs strictly sequential.

## 1. Build (no GPU)

- [x] 1.1 Engine option `ssd_streaming_uncached`, the refusal without `--ssd-streaming`, the Metal switch set at open (the variable stays an alias), the warning when the descriptor fails.
- [x] 1.2 The option in the four frontends; the help's SSD streaming section.
- [x] 1.3 `ab_bench.py` evicts before a series for either form; the unit test runs its uncached pass through the option's setter.
- [x] 1.4 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 2. Model checks

- [x] 2.1 Q4, capped 54 GiB: the option and the variable give the same log line and identical tokens to resident; without `--ssd-streaming` the open is refused. *(2026-11-20, Q4, 11,831 slots, greedy, 96 tokens: option, variable and resident outputs identical; the bypass line printed for both forms; `--ssd-streaming-uncached` alone exits 1 with `needs --ssd-streaming`.)*
- [x] 2.2 The file cache after a run with the option holds only the static weights (as `190`). *(GGUF resident after the run 6.33 GiB, against 69.74 after a resident run.)*
- [x] 2.3 `tests/model_gates.sh` on Q4 and Q2. *(All PASS on both: mtp-identity, mtp-limits, mtp-turns, ds4_test, host-paths; vision not run, the change does not reach it.)*

## 3. Closing

- [x] 3.1 `docs/SSD_STREAMING.md`, `AGENTS.md`.
- [x] 3.2 `openspec validate 207-ssd-uncached-reads-option --strict`; report; land as one signed commit; archive.
