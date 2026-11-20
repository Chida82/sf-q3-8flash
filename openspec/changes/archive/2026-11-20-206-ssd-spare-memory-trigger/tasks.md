# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard (the neighbour inside the guarded tree).
`$SCR/c206/` holds this change's files.

## 1. Step 0 (design D3)

- [x] 1.1 Scratch sampler; beside the neighbour and without it, capped Q4 at 54 GiB, uncached. Close if the estimate does not lead the system level. *(Done 2026-11-20 on `main` bb1f9e8 with a scratch sampler (`$SCR/c206/spare`: design D1's estimate, D2's would-be level, `kern.memorystatus_vm_pressure_level` and the compressor, every second) and the `195` neighbour (60 GiB of random words, touched once a second) inside the guarded tree; Q4 at 10,725 slots (the `195` setup), capped, uncached, MTP code 8K + 512 tokens, each run after an evict. Reserve 7.0 GiB (7% of 128 GiB, clamped), warning under 8.0 GiB.*

  *| Run | Lowest free | At that moment: spare / file-backed / inactive anonymous | Lowest spare | Would-be level | System level | Neighbour compressed | Decode |*
  *|---|---|---|---|---|---|---|---|*
  *| neighbour, 1 | 0.21 GiB | 39.3 / 26.6 / 25.0 (falling) | 24.4 GiB | normal | normal | 0.00 GiB | 34.4 t/s |*
  *| neighbour, 2 | 0.21 GiB | 24.7 / 8.0 / 33.1 | 24.4 GiB | normal | normal | 0.00 GiB | 34.6 t/s |*
  *| none | 60.0 GiB | 69.3 / 8.0 / 2.6 | 69.3 GiB | normal | normal | - | 34.4 t/s |*

  *Beside the neighbour free memory stayed at 0.2 GiB for the whole decode, yet the estimate never fell below 24.4 GiB: 8 GiB of file-backed pages (the locked static weights and system files) and half of 33 GiB of inactive anonymous pages, which are the neighbour's and, being random, could not compress at all. The would-be level stayed normal, as the system's did, and there was nothing to protect: with uncached reads the neighbour lost nothing. In the harmful case of `195` (buffered reads filling the file cache while the kernel compressed the neighbour) this formula counts the growing file cache as spare, as macOS does, so it would not lead there either; what moved first there was the compressor. The estimate does not lead the system level: CLOSED by this task. The S1 code (sampler, combined level, seams, tests, the regrowth-after-failed-slab test that closes `186`'s doubt) was kept on `fix/206-ssd-spare-memory-trigger` and not landed. At the owner's request only the regrowth-after-failed-slab seam and its check (inside `check_pressure`) landed on `main`; the branch is deleted.)*

## 2. S1 (design D1, D2; no GPU)

- [x] 2.1 Branch `fix/206-ssd-spare-memory-trigger`; every reader and writer of the pressure level with `rg`. *(Written ahead of step 0 on the branch, during a window with no GPU; not landed: closed after step 0, 2026-11-20.)*
- [x] 2.2 The sampler and the combined level; model-less tests through a seam that feeds spare-memory values (thresholds, hysteresis, combination with the system level). *(Written ahead of step 0 on the branch, during a window with no GPU; not landed: closed after step 0, 2026-11-20.)*
- [x] 2.3 186's doubt: a seam that fails the next slab allocation; a test that regrowth waits a quiet period and then resumes. *(Written ahead of step 0 on the branch, during a window with no GPU; not landed: closed after step 0, 2026-11-20.)*
- [x] 2.4 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`. *(Written ahead of step 0 on the branch, during a window with no GPU; not landed: closed after step 0, 2026-11-20.)*
- [x] 2.5 Step review. *(Written ahead of step 0 on the branch, during a window with no GPU; not landed: closed after step 0, 2026-11-20.)*

## 3. Measure (design D4)

- [x] 3.1 Streamed equals resident on Q4 and Q2 with injected transitions. *(Not run: closed after step 0, 2026-11-20.)*
- [x] 3.2 No-pressure cost at 54 GiB, three kinds; the neighbour run. Keep or drop by D4. *(Not run: closed after step 0, 2026-11-20.)*

## 4. Closing

- [x] 4.1 Final review pass; `docs/SSD_STREAMING.md` ("Memory pressure"). *(Not run: closed after step 0, 2026-11-20.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Not run: closed after step 0, 2026-11-20.)*
- [x] 4.3 `openspec validate 206-ssd-spare-memory-trigger --strict`; report; land as one signed commit; archive; delete `$SCR/c206`. *(Docs only, 2026-11-20; `$SCR/c206` deleted.)*
