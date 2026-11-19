# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c202/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 Ceiling per append size at 54 GiB, 8K and 32K. Close by the proposal's rule. *(Done 2026-11-19 on `main` (c6543a9 code) with a scratch probe: per streamed call of more than 3 rows, the layer's routed and missing experts, the read wall of its misses, the next layer's uncached set when this layer's experts are bound, and the GPU time after that bind until the next layer's drain (spans of the waited command buffers); the bench marks each frontier. Q4, prose, MTP off, 16 tokens after each append, 54 GiB (10,725 slots), capped, uncached, one run per cell; the 32K bench replays the prefix after each decode (snapshot above 1 GiB), as in `198`. Per layer, then per append (wall from the bench):*

  *| Context | Append | Routed / missing | Next layer uncached | Read, ms | GPU after bind, ms | Wall, ms | D1 ceiling (read every uncached expert) | Perfect prediction |*
  *|---|---|---|---|---|---|---|---|---|*
  *| 8K | +64 | 112 / 9.5 | 293 | 2.26 | 5.05 | 404 | -3144 ms | 106 ms (26%) |*
  *| 8K | +256 | 193 / 38.4 | 296 | 8.69 | 7.32 | 844 | -2496 ms | 302 ms (36%) |*
  *| 8K | +1024 | 260 / 87.0 | 310 | 19.60 | 11.50 | 1676 | -1859 ms | 538 ms (32%) |*
  *| 8K | +4096 | 376 / 205 | 341 | 45.57 | 36.20 | 4416 | +138 ms (3.1%) | 1585 ms (36%) |*
  *| 32K | +64 | 113 / 10.7 | 295 | 2.45 | 4.96 | 419 | -3020 ms | 114 ms (27%) |*
  *| 32K | +256 | 184 / 32.4 | 293 | 7.14 | 5.06 | 661 | -2484 ms | 224 ms (34%) |*
  *| 32K | +1024 | 299 / 93.3 | 294 | 19.84 | 11.21 | 1694 | -1507 ms | 516 ms (30%) |*
  *| 32K | +4096 | 375 / 162 | 296 | 34.36 | 38.14 | 3993 | +135 ms (3.4%) | 1487 ms (37%) |*

  *D1's ceiling is the sum over layers of min(read of l+1, GPU of l) less the read time of the uncached experts l+1 does not route, at the layer's own per-expert read time. The proposal's premise does not hold: a chunk routes 22% (64 tokens) to 73% (4096) of a layer's experts, never the ~90% D2 needs for N, and the cache already holds 45-92% of what it routes, so reading every uncached expert of the next layer reads 1.7 (4096 tokens) to 30 times (64) what that layer misses. Under 10% at every append size: CLOSED by the proposal's rule. The reads would overlap well (a layer's GPU time covers most of the next layer's reads: a perfect prediction hides 26-37% of every append), so a predicted variant (the next layer's router on this layer's input, as `194` did for decode rows; a chunk's prediction is a union over many rows) is a different change, not written here.)*

## 2. S1 (design D2; no GPU)

- [x] 2.1 Branch `perf/202-ssd-append-next-layer-reads`; every caller of the pending-load path with `rg`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.2 Early reads of the next layer for multi-row calls; model-less test: early-read slots are exact, protected, and survive a failed read. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.4 Step review. *(Not run: closed after step 0, 2026-11-19.)*

## 3. Measure (design D3)

- [x] 3.1 Streamed equals resident on Q4 and Q2. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 3.2 Appends at 54, then 48 and 60 GiB; capped decode kinds. Keep or drop by D3. *(Not run: closed after step 0, 2026-11-19.)*

## 4. Closing

- [x] 4.1 Final review pass; `docs/SSD_STREAMING.md` (appends). *(Docs only: "Appends on a long context" corrected; it said a chunk routes most of a layer's experts.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 4.3 `openspec validate 202-ssd-append-next-layer-reads --strict`; report; land as one signed commit; archive; delete `$SCR/c202`. *(Docs only, 2026-11-19. `$SCR/c202` stays until `203`, which shares its probe runs, is closed or landed.)*
