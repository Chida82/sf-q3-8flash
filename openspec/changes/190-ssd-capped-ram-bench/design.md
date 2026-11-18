# Design

## Context

Qwen3.8 Flash Next has 48 trunk layers of 512 routed experts, 10 used per
token: 24,576 experts, 2.59 MiB each on Q4 (61.6 GiB) and 1.39 MiB on Q2
(33.4 GiB). A streamed layer call reads the router's ids, and every one of
its experts that is not in the cache is read from the GGUF before the layer's
expert pass can finish. Q2 resident is 42 GiB, so use 2 concerns Q4.

The engine plans the cache from a budget, the smaller of 7/8 of the RAM and
Metal's recommended working set (107.52 GiB on this 128 GiB Mac, 84%), less
the static weights (6.32 GiB), the graph for the context, the staging
windows (2.59 GiB on Q4) and 2 GiB. `--ssd-streaming-cache-experts` lowers
the cache below the plan, never above it.

## Decisions

### D1. Two uses, three bench conditions

| Condition | Memory lock | Expert cache | Expert reads | Models |
|---|---|---|---|---|
| **capped, RAM taken** (development) | none | fixed from the footprint | uncached | use 2 with other work holding the RAM: a miss is an SSD read |
| capped, RAM free | none | the same | buffered | use 2 with nothing else running: a miss is usually a copy from the file cache |
| emulated 48 GB | 80 GiB | the plan under the lock | buffered | neither use (D2); kept only as D8's generous end |

A change is developed and kept or dropped in the first condition. The second
is reported beside it and decides nothing.

### D2. Why the memory lock is not the development bench

