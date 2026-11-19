# Proposal

## Why

An agent talks to the server in appends: a tool result or a user turn of a
few hundred to a few thousand tokens on top of a long context, then a short
answer. Under streaming the append is the slow part. At emulated 48 GB the
docs record the first 8192-token prefill at 903 tokens/s on Q4 and the
+512 append after it at 241 (`docs/SSD_STREAMING.md`); in `190`'s step 0
the first prefill ran at 750-890 tokens/s at every cache size. A 512-row
chunk routes most of a layer's 512 experts, so it reads nearly every expert
the cache lacks, layer after layer, while the GPU waits.

sf-ds4-1flash took its largest prefill gains from the same shape (`60`
prefill sweeps, `100` prefill weight delivery: time to first token +26% to
+155%), by reading the next layer's experts while the current layer
computes and by making short appends one sweep (`770`: +300-token append
from 9.6 to 6.2 s). Its model, layer count and buffers differ; the shape of
the problem is the same.

Nothing here measures appends at the owner's footprints yet.

## What Changes

- **Step 0, measurement only.** Q4 at 48, 54 and 60 GiB, capped and RAM
  taken, and resident: time to first token of appends of 64, 256, 1024
  and 4096 tokens on top of 8K and 32K contexts (a session per context, the
  appends in sequence with 16 decoded tokens after each), with the stream
  timing summary: read wait per layer, experts read per chunk, GPU time.
  Output: where an append's time goes, and the gap to resident.
- **Candidates, written as follow-up proposals only where step 0 shows the
  gap**: a one-layer-ahead read pipeline for multi-row calls (the next
  layer's uncached experts read while this layer computes; a multi-row
  chunk selects most of them anyway); the chunk size for appends under
  streaming; the row path for very short appends.

## Impact

- No code in this change: a scratch script, a section in
  `docs/SSD_STREAMING.md` with the table, and the follow-up proposals.
- Starts after `190`.
