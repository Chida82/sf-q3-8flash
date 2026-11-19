# Tasks

GPU: section 1. Model runs strictly sequential, each under the one-second
memory guard. `$SCR/c198/` holds this change's files.

## 1. Measure (design D1, D2)

- [x] 1.1 Appends on 8K and 32K contexts at 48, 54 and 60 GiB (capped, RAM taken) and resident, 3 runs per cell. *(Done 2026-11-19 on `main` with 192, Q4, prose, MTP off, 16 tokens after each append, 3 runs per cell, medians, time to first token in ms (prefill time plus the first token). Streamed runs capped and uncached. 8K context, first 8192 / +64 / +256 / +1024 / +4096: resident 6675 / 201 / 360 / 934 / 3287; 48 GiB (8,350 slots) 9869 / 515 / 968 / 1979 / 4802; 54 GiB (10,725) 10123 / 558 / 709 / 1597 / 4434; 60 GiB (13,100) 10246 / 351 / 511 / 1275 / 3869. 32K context, first 32768 / +64 / +256 / +1024 / +4096: resident 20910 / 210 / 352 / 890 / 3040; 48 GiB 29302 / 530 / 858 / 2116 / 4426; 54 GiB 28185 / 443 / 637 / 1678 / 3941; 60 GiB 26990 / 394 / 489 / 1293 / 3501. At 54 GiB an append takes 2.1-2.8x resident at 64 tokens, 1.8-2.0x at 256, 1.7-1.9x at 1024, 1.3x at 4096: the streamed part is at least a quarter of every append, well above D3's 10%.)*
- [ ] 1.2 Attribution runs with the timing summary and command-buffer times.

## 2. Closing (design D3)

- [ ] 2.1 The table and the attribution in `docs/SSD_STREAMING.md`.
- [ ] 2.2 Follow-up proposals for the candidates that pass D3, each with its share of the gap.
- [ ] 2.3 `openspec validate 198-ssd-agent-append-shapes --strict`; report; land as one signed commit (docs only); archive.