For an emulated size of X GiB the lock is 128 - X. With about 5 GiB wired by
the system, the wire room left is 108.8 - (133 - X) = X - 24.2 GiB, and the
plan's budget is Metal's recommendation scaled to it, 0.84 x (X - 24.2). A
machine that really has X GiB plans about 0.84 X if Metal keeps this Mac's
ratio there (not measured on one). The emulation is
therefore about 20 GiB under the real plan at every X, and the RAM it does
not plan, about 0.16 X + 20 GiB, is file cache. At X = 48: budget 19.5 GiB
measured (19.36-19.57 across `185`'s runs), 25 GiB of file cache measured.

No lock size reaches a small file cache: the wire limit caps lock plus plan
at about 104 GiB, which leaves the kernel at least 16 GiB. The lock is also
the one condition that has hung this Mac (2026-09-26) and that needs the
no-container rule. Uncached reads need neither.

### D3. The switch

`DS4_METAL_STREAM_EXPERT_UNCACHED_READS=1`, read when streaming is enabled.
The code is `dc50997` (`185` S1) with the default inverted: a second
descriptor on the GGUF, checked to be the same file, with `F_NOCACHE` and
read-ahead off, and reads of whole pages into a per-thread page-aligned
buffer from which the expert's bytes are copied. Three points:

- **Alignment is what makes it uncached.** sf-ds4-1flash `268` measured that
  on APFS an `F_NOCACHE` read that does not start on a 16 KiB page leaves
  about 26% of its pages in the file cache, and that a misaligned destination
  leaves 65%. The bounce buffer aligns offset, length and destination.
- **The check.** After a run the GGUF's resident pages are the static weights
  and nothing else: 6.33 GiB measured on 2026-11-18, against 59-64 GiB after a
  buffered run.
- **The cost it adds is the right one.** The copy out of the bounce buffer is
  the copy a buffered miss also pays, out of the file cache. The condition is
  the pessimistic end of use 2: with the RAM taken the kernel still keeps a
  little file cache, and here it keeps none.

One model-less case in `tests/test_qwen4_ssd_experts.c`: the uncached read
returns the same bytes as the buffered one for an unaligned range that
crosses the bounce size, and the fallback to the buffered descriptor works
when the second open fails. Whether uncached reads should become the default
for a class of reads is not decided here (D9, candidate C1).

### D4. From a footprint to a cache size

The footprint is the engine's own "planned" total: KV, graph buffers, static
weights, expert cache and staging. It is read from one engine open at the
service's configuration (`--ctx 262144 --mtp`, vision loaded) for each
target, and the slot count that gives 48, 54 and 60 GiB is recorded with the
table. Measured so far, at an 8192-token context and MTP:

| Configuration | Before the cache | Of which |
|---|---|---|
| 8192-token context, MTP | 16.98 GiB | statics 6.32, staging 2.59, KV and graph buffers 8.07 |
| `--ctx 262144 --mtp` (the service, without vision) | 28.92 GiB | statics 6.32, staging 2.59, KV 8.33, graph buffers 11.68 |

The vision projector adds 0.57 GiB. At the service's configuration the
three targets therefore leave the cache about:

| Footprint | Expert cache | Slots | Share of Q4's experts |
|---|---|---|---|
| 48 GiB | 18.5 GiB | about 7,330 | 30% |
| 54 GiB | 24.5 GiB | about 9,700 | 39% |
| 60 GiB | 30.5 GiB | about 12,080 | 49% |

Task 3.2 replaces the estimates with the slot counts of real opens. Two
things follow already. The planned total is the worst case: a run that uses
little of its context held about 10 GiB less than planned (50.2 GiB at a
60.5 GiB plan). And the context is the largest fixed term: 262144 tokens
reserve 12 GiB more than 8192, which at this footprint is a fifth of the
experts.

### D5. Protocol

- Kinds added to `ab_bench.py`, on request only: `capped-mtp-code`,
  `capped-mtp-prose` and `capped-plain`, an 8192-token context and 512
  generated tokens, so the cache passes its warm-up inside the run. The
  existing `--env` and `--bench-arg` set the switch and the cache size on
  both sides; no other option is needed.
- A B B A pairs, at least 8 per kind, the harness's token gate on every
  pair.
- Uncached runs leave nothing in the file cache, so every run starts from
  the same state without an eviction step. The buffered condition evicts the
  GGUF's pages before each run, as in `185`.
- Every model run stays under the one-second memory guard. Without a lock
  the guard watches the compressor against its value at the start of the run
  (growth over 5 GiB), free plus inactive under 3 GiB, and wired plus
  compressor over 120 GiB.
- Timing taken while a container, a VM or a scan was busy never grounds a
  drop or a neutral result. The switch removes the dependence on free RAM,
  not on a shared CPU, GPU or drive.

### D6. Step 0: misses per layer call against the cache size

Taken on 2026-11-18 on Q4, one run per cell, with a scratch counter that
prints, for every streamed layer call, how many of its routed experts were
not cached. Counts do not depend on the load of the machine; the rates
beside them were taken with a VM running and are indicative only.

| Cache: share, slots, GiB | Layer calls with every expert cached, %: MTP code / MTP prose / plain code / plain prose | Decode, t/s, same order |
|---|---|---|
| 2%, 492, 1.2 | 0.0 / 0.2 / 0.1 / 0.7 | 9.6 / 9.6 / 8.3 / 10.6 |
| 5%, 1229, 3.1 | 0.7 / 3.1 / 3.3 / 11.3 | 12.0 / 13.6 / 10.7 / 14.2 |
| 10%, 2458, 6.2 | 2.4 / 10.8 / 9.0 / 25.1 | 14.5 / 17.7 / 12.9 / 17.2 |
| 20%, 4915, 12.4 | 9.2 / 30.9 / 23.3 / 51.1 | 19.2 / 25.1 / 16.4 / 23.3 |
| 30%, 7373, 18.6 | 22.8 / 54.2 / 41.8 / 74.5 | 24.4 / 31.4 / 19.4 / 28.5 |
| 40%, 9830, 24.8 | 36.1 / 75.1 / 54.8 / 86.8 | 30.0 / 36.6 / 22.9 / 31.8 |
| 50%, 12288, 31.0 | 54.8 / 85.2 / 70.5 / 92.0 | 35.8 / 39.2 / 26.7 / 33.7 |
| 60%, 14746, 37.3 | 72.6 / 91.1 / 81.2 / 95.4 | 41.3 / 41.4 / 29.8 / 35.0 |
| 70%, 17203, 43.5 | 83.6 / 95.4 / 89.6 / 97.7 | 47.2 / 42.8 / 32.6 / 35.9 |

Conditions: an 8192-token context, 512 generated tokens, uncached expert
reads, no memory lock; the shares are over the second half of each run. An
MTP pass verifies 1.93 tokens on code and 1.48 on prose. Resident on this Mac
is about 47-49 t/s plain and 65 (code) and 50 (prose) with MTP, measured at
other contexts. 30%, 40% and 50% are close to the 48, 54 and 60 GiB
footprints of D4.

What the table says:

- **Under 10% almost no layer call finds its experts.** That is where
  emulated 48 GB put Q4 (4%), and why the file cache decided every figure
  taken there.
- **The owner's range is the steep part.** From 48 to 60 GiB decode goes
  from 24.4 to 35.8 t/s on MTP code (+47%), from 31.4 to 39.2 on MTP prose,
  from 19.4 to 26.7 and from 28.5 to 33.7 plain. On code there is no knee
  inside the range, about 0.9 t/s per GiB of cache; on prose the curve bends
  near 40%.
- **Code needs far more cache than prose** for the same share of all-cached
  calls, plain or MTP.
- **A full cache does not reach resident.** At 70%, plain prose misses on
  2.3% of the layer calls and decodes at 35.9 t/s, against 47-49 resident:
  the stop at every layer, which `191` is about.
- **The first prefill slows as the cache grows**, 8192 tokens from 887-890
  to 760-767 t/s on prose between 2% and 70%. Locking the cache's slabs takes
  0.12 s at 6 GiB and 0.77 s at 43 GiB, about half of the difference; the
  rest is not traced.

With the RAM free instead, the three buffered runs that completed before the
guard stopped that series give MTP code 28.5, 31.6 and 32.4 t/s at 2%, 5%
and 10%, against 9.6, 12.0 and 14.5 here: the file cache was doing the work
of a 40% cache.

### D7. The development value

54 GiB, the middle of the owner's range: D6 shows no knee that would move
it, and at 39% of the experts both miss layers and all-cached layers are
common, so a change to either is visible. Each later streaming change is
developed at 54 and measured at 48 and 60 before it lands; its record row
carries the three. For the service itself D6 already says the fastest
setting in the range is its top, and that a smaller `--ctx` buys cache at
the same footprint; both are the owner's to choose.

### D8. Use 1, the closing check

A 48 GB Mac is bracketed, not emulated: the cache it would plan (about 36 GiB
of budget, less the fixed part), without a lock, once with uncached reads
(no file cache at all, the hard end) and once under the 80 GiB lock with the
plan's own small cache (25 GiB of file cache, the generous end). The real
machine has a few GiB of file cache and sits between, nearer the hard end.
One table per pack in `docs/SSD_STREAMING.md`, replacing the reading of the
emulated figures as "a 48 GB Mac".

### D9. What follows, and what is taken from sf-ds4-1flash

Read against that child's record (`speed-bench/perf-record.md`, changes `30`
to `770`), each lesson with its state here:

