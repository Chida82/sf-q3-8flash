# Proposal

## Why

`186` gives the streamed expert cache back to the system when macOS raises
its memory-pressure level. In 186's one real-signal run free memory fell to
0.1 GiB and the compressor grew, yet no level was raised. In `195`, with a
60 GiB neighbour beside a 54 GiB streamed process, the level stayed normal
through nine runs while free memory touched 0.4 GiB, and rose to warning
only after the compressor had already taken 10 GiB of the neighbour. The
level comes too late to protect the work beside the model.

Splash (incoai) does not wait for the level alone: it computes spare memory
itself (free, file-backed and purgeable pages, plus half of what
compressing other processes would free) and gives memory back when that
falls below a reserve of 7% of RAM (2-7 GiB) plus a 1 GiB margin. Only the
idea is taken; no code.

## What Changes

- **Step 0.** With the neighbour tool (scratch, from `195`) and uncached
  reads only, a scratch sampler logs the spare-memory estimate and the
  system level every second beside a capped run: the estimate must cross
  its threshold where the level stays normal. Close if it does not.
- **S1.** A one-second sampler on a utility queue computes the spare
  estimate and turns it into a level with hysteresis: below the reserve plus
  margin a warning, below the reserve a critical level, back to normal only
  above the reserve plus twice the margin. It feeds 186's existing note:
  the level the cache acts on is the higher of the system's and the
  sampler's. The streamed call keeps one atomic load when nothing is due.
- **186's open doubt.** A test seam and a model-less test for regrowth
  after a failed slab allocation.

Output does not change: a smaller cache changes what is read, never what a
layer computes.

## Impact

- `ds4_metal.m` (the pressure source of 186), `tests/test_qwen4_ssd_experts.c`,
  `docs/SSD_STREAMING.md` ("Memory pressure").
- A scratch sampler; nothing installed.
