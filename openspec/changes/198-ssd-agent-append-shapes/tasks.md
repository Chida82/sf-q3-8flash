# Tasks

GPU: section 1. Model runs strictly sequential, each under the one-second
memory guard. `$SCR/c198/` holds this change's files.

## 1. Measure (design D1, D2)

- [ ] 1.1 Appends on 8K and 32K contexts at 48, 54 and 60 GiB (capped, RAM taken) and resident, 3 runs per cell.
- [ ] 1.2 Attribution runs with the timing summary and command-buffer times.

## 2. Closing (design D3)

- [ ] 2.1 The table and the attribution in `docs/SSD_STREAMING.md`.
- [ ] 2.2 Follow-up proposals for the candidates that pass D3, each with its share of the gap.
- [ ] 2.3 `openspec validate 198-ssd-agent-append-shapes --strict`; report; land as one signed commit (docs only); archive.
