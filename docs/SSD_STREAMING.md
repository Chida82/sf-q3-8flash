# SSD streaming

With `--ssd-streaming`, Qwen3.8 keeps only its routed experts on disk. Dense
weights, shared experts, GDN, attention, hyper-connections, the router, the
head and the embeddings stay mapped (6.32 GiB for either pack). The BF16
n-gram table keeps its own disk reads. Routed experts are read on demand, with
`pread`, into a bounded cache of owned Metal buffers. The routed kernels take
each expert's GPU address from the cache through function constant 906, so
their arithmetic is the resident one. Greedy output is token-identical to a
resident run of the same build. The resident path compiles the address code
out and stays bit-identical.

```sh
./sf-q3-8flash --ssd-streaming --ctx 8192
./sf-q3-8flash-server --ssd-streaming --ssd-streaming-cache-experts 16GB
```

## Memory plan

At engine open the budget is the smaller of 87.5% of physical RAM and Metal's
recommended working set. From it the engine reserves:
- the mapped static weights;
- the graph for the context and prefill chunk;
- staging windows for the calls the cache cannot take: a layer whose experts
  have another size (Q2's MTP layer: one full predictor layer), and, when
  the cache left would hold fewer experts than one layer has (512), two full
  trunk layers;
- another 2 GiB for the runtime.

What is left becomes the expert cache, capped at every routed expert. The
plan line names which staging case applied. On Q4 at the footprints of
"Capped RAM" no call takes the owned path, so no staging is planned and the
same footprint holds 1,024 more experts (2.59 GiB); on Q2 with MTP the
reserve falls from 1.42 to 1.29 GiB (change `193`). If the
fixed part does not fit, the engine refuses to open and names both figures:

```
ds4: Qwen SSD needs 13.26 GiB before the expert cache; safe budget 8.22 GiB. Reduce context or prefill chunk.
```

`--ssd-streaming-cache-experts N` requests N cache slots, and `NGB` a byte
budget that includes staging. A request larger than the plan is capped.
Each new session is checked against the same budget. Qwen fills the cache on
demand: `--ssd-streaming-cold` changes nothing, and
`--ssd-streaming-full-layers` and `--ssd-streaming-preload-experts` are
refused.

A prefill batch that selects more experts than the cache holds, and the Q2
pack's differently quantized MTP layer, stage only the selected experts in
owned buffers. Cached experts compute while the missing ones load: gate/up
first, then down once its rows arrive, for decode, MTP verification and
prefill.

### Memory pressure

The plan is made once, at open, from what is free then. A streamed engine
also listens to the system's memory-pressure level (a dispatch source for
warning and critical, and `kern.memorystatus_vm_pressure_level` read at
open) and gives part of the expert cache back when the machine runs short
later (change `186`):

- **Warning**: the cache shrinks to three quarters of the plan.
- **Critical**: the cache shrinks to its floor, one layer's 512 experts, so
  a prefill chunk still fits and no call needs staging the plan did not
  reserve. A request in flight always completes.
- **At open**, a level that is not normal opens the cache at its floor.
- **Regrowth**: after 30 s at the normal level the cache grows by one slab,
  and again every 30 s, up to the planned size and never past it. A slab
  that cannot be allocated ends that step; the next waits another 30 s.

The cache shrinks by whole slabs (`DS4_METAL_STREAMING_EXPERT_SLAB_MB`,
4 GiB by default: 1,579 Q4 experts), newest first: their entries are
dropped, their pages unlocked and freed, and a dropped expert is read
again when a layer routes it. The handler only records the level; the cache
acts at the next streamed layer call, after that call has drained the GPU,
so nothing a command buffer reads is released. When an action is due on a
Q2 decode layer, that one layer takes the ordinary path instead of the
handshake, which does not drain. With no pressure the cost is one atomic
load per streamed layer call.

Each change is logged once, with the sizes, and the totals appear in the
memory report:

