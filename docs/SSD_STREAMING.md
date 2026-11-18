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
- the staging windows: two full trunk layers, or two compact predictor
  payloads with MTP;
- another 2 GiB for the runtime.

What is left becomes the expert cache, capped at every routed expert. If the
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

## Measured figures

M5 Max 128 GiB. The smaller machines are emulated with
`sf-q3-8flash-bench --simulate-used-memory <GiB>`, which locks that much RAM
before the model loads. The plan then uses the RAM left, Metal's
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

Expert reads are buffered on purpose. At these sizes the plan does not take
all the RAM that is left: at 48 GB it plans 19.4 GiB and the Q2 process holds
about 10.6. The kernel fills the rest with the pack's pages, about 25 GiB
after one prefill, and an expert evicted from the cache is read back from
there, not from the SSD. With `F_NOCACHE` on the expert reads, plain decode
fell from 30.2 to 20.3 t/s on Q2 and from 18.9 to 11.2 on Q4, and resumed
prefill by 8-31% (each run started with the pack's pages dropped from the
page cache; change `185`).

Minimum RAM follows from the fixed part of the plan: 6.32 GiB static weights,
the graph for the context, 1.4 (Q2) or 2.6 GiB (Q4) of staging, and 2 GiB of
runtime headroom. At a 2K context this is about 12-13 GiB, so a 24 GB Mac,
whose Metal recommendation is about 16 GiB, has room for a small cache. This
is derived from the plan, not measured on such a machine.

## Keep

Do not remove `ds4_ssd.*` or the generic stream expert cache in `ds4_metal.m`:
Qwen streaming is built on them, and the functions it calls are marked
`sf-keep` at their definitions.
