# Tasks

GPU: section 1. Model runs strictly sequential, each under the one-second
memory guard. `$SCR/c198/` holds this change's files.

## 1. Measure (design D1, D2)

- [x] 1.1 Appends on 8K and 32K contexts at 48, 54 and 60 GiB (capped, RAM taken) and resident, 3 runs per cell. *(Done 2026-11-19 on `main` with 192, Q4, prose, MTP off, 16 tokens after each append, 3 runs per cell, medians, time to first token in ms (prefill time plus the first token). Streamed runs capped and uncached. 8K context, first 8192 / +64 / +256 / +1024 / +4096: resident 6675 / 201 / 360 / 934 / 3287; 48 GiB (8,350 slots) 9869 / 515 / 968 / 1979 / 4802; 54 GiB (10,725) 10123 / 558 / 709 / 1597 / 4434; 60 GiB (13,100) 10246 / 351 / 511 / 1275 / 3869. 32K context, first 32768 / +64 / +256 / +1024 / +4096: resident 20910 / 210 / 352 / 890 / 3040; 48 GiB 29302 / 530 / 858 / 2116 / 4426; 54 GiB 28185 / 443 / 637 / 1678 / 3941; 60 GiB 26990 / 394 / 489 / 1293 / 3501. At 54 GiB an append takes 2.1-2.8x resident at 64 tokens, 1.8-2.0x at 256, 1.7-1.9x at 1024, 1.3x at 4096: the streamed part is at least a quarter of every append, well above D3's 10%.)*
- [x] 1.2 Attribution runs with the timing summary and command-buffer times. *(Done 2026-11-19 on `main` 60e5189 with a scratch bench that prints, per frontier, the prefill wall, the GPU busy time summed over the command buffers it waited on, and the stream timing summary's delta over that prefill; Q4, prose, MTP off, the 1.1 shapes, one run per cell, resident and 54 GiB (10,725 slots, capped, uncached). Per append, wall resident / streamed, GPU busy resident / streamed, streamed GPU idle, reads (sum of per-layer read walls), ms: 8K +64 165/437, 156/241, 196, 105; +256 324/673, 298/320, 353, 402; +1024 818/1585, 720/743, 843, 886; +4096 2803/4315, 2415/2453, 1862, 2068. 32K +64 189/435, 170/237, 198, 122; +256 365/612, 336/318, 293, 345; +1024 910/1658, 807/761, 897, 950; +4096 3123/3957, 2716/2520, 1437, 1633. Each append is one chunk, 48 layer loads, no split layers. From 256 tokens the gap is the read wait (reads 41-60% of the append); at 64 tokens reads are 24-28% and the extra GPU time (67-85 ms) plus idle no read explains (76-91 ms) are 33-40%.)*

## 2. Closing (design D3)

- [x] 2.1 The table and the attribution in `docs/SSD_STREAMING.md`. *("Appends on a long context", under "Capped RAM".)*
- [x] 2.2 Follow-up proposals for the candidates that pass D3, each with its share of the gap. *(`202-ssd-append-next-layer-reads`: the one-layer-ahead pipeline for multi-row calls, against reads of 24-60% of an append. `203-ssd-short-append-fixed-cost`: the row-count kernels and per-layer stop of a 64-token append, 33-40% of it. The chunk size is not a candidate: every measured append is one chunk, and its per-layer fixed cost is `203`'s.)*
- [x] 2.3 `openspec validate 198-ssd-agent-append-shapes --strict`; report; land as one signed commit (docs only); archive. *(2026-11-19.)*
