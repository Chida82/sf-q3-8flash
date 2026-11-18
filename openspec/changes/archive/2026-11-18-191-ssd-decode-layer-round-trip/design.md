# Design

## Context

One streamed layer call on the row path (decode: one row; MTP verification:
two or three), as `main` runs it:

1. the batch that holds the layer's attention and router is committed and
   waited (`ds4_gpu_synchronize` -> `ds4_gpu_end_commands` ->
   `waitUntilCompleted`);
2. the ids are read (`ds4_gpu_tensor_read`) and counted;
3. `ds4_gpu_stream_expert_cache_prepare_selected_batch` looks them up,
   picks victims and reads the missing experts; on a layer that misses,
   `qwen4_stream_mid_before_read` launches the cached experts' gate/up
   first;
4. a new batch is begun and the expert pass encoded into it
   (`ds4_gpu_qwen4_moe_mid_tensor`, `ds4_gpu_qwen4_moe_down_tensor`);
5. the caller goes on encoding into the same batch, up to the next layer's
   step 1.

The expert cache tracks which entries a committed batch may still read
(`ds4_gpu_stream_expert_cache_note_batch_committed`, `..._owned_completed`),
so an entry is not evicted under a running kernel.

## Decisions

### D1. S0, the probe

A scratch build prints, per row-path call: the router batch's GPU end, the
time the CPU returns from the wait, the time the next batch is committed and
that batch's GPU start, with the call's miss count from `190`'s counter.
From them, per all-cached call and per call that misses:

- wake = CPU return - router GPU end;
- CPU turn = next commit - CPU return, split into lookup and encoding;
- start = next batch GPU start - its commit.

Run in `190`'s capped condition at the development footprint, Q4,
`capped-mtp-code` and `capped-plain`. Projection: S1 removes the encoding
part of the CPU turn that follows the expert pass, S2 the wake above a few
microseconds, S3 the lag of the completion report. **Close the change** if
the three together project to under 2% of decode.

### D2. The steps

- **S1.** One `ds4_gpu_flush_commands` after step 4 for row-path calls. The
  flush already moves the batch to the pending list and tells the cache; the
  check is that the entries the pass reads stay protected until that batch
  completes, which the next drain waits for. One more command buffer per
  layer call: S0's "start" figure says what a commit to an idle GPU costs,
  and S1 is dropped if that exceeds the encoding it hides.
- **S2.** In the drain used by row-path calls, poll `cb.status` for a
  bounded time, then fall back to `waitUntilCompleted`. The bound is a
  constant chosen from S0's GPU-span distribution, not a tuning surface.
  Errors and the pending-buffer wait keep their paths.
- **S3.** The router batch ends with a one-thread kernel that copies the ids
  and a sequence word into a shared buffer; the CPU polls it and falls back
  to S2's poll. Built only if S0 shows the lag, and after S2.

Not taken: work ahead of the ids (sf-ds4-1flash `132`'s shared expert).
Qwen's shared expert is computed inside the routed kernels
(`ds4_gpu_qwen4_moe_mid_tensor` takes the shared offsets), and splitting it
out changes the order of a sum. Reopened only with a bitwise proof.

### D3. Measurement and keep rule

`190`'s bench: capped, RAM taken, Q4, the three `capped-*` kinds, A B B A,
at least 8 pairs. Each step against the previous kept state at the
development footprint; the final state against `main` at 48, 54 and 60 GiB,
and once with the RAM free.

- Target: decode of `capped-mtp-code` and `capped-mtp-prose`, pooled. A step
  is kept when the pooled CI lies above zero.
- Guards: no metric's CI wholly below zero at any footprint, plain decode
  and the prefill rates included; resident decode unchanged (the resident
  path does not run this code, checked `--bitwise`).
- Tokens identical on every pair; streamed equals resident on Q4 and Q2.

### D4. Relation to `189`

The handshake commits the expert pass before the ids are known and parks it
on a shared event the CPU releases. sf-ds4-1flash measured such a release at
about 100 us, the same as a commit to an idle GPU. S0 measures the same
figure here. If S1 and S2 are kept, `189` is measured against that state, not
against today's `main`.

## Risks / Trade-offs

- **A poll burns a core for its bound.** The decode thread already waits
  there; the bound keeps a stuck GPU from spinning it. sf-ds4-1flash found a
  second spinning thread costs GPU power (`220`), so nothing here adds one.
- **More command buffers per pass** (S1): 48 more commits. Measured by S0
  before it is built.
- **The cache's in-flight accounting** is the one correctness surface. The
  eviction tests of `tests/test_qwen4_ssd_experts.c` run with each step's
  switch on and off, and a forced-eviction case (a cache smaller than one
  pass's experts) is added if none exists.