```
ds4: memory pressure warning: expert cache 10725 -> 7895 experts (27.17 -> 20.00 GiB), 5 slabs
ds4: memory pressure quiet: expert cache 7895 -> 9474 experts (20.00 -> 24.00 GiB), 6 slabs
ds4:   streaming expert cache memory pressure shrinks=1 regrows=2 size=10725 planned=10725
```

Output does not change: a smaller cache changes which experts are read
from disk, never what a layer computes.

## Eviction order

When the cache is full, a load takes the slot of another cached expert, of
any layer; the experts routed for the layer being computed are never taken.
The victim is the entry with the lowest route hotness (one count per
selection, hit or miss, halved every 16 passes), then the least recently
used.

Decode and MTP verification put one rule ahead of that order: an expert used
within the last full pass over the layers is not taken while an older entry
exists. That covers this pass's layers and the previous pass's layers that
this pass has not reached again. Hotness alone evicts an expert loaded for
the current token, which has one selection, before one that was hot a while
ago, and a layer often routes the same expert again one token later.

The victim is found through a per-layer minimum (change `192`): each layer
keeps its least (rank, last use, expert) among the entries that can be taken,
recomputed only when the layer changed (a load, a hit, an eviction, an
in-flight mark, a hotness change), at a new pass, or when the row call moves
past it. A search visits layers by their minimum and scans only those that
can still hold a victim. The victims are exactly those of a scan of every
entry, which `DS4_METAL_STREAM_EXPERT_VICTIM_SCAN=1` restores and `=2` checks
against the index at every search. At 54 GiB the search took 2-3% of decode
before (one scan of every entry per layer call that misses) and a third of
that after: decode +1.9% on MTP code, +0.4% on MTP prose, +2.0% plain at 54 GiB.

At emulated 48 GB, against the hotness order alone (each run started with
the pack's pages dropped from the page cache, tokens identical, bootstrap
95% CI of the median pair ratio; change `188`):

| Pack | Misses per decode token, of 480 (prose / code) | Plain decode | MTP decode, code / prose |
|---|---|---|---|
| Q2 | 120 -> 99 / 267 -> 226 | 30.4 -> 30.9 t/s, +1.6% [+1.4%, +2.0%] | -0.1% [-0.5%, +0.2%] / -0.1% [-0.3%, +0.3%] |
| Q4 | 234 -> 181 / 349 -> 291 | 18.8 -> 19.5 t/s, +3.5% [+2.6%, +4.2%] | -0.2% [-1.3%, +0.8%] / +1.8% [+1.6%, +2.4%] |

