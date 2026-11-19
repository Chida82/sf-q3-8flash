# Proposal

## Why

A streamed engine sizes its expert cache once, at open, from the smaller of
87.5% of physical RAM and Metal's recommended working set
(`docs/SSD_STREAMING.md`, `ds4.c:32465-32575`). After that it never gives
memory back and never notices that the machine ran short:

- the cache slabs are locked (`ds4_metal.m:12455-12530`), so the kernel
  cannot reclaim them;
- nothing in the tree listens for memory pressure: `rg` for
  `MEMORYPRESSURE`, `memorystatus` and `os_proc_available_memory` in
  `ds4*.c`, `ds4*.m`, `ds4*.h` finds nothing;
- the plan counts what is free at open, so an application, a container or a
  virtual machine started later takes memory the plan already spent.

On this Mac, running out of memory has ended in a kernel watchdog panic three
times in two days (2026-11-16 and 2026-11-17), not in a slowdown. Those
panics came from a second process opening the model, which this change does
not address. They show what a streamed server risks when it shares the
machine with other work, which is the case streaming exists for.

Splash 1.7.0 (incoai/splash, Apache-2.0) handles this for the same model: a
dispatch memory-pressure source plus `kern.memorystatus_vm_pressure_level`,
a reserve of 7% of RAM, expert-store chunks given back under shortage and
regrown after 30 s of quiet, never below a floor. The mechanism is exact: a
smaller cache changes which experts are read from disk, never what a layer
computes. No Splash code is copied.

Quality (robustness) under the intake criteria, on the streaming path the
owner named as a next focus.

## What Changes

- The streamed engine registers a memory-pressure source. On a warning it
  shrinks the expert cache by a step; on critical it shrinks to a floor.
  Released slots are unlocked and their buffers freed.
- After a quiet period the cache regrows, one step at a time, up to the size
  planned at open.
- The floor is the staging the current context needs plus a minimum of
  slots, so a request in flight always completes.
- The shrink and regrow are logged once each, with the sizes, and counted in
  the stream timing summary.
- The resident path and the engine-open admission are unchanged.

Output must not change: token ids of a streamed run under pressure stay
identical to the resident run.

## Impact

- `ds4_metal.m` (stream expert cache: slabs, slots, eviction), `ds4.c`
  (engine open and close), `tests/test_qwen4_ssd_experts.c`,
  `docs/SSD_STREAMING.md`, the `ssd-streaming` spec.
- Independent of `185-ssd-expert-read-path`; either order.
