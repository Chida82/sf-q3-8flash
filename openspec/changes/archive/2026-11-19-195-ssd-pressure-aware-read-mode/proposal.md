# Proposal

## Why

Streamed expert reads go through the file cache, on purpose: with RAM to
spare, an evicted expert comes back from there at memory speed, and reading
past it cost decode 33% on Q2 and 41% on Q4 (`185`). That holds only while
the RAM is free. In the owner's second use (`190`: Q4 held to 48-60 GiB
while other work holds the rest) the same reads cost the neighbour: they
fill the file cache at the drive's rate and the kernel makes room by
compressing other processes. On 2026-11-18 four buffered streamed runs took
free memory from 10.8 to 0.1 GiB in two seconds each and pushed about 23
GiB of a running virtual machine into the compressor, until the memory
guard stopped the series. With the uncached reads `190` added, the same runs
left only the static weights in the file cache.

Neither mode is right for both cases, and the engine cannot be told which
case it is in at open: a neighbour can start later. The machine says it,
though: macOS raises memory-pressure notifications, and `186` already plans
to listen to them to shrink the cache.

sf-ds4-1flash made the same split by read class instead (`268`: bulk prefill
reads uncached and page-aligned, decode misses buffered, because the file
cache served 20-28% of them, `240`). Its machine had no neighbour; here the
class split is one candidate and the pressure signal another, and the
measurement decides.

## What Changes

- **A neighbour for the bench.** A scratch tool that holds and keeps
  touching N GiB of anonymous memory (never wired, so the kernel may
  compress it), and reports how much of it was compressed or swapped. It
  replaces "RAM taken" by a real neighbour for this change's measurement
  and checks `190`'s switch as a model of it.
- **Step 0.** At 54 GiB with a neighbour holding the rest (about 60 GiB):
  buffered against uncached reads, for decode, prefill, and their split by
  class: rates, and the neighbour's compressed and swapped bytes. Also with
  no neighbour. The table decides which of S1 and S2 is built.
- **S1, by class**: prefill (multi-row) reads uncached and page-aligned,
  decode and verification misses buffered.
- **S2, by pressure**: reads buffered while the system reports normal
  pressure, uncached from the first warning until it clears; the switch is
  per read, so nothing is reopened.
- The `190` switch stays as the forced mode for the bench.

Output does not change: the same bytes reach the same buffers.

## Impact

- `ds4_metal.m` (the read pool's choice of descriptor), the pressure source
  shared with `186` (whichever lands first adds it), `docs/SSD_STREAMING.md`.
- A scratch neighbour tool; nothing installed.
- Starts after `190`; shares its signal with `186`.
