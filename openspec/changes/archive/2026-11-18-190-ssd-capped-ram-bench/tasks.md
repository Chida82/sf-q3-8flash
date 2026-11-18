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

- [x] 2.1 `git config rerere.enabled true`; `git switch -c perf/190-ssd-capped-ram-bench`. Bring `dc50997`'s read onto `main` with the default inverted and the name `DS4_METAL_STREAM_EXPERT_UNCACHED_READS`; find every reader of `g_model_fd` with `rg` first. *(Done; `=1` turns it on, the first open prints "ds4: Metal SSD expert reads bypass the file cache". `F_RDADVISE` is skipped while the second descriptor is open, as in `dc50997`. The readers of `g_model_fd` are the pread pool and the explicit-load paths, which all go through `ds4_gpu_stream_expert_pread_into`.)*
- [x] 2.2 The model-less case in `tests/test_qwen4_ssd_experts.c` (unaligned range across the bounce size; fallback when the second open fails). The step checks, model-less part. *(The fixture is now a named file and `make test-qwen4-ssd-experts` runs the binary twice. With the switch, the decode and MM shapes of Q2, Q4 and Q8 are exact, cold and warm, including the retry after a failed read on the unlinked empty file, where the second open fails and reads stay buffered. The read-accounting assertions and the probe's failure injection are skipped in that mode: they observe only the buffered descriptor. Not covered: a range that crosses the 1 MiB bounce buffer, since the fixture's experts are under 200 KB; the Q4 token check below covers the real sizes. Unit test 145 PASS; `make -j8` no warnings; `make test -j8` passes.)*
- [x] 2.3 On Q4: tokens of a streamed run equal with and without the switch, plain and MTP; the GGUF's resident pages after an uncached run are the static weights only. *(2048-token context, 128 tokens, 4915 slots: token ids equal on `rax.c` with MTP and on prose without it. After three uncached runs from an evicted file, 6.33 GiB of the GGUF are resident: the locked static weights, 6.32 GiB.)*
- [x] 2.4 Without the switch, streamed and resident `ab_bench.py` against `main`: `PASS (tokens)`, and `--bitwise` on the resident side. *(By hand, not through `ab_bench.py`: its preflight refused while a Parallels VM held 19.6 GiB. A = `prev-main` (`3f51f55`, the same engine code as `main`), B = this branch, Q4, `rax.c`, MTP. Resident, 2048 tokens and 32 generated: token ids equal and both logits dumps byte-identical. Streamed with 4915 slots, 128 generated: token ids equal.)*

## 3. The bench (design D4, D5)

- [x] 3.1 The three `capped-*` kinds in `ab_bench.py`, on request only; `python3 speed-bench/ab_bench.py --help` names them. *(Decode is their headline metric; the record row is unchanged. `tests/test_ab_bench.py`: 31 OK.)*
- [x] 3.2 One engine open per target at the service's configuration: the slot counts for 48, 54 and 60 GiB. Record them in `$SCR/c190/steps.txt`. *(Design D4. The bench has no `--vision`: opens at `--ctx-alloc 262144 --mtp`, the projector's 0.57 GiB added.)*
- [x] 3.3 An A/A run at 54 GiB in the capped, RAM-taken condition: the spread of each metric over 8 pairs, which is the resolution later changes are judged against. *(One 600 s invocation per kind, the GGUF evicted first. A first attempt ran with 71 GiB of the GGUF left in the file cache by earlier buffered runs, which `F_NOCACHE` reads still use: it measured 42.3 t/s instead of 29.9, and the harness now evicts before an uncached series (design D5). `capped-mtp-code`, 6 pairs: decode 29.94 / 29.82 t/s, -0.45% [-3.19%, +0.17%], pair range -4.7% to +0.2%; prefill 8192 -0.52% [-1.74%, +1.44%]. `capped-plain`, 4 pairs: decode 22.91 / 22.96, +0.15% [-3.92%, +4.39%]; prefill -0.51% [-2.41%, +1.64%]. One invocation gives 4 to 6 pairs here, so 8 pairs take two; a single pair can move 4%.)*

## 4. The tables (design D6, D7, D8)

- [x] 4.1 Q4 at 48, 54 and 60 GiB, the three kinds, RAM taken and RAM free, in a clean window: decode and prefill rates, misses and miss layers per token. *(3 runs per cell by hand, each after an evict; misses from one run per cell of the step-0 counter. Table in `docs/SSD_STREAMING.md`. RAM taken, the runs of a cell agree within 1%.)*
- [x] 4.2 Fix the development value by D7. *(54 GiB, 9,701 slots: the table has no knee in the range; MTP code decode rises 24.5 -> 29.8 -> 36.0 t/s.)*
- [x] 4.3 Use 1: the two ends of D8, Q4 and Q2. *(One run per cell. Assumed budget 36 GiB at an 8192-token context with MTP: 6,727 slots on Q4, 13,086 on Q2. The emulated end decodes 14-29% slower than the hard end on every kind and pack, so it is not the generous end D8 expected: its cache is too small for the file cache to make up. Table in `docs/SSD_STREAMING.md`.)*

## 5. Closing

- [x] 5.1 `docs/SSD_STREAMING.md`: the capped-RAM section with 4.1's table, the switch, the bracket for a 48 GB Mac, and the corrected account of the emulated figures. `AGENTS.md`: the bench condition for streaming work, in the development loop. *(Also: `docs/SSD_STREAMING.md` now names the old figures "Emulated 48 GB" and says what they measured; `AGENTS.md` gives the `ab_bench.py` line.)*
- [x] 5.2 Update `189-ssd-handshake-gated` design D2 and tasks to this bench; open C1 to C3 only where their gate passes (design D9). *(189 D2: the slot counts, the eviction before an uncached series. C1 to C3 are not opened here: the main session proposed them as `195` (read mode under pressure, C1), `193` (staging reserve, C2) and `198` (agent appends, C3).)*
- [x] 5.3 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. *(Model gates on Q4 and Q2 all PASS (identity, limits, turns, ds4_test, vision, host paths); PARITY OK (10 prompts).)*
- [x] 5.4 `openspec validate 190-ssd-capped-ram-bench --strict` passes.
- [x] 5.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c190/` and the worktree `190-trace`; archive the change. *(Landed as one signed commit; report through the night log.)*
