# Proposal

## Why

A resident decode pass never stops the GPU. A streamed one stops it at every
trunk layer, 48 times a pass: `ds4_gpu_qwen4_moe_stream_tensor` drains the
GPU (`ds4_gpu_synchronize`, a commit and a blocking `waitUntilCompleted`),
reads the router's ids, looks them up in the expert cache, loads what is
missing, and only then encodes the expert pass. From reading, nothing is
committed again until the next layer's drain, except the flush before a PLE
layer and the launch of the cached experts on a layer that misses: on a
layer whose experts are all cached, the GPU waits while the CPU wakes up and
encodes the expert pass, the rest of the layer, the next layer's attention
and its router.

This cost is paid on every layer call, whatever the cache holds, so it sets
the ceiling of streamed decode. `190`'s step 0 measured it on Q4 with the
cache at 70% of the routed experts:

| Kind | Layer calls with every expert cached | Streamed decode | Resident |
|---|---|---|---|
| plain, prose | 97.7% | 35.9 t/s | 47-49 t/s |
| MTP, prose | 95.4% | 42.8 t/s | about 50 t/s |

With almost nothing left to load, a plain pass still takes about 7 ms more
than a resident one, about 150 us per layer call, and an MTP pass about 5 ms
more. The figures are indicative (one run, a VM running, the resident rates
taken at other contexts); S0 measures the idle itself.

sf-ds4-1flash had the same shape, a stop at each of 40 layers to read six
expert ids, and took it apart in measured steps on this Mac
(`speed-bench/perf-record.md` there):

| Step there | What it changed | Decode |
|---|---|---|
| `30` | layers committed without a wait, so the GPU runs layer L while the CPU encodes L+1 | 17.5 -> 20.1 t/s |
| `131` | a bounded poll for the router's completion instead of the blocking wait (76 us of wake per layer) | 20.4 -> 22.3 t/s |
| `132` | work that does not need the ids (the shared expert) committed before the wait | 22.3 -> 22.6 t/s |
| `210` | the ids copied into a shared buffer the CPU polls, seen 25-30 us before the buffer reports completed | +5.5% at a 2048 context |

It also measured what does not help: an expert pass committed ahead and
released by a CPU-signalled event restarts the GPU no faster than a commit
(about 100 us, `132` D3 and `680`), and GPU or CPU keep-alives during decode
lose (`220`).

None of this is in this child. The idea is taken, not the code: the Qwen
graph, its kernels and its MTP verification rows are different.

Performance under the intake criteria, on the streaming path, and at every
cache size: it does not depend on how many experts miss.

## What Changes

- **S0, a probe, nothing landed.** Per streamed layer call of a decode pass,
  split by all cached or not: the GPU idle between the router's end and the
  expert pass's start, and its parts (CPU wake, cache lookup, encoding,
  commit to GPU start). `DS4_METAL_CB_TIMES` already prints most of it. The
  change closes here if the idle that S1 to S3 can reach projects to less
  than 2% of decode.
- **S1, commit the expert pass without waiting.** After the expert pass of a
  decode or verification call is encoded, flush the batch
  (`ds4_gpu_flush_commands`), so the GPU computes it while the CPU encodes
  the rest of the layer and the next router.
- **S2, a bounded poll at the drain.** The drain of a decode or verification
  call polls the command buffer's status for a bounded time before the
  blocking wait.
- **S3, the ids through a polled shared buffer**, only if S0 shows the
  completion report lagging the GPU's end as it did there.
- Each step has a kill switch for its A/B and is kept or dropped by its own
  measurement in `190`'s bench (design D3). Prefill batches are not touched.

Output must not change: the same kernels run on the same inputs in the same
order; token ids of a streamed run stay identical to the resident run, and
the resident path stays bitwise unchanged.

## Impact

- `ds4_metal.m` (`ds4_gpu_qwen4_moe_stream_tensor`, the drain and the
  in-flight accounting of the expert cache), possibly `metal/qwen4.metal`
  for S3's copy kernel, `tests/test_qwen4_ssd_experts.c`,
  `docs/SSD_STREAMING.md`.
- Starts after `190` (the bench). `189-ssd-handshake-gated` runs after this
  change's S0: the handshake attacks the same idle by parking the expert pass
  on a shared event, and S0's figures say how much is left for it.
