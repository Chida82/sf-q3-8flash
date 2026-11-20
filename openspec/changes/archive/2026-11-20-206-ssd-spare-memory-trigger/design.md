# Design

## Decisions

### D1. The estimate

From `host_statistics64(HOST_VM_INFO64)`: spare = free + external
(file-backed) + purgeable + half of the inactive anonymous pages (what the
compressor could still take from other processes, at about 2:1). Reserve =
7% of physical RAM clamped to 2-7 GiB; margin = 1 GiB. Sampled once a second
by a dispatch timer on a utility queue while a streamed engine is open, so
the call path sees only 186's atomic event counter.

### D2. Levels and hysteresis

- spare < reserve + margin: warning (186: three quarters of the plan);
- spare < reserve: critical (186: the floor);
- back to normal only when spare > reserve + 2 x margin; 186's 30 s quiet
  period then regrows one slab at a time.

The cache acts on max(system level, sampler level). A level change is
posted once, through `ds4_gpu_stream_pressure_note`.

### D3. Step 0

Q4 at 54 GiB (10,725 slots), capped, uncached, beside the 60 GiB neighbour
(the `195` setup, under the one-second guard with its 15 GiB compressor
limit); a scratch sampler beside the run logs spare, the would-be level and
`kern.memorystatus_vm_pressure_level` each second. Pass: the would-be level
reaches warning while the system level is normal. Also without the
neighbour: the would-be level must stay normal (no false trigger).

### D4. Keep rule

As `186` 3.3: the no-pressure cost against `main`, capped and uncached, at
54 GiB on the three kinds, no decode CI wholly below zero; injected
transitions exact; and beside the neighbour the cache shrinks before the
compressor grows by 5 GiB.

## Risks / Trade-offs

- A machine that keeps little file cache by design may sit near the
  threshold: the hysteresis band and the quiet period bound the churn.
- The inactive-anonymous share is a guess at compressibility; step 0 checks
  the estimate against the compressor's real growth.
