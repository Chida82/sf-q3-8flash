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

Minimum RAM follows from the fixed part of the plan: 6.32 GiB static weights,
the graph for the context, 1.4 (Q2) or 2.6 GiB (Q4) of staging, and 2 GiB of
runtime headroom. At a 2K context this is about 12-13 GiB, so a 24 GB Mac,
whose Metal recommendation is about 16 GiB, has room for a small cache. This
is derived from the plan, not measured on such a machine.

## Keep

Do not remove `ds4_ssd.*` or the generic stream expert cache in `ds4_metal.m`:
Qwen streaming is built on them, and the functions it calls are marked
`sf-keep` at their definitions.
