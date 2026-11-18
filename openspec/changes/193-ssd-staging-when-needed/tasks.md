# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c193/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 Scratch counter; Q4 and Q2, three footprints, plain and MTP. Close by D1 if Q4 takes the owned path.

## 2. The rule (design D2, D3; no GPU)

- [ ] 2.1 Branch `perf/193-ssd-staging-when-needed`; every reader of `ssd_streaming_prefill_headroom_bytes` with `rg`.
- [ ] 2.2 The rule in the plan, the plan line naming it; a test that a cache under 512 slots keeps the reserve.
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 3. Measure (design D4)

- [ ] 3.1 Slot counts for 48, 54 and 60 GiB after the change.
- [ ] 3.2 Streamed equals resident on Q4 and Q2.
- [ ] 3.3 A/B at the same footprint, 54 then 48 and 60. Keep or drop by D4.

## 4. Closing

- [ ] 4.1 `docs/SSD_STREAMING.md` memory plan; `190`'s footprint table.
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 193-ssd-staging-when-needed --strict`; report; land as one signed commit; archive.
