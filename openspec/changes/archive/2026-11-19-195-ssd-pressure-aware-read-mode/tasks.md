# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard (the neighbour runs inside the guarded tree).
`$SCR/c195/` holds this change's files.

## 1. Neighbour and step 0 (design D1, D2)

- [x] 1.1 The scratch neighbour tool; a dry run without a model: it holds 60 GiB, the guard sees it, nothing wires. *(Done 2026-11-19: `$SCR/c195/neighbour`, random words (a real neighbour does not compress to nothing), one touched page per 64 MiB a second, `task_info` compressed bytes and the slowest touch pass at exit. Dry run: 60 GiB written in 13.8 s, footprint 60.03 GiB, compressed 0.00, wired unchanged at 3.6-4.2 GiB, the guard logged it.)*
- [x] 1.2 Step 0 table at 54 GiB. Choose S1, S2, both or none by D2; close if neither can pass D4. *(Done 2026-11-19 on `main` c6543a9 (with `186`'s pressure shrink) and a scratch switch that keeps row calls (decode, verification) buffered while prefill reads uncached ("split"). Q4, 10,725 slots (54 GiB at today's plan; D2's 9,701 predates `193`), each run after an evict, 3 runs per cell, medians (range). The guard's compressor limit was 15 GiB of growth from the start of a run, the memory rule's figure, and it logged `kern.memorystatus_vm_pressure_level` every second.*

  *| Reads | Neighbour | MTP code decode | Plain decode | Prefill 8192, MTP code / plain runs | Cold 32K prefill | Neighbour compressed |*
  *|---|---|---|---|---|---|---|*
  *| buffered | none | 48.73 (47.5-49.6) | 35.83 (35.4-35.8) | 773 / 780 | 1248 | - |*
  *| uncached | none | 34.21 (34.1-34.5) | 26.32 (26.1-26.5) | 768 / 775 | 1188 | - |*
  *| split | none | 40.02 (39.6-40.3) | 28.76 (28.7-28.8) | 775 / 778 | 1188 | - |*
  *| uncached | 60 GiB | 34.14 (33.7-34.4) | 26.25 (25.8-26.3) | 768 / 775 | 1185 | 0.00 GiB, slowest touch 0.3-0.6 ms |*
  *| buffered | 60 GiB | killed by the guard 18 s in (one run) | - | - | - | compressor 4.0 -> 47.3 GiB |*
  *| split | 60 GiB | killed by the guard in the first seconds of decode (one run) | - | 768-775 reached | - | compressor 4.9 -> 49.7 GiB, 2 GiB swapped |*

  *Beside the neighbour, buffered reads fill the file cache and the kernel makes room by compressing the neighbour, whose pages are older: the first buffered run took the compressor from 4 to 47 GiB while the guard itself stalled for 13 s, so further buffered runs beside it were not taken (the state the memory rule exists to stop). With uncached reads the neighbour lost nothing and the rates equal the RAM-free uncached ones. The pressure level stayed normal through all nine uncached runs (378 samples) and, in the split run, rose to warning only once the compressor had already grown by 10 GiB (free memory was at 0.1-0.5 GiB for 7 s before); no level reached the engine before that.*

  *D2: uncached spares the neighbour and buffered cannot run beside it, so S1 and S2 are compared on the RAM-free rows. S1 (split) loses 18% of MTP code and 20% of plain decode against buffered with the RAM free: a CI wholly below zero against `main`, which D4 forbids. S2 equals `main` with the RAM free, but its signal comes after the neighbour has lost about 10 GiB, and no buffered phase beside a neighbour completes under the guard, so its first D4 condition cannot be met or measured. Neither can pass D4: CLOSED. On a machine whose RAM other work holds, the read mode has to be chosen at launch (`DS4_METAL_STREAM_EXPERT_UNCACHED_READS=1`); `docs/SSD_STREAMING.md`, "A neighbour", records it.)*

## 2. Build (design D3; no GPU)

- [x] 2.1 Branch `perf/195-ssd-pressure-aware-read-mode`; every caller of the read pool with `rg`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.2 The chosen step(s) behind kill switches; model-less tests for the mode choice (class, pressure, hold time). *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`. *(Not run: closed after step 0, 2026-11-19.)*

## 3. Measure (design D4)

- [x] 3.1 Streamed equals resident on Q4 and Q2. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 3.2 With and without the neighbour at 54 GiB, then 48 and 60. Keep or drop by D4. *(Not run: closed after step 0, 2026-11-19.)*

## 4. Closing

- [x] 4.1 `docs/SSD_STREAMING.md` (read modes and when each applies). *(Done: "A neighbour", under "Capped RAM", with the step 0 figures.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 4.3 `openspec validate 195-ssd-pressure-aware-read-mode --strict`; report; land as one signed commit; archive. *(Docs only, 2026-11-19.)*
