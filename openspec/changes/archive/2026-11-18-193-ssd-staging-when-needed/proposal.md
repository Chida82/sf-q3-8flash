# Proposal

## Why

The streamed memory plan reserves staging windows before it sizes the
expert cache: two full trunk layers, 2.59 GiB on Q4 and 1.4 GiB on Q2
(`qwen4_streaming_staging_bytes`). `--ssd-streaming-cache-experts NGB`
counts them inside N. They are used only when an expert pass cannot go
through the cache (`ds4_gpu_qwen4_moe_stream_tensor` takes the owned-buffer
path, `qwen4_stream_read_selected`, when a call selects more distinct
experts than the cache holds, or when a layer's experts are of another size
class, as the Q2 pack's MTP layer is).

At the footprints the owner targets (`190`: 7,326 to 12,076 slots on Q4) a
call can select at most 512 experts, so a trunk layer never takes that path,
and on Q4 the MTP layer has the trunk's size class (to be confirmed by step
0). The 2.59 GiB are then planned for nothing, at the expense of the cache.

At the same footprint they are about 1,020 more slots on Q4. `190`'s step 0
measured about 0.9 tokens/s of MTP decode on code per GiB of cache in the
48-60 GiB range, so the ceiling is roughly +2 tokens/s at 54 GiB (+7%), from
reading a plan, not from new code on the hot path.

## What Changes

- **Step 0.** On Q4 and Q2, at the three footprints, plain and MTP, count
  the calls that take the owned-buffer path (a counter in the stream timing
  summary, scratch). Confirm zero on Q4.
- **S1.** The plan reserves staging only when it can be needed: when the
  cache could hold fewer slots than one call can select (512), or when a
  streamed layer's expert size differs from the trunk's. The cache gets the
  rest. If the owned path is ever reached without its reserve, it still
  allocates on demand, as today; the plan line says which case applied.
- Re-measure the slot counts for 48, 54 and 60 GiB and update `190`'s table.

Output does not change: the same experts through the same kernels.

## Impact

- `ds4.c` (`qwen4_streaming_staging_bytes`, `qwen4_streaming_memory_admit`),
  `docs/SSD_STREAMING.md` (memory plan), `190`'s footprint table.
- Starts after `190`.
