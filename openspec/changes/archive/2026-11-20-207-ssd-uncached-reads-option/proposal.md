# Proposal

## Why

Streamed expert reads go through the macOS file cache by default. With RAM
to spare that cache serves evicted experts at memory speed; with the RAM
taken by other work it is a cost the process footprint does not show: the
file cache grows toward the whole model, and macOS compresses idle
applications rather than drop those pages (`195`: beside a 60 GiB
neighbour, the compressor took 43 GiB in 18 s while 20 GiB of model pages
stayed cached). Reads that bypass the file cache keep the 48-60 GiB
footprint real and leave the neighbour untouched (decode 34.1 against 34.2
t/s alone), and cost about 30% of decode when the RAM is free (MTP code
48.7 -> 34.2 t/s). Neither the system pressure signal (`195`) nor an own
spare-memory estimate (`206`) can choose the mode at run time, so it is
chosen at launch.

Today the only switch is the environment variable
`DS4_METAL_STREAM_EXPERT_UNCACHED_READS=1`, written for measurement (`190`).
The owner asked for a command-line option, clearly explained. `sfctl` does
not use it for now.

## What Changes

- `--ssd-streaming-uncached` in the CLI, server, bench and eval: with
  `--ssd-streaming`, routed experts are read with `F_NOCACHE`. Without
  `--ssd-streaming` the engine refuses to open and says why.
- If the uncached descriptor cannot be opened, the engine says so and the
  reads stay buffered (today this is silent).
- The help lists the SSD streaming options, the new one with a plain
  explanation of when to use it.
- The environment variable stays as an alias: `ab_bench.py` compares trees
  that predate the option, and the SSD unit test uses it. `ab_bench.py`
  evicts the GGUF before a series when either form is given.
- Docs: `docs/SSD_STREAMING.md` and `AGENTS.md` name the option.

Default behaviour does not change; output does not change in either mode.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ssd-streaming`: a launch option for reads that bypass the file cache.

## Impact

- `ds4.h`, `ds4.c` (engine options, open), `ds4_gpu.h`, `ds4_metal.m`
  (the switch), `ds4_cli.c`, `ds4_server.c`, `ds4_bench.c`, `ds4_eval.c`,
  `ds4_help.c`, `speed-bench/ab_bench.py`, `tests/test_qwen4_ssd_experts.c`,
  `Makefile`, `docs/SSD_STREAMING.md`, `AGENTS.md`.
- `sfctl/` unchanged.
