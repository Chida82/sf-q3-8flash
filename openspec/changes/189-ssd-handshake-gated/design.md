# Design

## Context

The port of #1328 is commit `dd8db0d` on the local branch
`perf/170-ssd-decode-handshake`, and its correctness was established
there: the handshake unit cases pass (failed read, invalid id, cancel and
retry), streamed output equals resident on Q2 and Q4, the resident path is
bitwise unchanged, and the peak footprint equals `main`'s. The handshake runs
through `qwen4_stream_handshake_layer` (called from
`ds4_gpu_qwen4_moe_stream_tensor`) and is on unless
`DS4_METAL_DISABLE_STREAMING_EXPERT_EARLY_LOAD` is set. On Q4 only the early
commit applies (the handshake skips Q4_K gate/up rows); on Q2 both parts do.

## Decisions

### D1. Bring the port onto current `main`

Merge `main` into a new branch cut from `dd8db0d`, resolving against `188`'s
eviction order (the port's up-front slabs and `188`'s pass stamp touch the
same cache). Every check `170` passed is run again on the result before any
measurement: the unit test on Metal, streamed equals resident on Q2 and Q4
(plain and MTP), resident bitwise against `main`.

### D2. The measurement protocol

- Emulated 48 GB (`--simulate-used-memory` with the 80 GiB lock), the
  streamed side only, as before.
- **The expert cache is fixed** with `--ssd-streaming-cache-experts <slots>`,
  the same number on both sides, so the plan's dependence on free memory at
  launch drops out (sf-ds4-1flash measures the same way at a fixed cache).
- Sizes: on Q4, the plan's own slot count at 48 GB for the plain context
  (about 780) and for the MTP context, plus one larger size; on Q2 the same
  three positions. Each size runs the plain and both MTP kinds.
- **Steady state is the main condition**: the page cache is left as the
  previous run leaves it, which is the state of a server that has been
  running. One cold check per pack (the GGUF's pages evicted before every run
  of both sides, the protocol `185` established) shows the first-request
  case.
- At least 8 pairs per kind and size before a rule is applied. Runs that
  overlapped a foreign load (a container, an XProtect scan) never ground a
  drop or a neutral result.
- Q4 first. Q2 follows only if Q4 shows a gain somewhere in the table or the
  clock allows both.

### D3. Keep rule

For the gated build of S1, against `main`, at every measured size:
- MTP decode (mtp-code and mtp-prose pooled per pack) is the target: kept
  when its pooled CI lies above zero on at least one pack;
- plain decode must not lose: no pooled CI wholly below zero, at any size;
- no other metric's CI wholly below zero.

If the table shows the handshake wins only at cache sizes the plan never
reaches at 48 GB, the change closes as "measured, not needed" with the table.

### D4. The gate

Candidates, chosen by the table, simplest first:
1. by kind: the handshake runs only for MTP verify calls (more than one row);
2. by coverage: it runs only when at least a threshold share of the layer's
   selected experts is already cached (the threshold read off the table);
3. both.
The gate is one predicate at the handshake's entry; the ordinary path is
untouched. `DS4_METAL_DISABLE_STREAMING_EXPERT_EARLY_LOAD` stays as the kill
switch only if the measurement shows the gain depends on the machine.

### D5. What is reused from sf-ds4-1flash

Read on 2026-11-18: its `760` lock of the static weights is already in this
child (Qwen's static spans are locked under streaming, `ds4.c:33121`); its
`268` alignment fix applies only to `F_NOCACHE` readers, which here is the
n-gram table alone, outside this change. What this change takes is the
measurement discipline: a fixed expert cache and a steady-state main
condition.

## Risks / Trade-offs

- **A gate by coverage needs the selected ids on the CPU before the decision.**
  The streamed path reads them back already; the gate must not add a second
  read-back.
- **The rebase over `188`** may change both changes' figures: `188` lowered
  misses, which helps the ordinary path's overlap and may shrink the space
  where the handshake wins. Step 0 measures on top of it, so the table is the
  current truth.
- **Emulation keeps this Mac's SSD.** A real 48 GB Mac reads slower; the doc
  says so beside the figures.