| sf-ds4-1flash | What it found there | Here |
|---|---|---|
| `30`, `130`, `131`, `132`, `210`: the layer round trip in decode | its largest decode steps: layers queued without a wait (17.5 -> 20.1 t/s), a bounded poll instead of a blocking wait (20.4 -> 22.3), id-independent work ahead of the wait (22.3 -> 22.6) and ids through a polled mailbox (+5.5%) | not done: every streamed layer call drains with a blocking wait. **`191`** |
| `132` D3, `680`: the expert pass committed ahead, behind a CPU-signalled event | restarts no faster than a commit, about 100 us; closed twice | bounds `189`'s handshake, which parks the pass on such an event; `189` runs after `191` S0 |
| a fixed cache and steady state for every figure (`6898b39`, `4353306`) | plan-sized caches and cold starts measured the start state, not the change | this change |
| `225`: count miss layers, not misses; a miss-size curve before any cache lever | a layer stops once whatever the number of misses | D6; the unit for `188`-style work from now on |
| `100`, `268`: prefill's bulk reads uncached and page-aligned | the sweep no longer evicted pages decode needs: first token after 8192 from 1230 to 150 ms, append +12.5% | **C1**: uncached reads for prefill staging only, decode misses buffered. Never measured: `185` switched every read at once. Gate: with the RAM free, the prefill and decode rates and what the run leaves in the file cache and in the compressor of a neighbour |
| `240`: decode misses uncached | closed, the file cache serves 20-28% of them | agrees with `185`; buffered stays the default for decode misses |
| `760`, `750`: static weights locked, prefaulted | prefill after other I/O +22% | already so here: Qwen's statics are always locked (`ds4.c`, engine open) |
| `230`: lend prefill-only memory to the cache during decode | +0.6/+2.3% decode but the first token paid a 200 ms allocation | **C2**: the staging windows (2.59 GiB on Q4) reused in place as cache slots between prefills, and the prefill chunk's graph reserve against cache inside a fixed footprint. D6's slope makes this worth a gate: at 54 GiB a GiB of cache is about 0.9 t/s on MTP code, so the staging alone is about 8% |
| `110`: LRU against hotness; `170`: next-layer prediction | never fewer misses; the guess costs more than it hides | agrees with `188` D2 and `185` S2; not reopened |
| `770`: short appends as one sweep | append +300 from 9.6 to 6.2 s | **C3**: measure the appends an agent sends (64 to 1000 tokens) in the capped condition before proposing anything |
| `220`: keep-alives | lost; the clock is already at its top in decode | not tried |

C1 to C3 become proposals only if their gate, read from this change's
tables, passes.

## Risks / Trade-offs

- **The hard end overstates a miss** when a little file cache would have
  served it. A change that wins there and loses with the RAM free is
  reported as such; development still follows the owner's condition.
- **The switch is product code that only a bench sets.** It is small, and
  C1 may give it a default of its own; without it no A side on `main` can
  run the condition.
- **One run per cell in D6.** Counts are deterministic for a given cache
  size and prompt; the rates are not, and are re-taken by task 3.
