# Design

## Context

The stream expert cache is a set of slots in locked slabs of owned Metal
buffers. Entries in use by the current layer are protected; eviction is by
decayed route hotness, then LRU. The plan at open fixes the slot count.

## Decisions

### D1. The signal

A `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` source for warning and critical,
created at engine open when `--ssd-streaming` is on and cancelled at close.
Its handler only records the level; the cache acts on it at the next layer
boundary, on the thread that owns the cache. No lock is added to the read
path.

The level is also read once at open. If it is not normal, the engine opens at
the floor and says so.

### D2. Shrinking

- Unit: one slab. A slab is released only when it holds no protected entry;
  its live entries are dropped (they can be read again), its memory unlocked
  and freed.
- Warning: release slabs until the cache is one quarter smaller than planned,
  or the floor is reached. Critical: release down to the floor.
- Floor: the staging the current context and prefill chunk need, plus the
  slots one layer's largest routed set needs. It is computed at open with the
  plan, so a shrink can never make a request fail.
- A shrink never happens inside a layer. A prefill chunk that needs more
  experts than the cache holds already runs through layer staging; that path
  is the one a shrunken cache uses.

### D3. Regrowing

After 30 s without a warning or critical level, grow by one slab; repeat
every 30 s up to the planned size. A slab that cannot be allocated or locked
ends regrowth until the next quiet period. The planned size is never
exceeded.

### D4. Validation without making the Mac short of memory

Inducing real pressure on this machine is not acceptable as a routine test.

- **Model-less (`make test`).** A test seam injects a pressure level into the
  handler. `tests/test_qwen4_ssd_experts` checks: shrink to the quarter step
  and to the floor; no protected entry is released; an evicted expert is read
  back and gives the same bytes; regrowth stops at the planned size; a failed
  slab allocation is survived.
- **Model, injected.** `DS4_METAL_STREAM_TEST_PRESSURE=warn|critical@<token>`
  (scratch-only patch, never committed) fires the level in the middle of a
  streamed decode at emulated 48 GB. Gate: tokens identical to the resident
  run, on plain and MTP kinds, Q2 and Q4; the log shows the shrink and the
  later regrowth.
- **Model, real signal, once.** One streamed run at emulated 48 GB beside a
  helper that allocates and touches memory in 2 GiB steps up to 12 GiB, then
  frees it. The run is watched with the kill criteria of 2026-11-17
  (compressor over 15 GiB, free plus inactive under 3 GiB, wired plus
  compressor over 120 GiB) and stopped by them. Gate: the engine logs a
  shrink before any criterion fires, and tokens are identical. If no pressure
  level is raised within the helper's 12 GiB, record that and do not push
  further.

### D5. Cost when there is no pressure

One atomic load per layer boundary. Measured with `ab_bench.py` at emulated
48 GB against `main`: no metric's pooled CI wholly below zero.

### D6. What is not taken

- Splash's memory ledger with typed claims, `--max-memory`, idle release of
  weights and the release endpoint. `--ssd-streaming-cache-experts` already
  caps the cache, and unloading the model is a different feature.
- KV spill to SSD under pressure.

## Risks / Trade-offs

- **A shrunken cache decodes slower.** That is the point: slower instead of a
  machine that stops. The log line says why.
- **The pressure level is system-wide.** Another process's burst shrinks our
  cache although we are not the cause; regrowth after 30 s bounds the cost.
- **Unlocking then freeing slabs under critical pressure** must not allocate.
  The release path is checked for allocation in review.