Prefill is unchanged (every prefill metric's interval includes zero). The
gain is small beside the misses saved because a missed expert usually comes
back from the page cache, not from the SSD (see below).

The window is one pass and no more, on purpose. A longer one saves more
misses where the cache is large, but it fills the cache with recent experts
and evicts the hot ones, and a prefill that resumes after decode computes
its cached experts while the rest load: with a window of eight tokens the
next 512-token prefill lost 3.2% on Q2, with two tokens 1.3% on Q4. A
prefill chunk itself evicts by hotness alone.

Cache size against rate, with this order, on Q2 at emulated 48 GB (same
protocol, 2200 slots against fewer with `--ssd-streaming-cache-experts`,
4 pairs each):

| Cache slots | Plain decode | Prefill 8192 / +512 / +2048 |
|---|---|---|
| 1650 (3/4) | -1.9% [-3.5%, -1.6%] | +0.3% / -0.2% / +3.1% |
| 1100 (1/2) | -3.1% [-4.4%, -1.3%] | +2.8% / +1.8% / +4.6% |
| 550 (1/4) | 30.7 -> 28.2 t/s, -8.5% [-9.2%, -7.3%] | +1.5% / +3.4% / +9.4% |

Decode loses little down to half the cache and then falls; a prefill that
resumes after decode gets faster as the cache shrinks. The prefill figures
are medians of 4 pairs, without intervals.

## Capped RAM: the development condition

Streaming serves two uses: a smaller Mac, and this one with the model held to
a fixed share of its RAM (Q4 at a footprint of 48 to 60 GiB, the request's KV
included) while other work holds the rest. Streaming work is developed for
the second, with the rest of the RAM taken, so that an expert the cache does
not hold is read from the SSD:

- no memory lock;
- the expert cache fixed with `--ssd-streaming-cache-experts`, from the
  footprint;
- `DS4_METAL_STREAM_EXPERT_UNCACHED_READS=1`, which reads routed experts
  through a second descriptor with `F_NOCACHE`, whole pages into a
  page-aligned buffer (on APFS an unaligned `F_NOCACHE` read still leaves
  pages cached). The default stays buffered. A run with the switch leaves
  only the static weights of the GGUF in the file cache, but an `F_NOCACHE`
  read is still served from pages that are already there: a series starts
  from an evicted GGUF, which `ab_bench.py` does when `--env` sets the switch;
- `ab_bench.py --kinds capped-mtp-code,capped-mtp-prose,capped-plain`: an
  8192-token context and 512 generated tokens, so the cache is past its
  warm-up. Decode is the headline metric.

The same runs with buffered reads, the GGUF's pages evicted before each run,
give the RAM-free figures. They are reported and decide nothing.

Footprint is the engine's planned total at the service's configuration
(`--ctx 262144 --mtp`, the 0.57 GiB vision projector added): 26.33 GiB before
the cache on Q4, of which the KV and graph buffers of the 262144-token
context are 20.01. The process holds about 3 GiB less than the plan, and
the same at every context length: its footprint (`footprint -p`) is 43.8
GiB at 2048 tokens and 44.0 GiB from 16K to 254K, plus the 6.3 GiB of locked
static weights, which macOS counts as clean mapped file rather than
footprint. The KV and graph buffers are touched in full when they are
allocated, so a short context leaves nothing to lend the cache; about 3.8
GiB of the 20.01 GiB graph reserve is never touched at all (change `196`).
Until change `193` the plan also reserved 2.59 GiB of
staging, and the table below was measured at those smaller caches.

| Footprint | Cache slots | Expert cache | Share of Q4's routed experts | Slots before `193` |
|---|---|---|---|---|
| 48 GiB | 8,350 | 21.1 GiB | 34% | 7,326 |
| 54 GiB (development) | 10,725 | 27.1 GiB | 44% | 9,701 |
| 60 GiB | 13,100 | 33.1 GiB | 53% | 12,076 |

Q4, at the slots before `193`, 3 runs per cell, medians (the runs of a cell agree within 1% with the
RAM taken). Misses and miss layers (layer calls that miss at least one
expert) per generated token come from one counted run per cell; all-cached
is the share of layer calls over the second half of the run that found every
expert cached (change `190`):

| Footprint | Kind | Decode, RAM taken | Decode, RAM free | Prefill 8192, taken / free | Misses / token | Miss layers / token | All-cached calls |
|---|---|---|---|---|---|---|---|
| 48 GiB | mtp-code | 24.5 | 44.4 | 798 / 804 | 80.6 | 21.01 | 22.5% |
| 48 GiB | mtp-prose | 31.5 | 41.8 | 841 / 846 | 29.0 | 16.13 | 53.3% |
| 48 GiB | plain | 19.7 | 31.6 | 807 / 811 | 72.2 | 30.67 | 41.5% |
| 54 GiB | mtp-code | 29.8 | 48.0 | 781 / 785 | 54.2 | 18.05 | 35.1% |
| 54 GiB | mtp-prose | 36.2 | 42.7 | 822 / 813 | 14.7 | 9.60 | 74.2% |
| 54 GiB | plain | 22.9 | 33.0 | 788 / 788 | 47.0 | 24.31 | 54.1% |
| 60 GiB | mtp-code | 36.0 | 49.8 | 764 / 764 | 32.6 | 13.97 | 52.9% |
| 60 GiB | mtp-prose | 39.3 | 43.6 | 803 / 802 | 8.5 | 5.99 | 84.3% |
| 60 GiB | plain | 26.4 | 34.3 | 773 / 776 | 28.0 | 17.29 | 68.9% |

The first prefill reads every expert once in both conditions, since both
start evicted, and slows a little as the cache grows (locking the cache's
slabs). Resident on this Mac is about 47-49 t/s plain and 65 (code) and 50
(prose) with MTP.

What the table says:

- **The footprint is worth about 1 t/s of decode per GiB** on code with the
  RAM taken (MTP 24.5 -> 29.8 -> 36.0 t/s, plain 19.7 -> 22.9 -> 26.4), with
  no knee in the range. MTP prose flattens above 54 GiB.
- **Code misses three to four times as often as prose** at the same cache.
- **With the RAM free the file cache does the work of the cache**: MTP code
  runs at 44-50 t/s at every footprint.
- **A cache that misses little still stops at every layer**: at 60 GiB MTP
  prose finds every expert cached in 84% of the layer calls and runs at 39.3
  t/s against 50 resident.

Resolution: an A/A at 54 GiB (one 600 s invocation per kind, 4 to 6 pairs)
gives decode -0.45% [-3.19%, +0.17%] on MTP code and +0.15% [-3.92%, +4.39%]
plain (bootstrap 95% CI of the median pair ratio). A single pair can move
4%; a change is judged on at least 8 pairs, two invocations per kind.

### A neighbour

The uncached switch models a neighbour; a real one shows why it is needed.
Beside a process holding 60 GiB of anonymous memory that it touches once a
second (Q4 at 54 GiB, change `195`):

- **Buffered reads compress the neighbour.** They fill the file cache, and
  the kernel makes room by compressing the neighbour, whose pages are older:
  in one run the compressor grew from 4 to 47 GiB within seconds of the
  first prefill and the memory guard stopped it. With the first prefill
  uncached and decode buffered, the first seconds of decode did the same.
- **Uncached reads leave it alone.** Nothing of the neighbour was compressed
  in nine runs, and decode and prefill ran at the RAM-free uncached rates:
  MTP code 34.1 t/s, plain 26.3, prefill 8192 768-775, cold 32K 1185.
- **The pressure signal comes too late to choose the mode.** The system's
  level stayed normal through every uncached run and rose to warning only
  after the compressor had already taken 10 GiB of the neighbour. Splitting
  by class instead (prefill uncached, decode buffered) costs 18-20% of
  decode with the RAM free (MTP code 48.7 -> 40.0 t/s, plain 35.8 -> 28.8).

So the read mode is chosen at launch: on a machine whose RAM other work
holds, run with `DS4_METAL_STREAM_EXPERT_UNCACHED_READS=1`; with RAM to
spare, the buffered default decodes 36-42% faster.

### Appends on a long context

An agent's request is an append: a tool result or a turn of a few hundred
to a few thousand tokens on top of a long context, then a short answer.
Time to first token of appends in sequence on one session, Q4, prose, MTP
off, 16 tokens decoded after each, 3 runs per cell, medians, ms (change
`198`; streamed runs capped and uncached):

| Context | Cell | First prefill | +64 | +256 | +1024 | +4096 |
|---|---|---|---|---|---|---|
| 8K | resident | 6675 | 201 | 360 | 934 | 3287 |
| 8K | 48 GiB | 9869 | 515 | 968 | 1979 | 4802 |
| 8K | 54 GiB | 10123 | 558 | 709 | 1597 | 4434 |
| 8K | 60 GiB | 10246 | 351 | 511 | 1275 | 3869 |
| 32K | resident | 20910 | 210 | 352 | 890 | 3040 |
| 32K | 48 GiB | 29302 | 530 | 858 | 2116 | 4426 |
| 32K | 54 GiB | 28185 | 443 | 637 | 1678 | 3941 |
| 32K | 60 GiB | 26990 | 394 | 489 | 1293 | 3501 |

At 54 GiB an append takes 2.1-2.8 times the resident time at 64 tokens,
1.8-2.0 at 256, 1.7-1.9 at 1024 and 1.3 at 4096.

Where the time goes, one run per cell at 54 GiB against resident: the
append's wall time, the GPU's busy time over it (command buffer spans),
and the sum of the per-layer expert read walls (stream timing summary).
Every append is one chunk; each of its 48 layers loads its missing experts
once, with the GPU idle unless a gate/up pass already runs:

| Context | Append | Wall, resident / streamed | GPU busy, resident / streamed | Streamed GPU idle | Reads |
|---|---|---|---|---|---|
| 8K | +64 | 165 / 437 | 156 / 241 | 196 | 105 |
| 8K | +256 | 324 / 673 | 298 / 320 | 353 | 402 |
| 8K | +1024 | 818 / 1585 | 720 / 743 | 843 | 886 |
| 8K | +4096 | 2803 / 4315 | 2415 / 2453 | 1862 | 2068 |
| 32K | +64 | 189 / 435 | 170 / 237 | 198 | 122 |
| 32K | +256 | 365 / 612 | 336 / 318 | 293 | 345 |
| 32K | +1024 | 910 / 1658 | 807 / 761 | 897 | 950 |
| 32K | +4096 | 3123 / 3957 | 2716 / 2520 | 1437 | 1633 |

- **From 256 tokens up the gap is the read wait**: the GPU does the same
  work as resident and sits idle for 40-55% of the append, about as long as
  the reads take (the reads can exceed the idle time where the down read
  overlaps the gate/up pass).
- **The next layer's misses cannot be read early by elimination.** A chunk
  routes far fewer of a layer's 512 experts than its rows suggest, and the
  cache holds most of those: per layer, an append routes about 112 experts
  at 64 tokens (misses 10), 190 at 256 (32-38), 260-300 at 1024 (87-93) and
  375 at 4096 (160-205), while 290-340 experts of the next layer are
  uncached. Reading all of those while this layer computes wastes more
  read time than it hides up to 1024 tokens and saves about 3% at 4096.
  A perfect prediction of the next layer's misses would hide 26-37% of an
  append, since a layer's GPU time (5 ms at 64 tokens, 36-38 ms at 4096)
  covers most of the next layer's reads (change `202`).
- **At 64 tokens the reads are a quarter of the append.** The extra GPU
  time was the expert pass: below 65 rows a streamed call ran the
  per-token expert kernels, which read an expert once for every row that
  chose it, while the resident path runs the grouped ones, which read it
  once per four such rows (67-70 ms more GPU per 64-token append). Streamed
  calls of 9 to 64 rows without a shared slot now take the grouped kernels
  through the cache's address table, bit for bit the same rows (change
  `203`): at 54 GiB a 64-token append takes 436 -> 364 ms on 8K and 493 ->
  406 ms on 32K (-16.5%, -17.7%; 3 runs), at 48 GiB 11-13% less and at 60
  GiB 18% less. Appends of 128 rows and more run the tiled path, which this
  does not change; their single runs spread by up to 15% with one binary
  (the GPU time of a read-bound chunk varies from run to run), so judge
  them on many runs. The per-layer stop's CPU work besides the drain and
  the reads is 0.13-0.15 ms per layer at 64 tokens and 0.33-0.39 ms at 256.

