# Tasks

GPU: sections 1, 3 and 4. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Every model run is under the one-second memory
guard (design D5). `$SCR` is `~/.sf/q3-8flash/scratch`; this change's files
are in `$SCR/c190/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Step 0 (done on 2026-11-18, before the proposal)

- [x] 1.1 Scratch counter (`$SCR/c190/trace190.py`, never committed) on a worktree of `main`; Q4, an 8192-token context and 512 generated tokens, cache sizes from 2% to 70% of the routed experts, plain and MTP, code and prose, uncached reads from `dc50997`. Table in design D6.
- [x] 1.2 The plan at the service's context, one engine open without vision. Figures in design D4. The raw files stay in `$SCR/c190/` until this change closes.

## 2. The switch (design D3; no GPU until 2.3)

- [ ] 2.1 `git config rerere.enabled true`; `git switch -c perf/190-ssd-capped-ram-bench`. Bring `dc50997`'s read onto `main` with the default inverted and the name `DS4_METAL_STREAM_EXPERT_UNCACHED_READS`; find every reader of `g_model_fd` with `rg` first.
- [ ] 2.2 The model-less case in `tests/test_qwen4_ssd_experts.c` (unaligned range across the bounce size; fallback when the second open fails). The step checks, model-less part.
- [ ] 2.3 On Q4: tokens of a streamed run equal with and without the switch, plain and MTP; the GGUF's resident pages after an uncached run are the static weights only.
- [ ] 2.4 Without the switch, streamed and resident `ab_bench.py` against `main`: `PASS (tokens)`, and `--bitwise` on the resident side.

## 3. The bench (design D4, D5)

- [ ] 3.1 The three `capped-*` kinds in `ab_bench.py`, on request only; `python3 speed-bench/ab_bench.py --help` names them.
- [ ] 3.2 One engine open per target at the service's configuration: the slot counts for 48, 54 and 60 GiB. Record them in `$SCR/c190/steps.txt`.
- [ ] 3.3 An A/A run at 54 GiB in the capped, RAM-taken condition: the spread of each metric over 8 pairs, which is the resolution later changes are judged against.

## 4. The tables (design D6, D7, D8)

- [ ] 4.1 Q4 at 48, 54 and 60 GiB, the three kinds, RAM taken and RAM free, in a clean window: decode and prefill rates, misses and miss layers per token.
- [ ] 4.2 Fix the development value by D7.
- [ ] 4.3 Use 1: the two ends of D8, Q4 and Q2.

## 5. Closing

- [ ] 5.1 `docs/SSD_STREAMING.md`: the capped-RAM section with 4.1's table, the switch, the bracket for a 48 GB Mac, and the corrected account of the emulated figures. `AGENTS.md`: the bench condition for streaming work, in the development loop.
- [ ] 5.2 Update `189-ssd-handshake-gated` design D2 and tasks to this bench; open C1 to C3 only where their gate passes (design D9).
- [ ] 5.3 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`.
- [ ] 5.4 `openspec validate 190-ssd-capped-ram-bench --strict` passes.
- [ ] 5.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c190/` and the worktree `190-trace`; archive the change.