### The layer round trip

A resident decode pass never stops the GPU; a streamed one stops it at every
layer to read the router's ids. Measured per layer call on Q4 at 54 GiB,
uncached, medians (change `191`):

| Part of the stop | All experts cached | Some missing |
|---|---|---|
| wake: the CPU returns from `waitUntilCompleted` after the GPU ends | 66-68 us | 67-70 us |
| ids read, cache lookup, loads | 12-13 us | 665-762 us |
| encoding the expert pass | 8-9 us | 8 us |
| encoding the rest of the layer and the next router | 12 us | 12-13 us |
| commit of that batch to its GPU start | 92-94 us | 90-93 us |

A layer that finds every expert cached still leaves the GPU idle about 190
us. Over decode the wake is 6% (MTP code) to 8% (plain), the commit start 8%
to 10%.

What shortens it is committing the expert pass as soon as it is encoded
(change `189`, from upstream #1328). The next batch, the rest of the layer
and the next router, is then committed while the expert pass runs, so its
commit-to-start time is spent with the GPU busy instead of idle. `191` had
dropped the same step on a projection that counted only the 12 us of
encoding it hides; measured, it gains (below). On Q2 a single-row decode
layer goes further: it is encoded before its experts are known and parks on
a shared event that the CPU signals once the missing experts are loaded
(the handshake; Q4's Q4_K gate/up rows take grouped tables and skip it).
Capped, RAM taken, against the code before, bootstrap 95% CI of the median
pair ratio:

| Pack, cache | Kind | Decode |
|---|---|---|
| Q4, 54 GiB | mtp-code | 32.75 -> 34.06 t/s, +4.0% [+3.6%, +5.2%] |
| Q4, 54 GiB | mtp-prose | 38.16 -> 40.18, +5.1% [+3.9%, +5.6%] |
| Q4, 54 GiB | plain | 24.59 -> 25.79, +4.9% [+0.7%, +5.7%] |
| Q4, 48 GiB | mtp-code | 26.95 -> 27.84, +3.2% [+2.6%, +3.7%] |
| Q4, 60 GiB | mtp-code | 39.20 -> 40.17, +2.4% [-3.7%, +5.6%] |
| Q4, 10% (2,458 slots) | mtp-code / plain | +0.1% [-1.2%, +1.3%] / +3.1% [+2.9%, +3.2%] |
| Q2, 54 GiB (18,563 slots) | plain / mtp-code | +5.6% [+4.7%, +6.9%] / +4.7% [-1.4%, +10.0%] |

Prefill does not change (every interval includes zero). At 10% of the
experts misses dominate and MTP code gains nothing.

Polling the command buffer's status instead of blocking (`191`) cut the
wake but ran the GPU at 720 MHz and 7 W instead of 1590 MHz and 27 W: MTP
code decode fell from 29.9 to 25.4 t/s. While the CPU blocks on the GPU, the
GPU stays at its high clock; while it spins, it does not. Any wait for the
GPU on this path must block.

### A 48 GB Mac

A 48 GB Mac is bracketed, not emulated. Assumed: a budget of 36 GiB (Metal's
recommendation on this Mac is 84% of RAM, 40 GiB at 48 GB, less what the
system and other apps hold), an 8192-token context with MTP, no projector.
The plan then gives the cache 17.0 GiB on Q4 (6,727 slots, 27% of the routed
experts) and 18.2 GiB on Q2 (13,086, 53%). The hard end runs that cache with
uncached reads and no lock: no file cache at all. The other end is the old
emulation (`--simulate-used-memory 80GB`): the plan's own 2-3 GiB cache and
about 25 GiB of file cache. One run per cell, 512 generated tokens, decode and
first prefill in t/s:

| Pack | Kind | Hard end: plan's cache, uncached | Emulated: lock, small cache, file cache |
|---|---|---|---|
| Q4 | mtp-code | 23.4 / 803 | 16.6 / 845 (809 slots) |
| Q4 | mtp-prose | 29.8 / 851 | 21.7 / 879 |
| Q4 | plain | 19.1 / 815 | 16.4 / 768 |
| Q2 | mtp-code | 44.0 / 1004 | 34.3 / 1052 (2,369 slots) |
| Q2 | mtp-prose | 38.2 / 1030 | 33.7 / 1093 |
| Q2 | plain | 30.2 / 1014 | 24.9 / 1071 |

The emulation is not the generous end for decode: its cache is too small for
the file cache to make up, and it runs 14-29% slower than a real-sized cache
reading every miss from the SSD. A 48 GB Mac with this SSD should decode at
least at the hard end, a little faster with whatever file cache it keeps; on
prefill the two ends are within 8%. Older emulated figures understate decode
on such a machine.

## Emulated 48 GB (earlier changes)

The figures below and those of `185` and `188` above were taken with
`--simulate-used-memory`, which models neither use. For an emulated size X
the lock takes most of the host's user wire limit (108.8 GiB) and the plan
stays inside what is left: about 0.84 x (X - 24) GiB, 19.5 GiB at 48 GB,
where a 48 GB Mac would plan about 36 to 40. The expert cache then holds 4%
(Q4) to 10% (Q2) of the routed experts, and the RAM the plan leaves, about
25 GiB, becomes file cache holding the experts the small cache evicts. Those
figures measured that file cache, not a small machine.

`sf-q3-8flash-bench --simulate-used-memory <GiB>` locks that much RAM before
the model loads. The plan then uses the RAM left, Metal's
recommendation scaled by the same fraction, and what the kernel still lets the
process wire. The emulation keeps this machine's SSD, so a real smaller Mac
with a slower disk reads slower. 40 GB is the smallest size this host can
emulate: the kernel's user wire limit is 108.8 GiB, and a 96 GiB lock leaves
too little of it. A resident run refuses the lock, because nothing in it can
adapt.

Throughput in tokens/s of the streamed run. Prefill is measured at 8192,
+512 and +2048 tokens on an 8192-token context (plain), and at 2048 tokens
with MTP. The resident rates on this machine are about 47-49 t/s plain decode,
65 (code) and 50 (prose) with MTP, and 1100-1150 t/s prefill at 8192.

| Pack | Emulated RAM | Expert cache, plain / MTP | Plain decode | Prefill 8192 / +512 / +2048 | MTP decode code / prose | MTP prefill code / prose |
|---|---|---|---|---|---|---|
| Q4 | 48 GB | 2.3 / 18.6 GiB | 17.4 | 903 / 241 / 449 | 23.8 / 26.3 | 339 / 447 |
| Q4 | 40 GB | refused / 1.5 GiB | - | - | 18.2 / 19.7 | 379 / 505 |
| Q2 | 48 GB | 3.5 / 12.5 GiB | 26.9 | 1090 / 409 / 686 | 34.7 / 35.7 | 596 / 649 |
| Q2 | 40 GB | - / 2.6 GiB | - | - | 27.3 / 29.1 | 593 / 714 |

The cache size also depends on what else the machine holds at open, since the
emulated plan counts the memory that is really available after the lock.

The cache size depends on the context: the plain runs' 10.8K context plans a
larger graph reserve than the MTP runs' 2K context. At 40 GB the plain kind is
refused (19.10 GiB fixed against 14.76), which is the admission working as
designed.

Expert reads are buffered by default. At these sizes the plan does not take
all the RAM that is left: at 48 GB it plans 19.4 GiB and the Q2 process holds
about 10.6. The kernel fills the rest with the pack's pages, about 25 GiB
after one prefill, and an expert evicted from the cache is read back from
there, not from the SSD. With `F_NOCACHE` on the expert reads, plain decode
fell from 30.2 to 20.3 t/s on Q2 and from 18.9 to 11.2 on Q4, and resumed
prefill by 8-31% (each run started with the pack's pages dropped from the
page cache; change `185`).

Minimum RAM follows from the fixed part of the plan: 6.32 GiB static weights,
the graph for the context, 1.4 (Q2) or 2.6 GiB (Q4) of staging while the
cache is smaller than a layer, and 2 GiB of runtime headroom. At a 2K context this is about 12-13 GiB, so a 24 GB Mac,
whose Metal recommendation is about 16 GiB, has room for a small cache. This
is derived from the plan, not measured on such a machine.

## Keep

Do not remove `ds4_ssd.*` or the generic stream expert cache in `ds4_metal.m`:
Qwen streaming is built on them, and the functions it calls are marked
`sf-keep` at their definitions.
