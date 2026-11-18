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

The bench of `190-ssd-capped-ram-bench` (its design D1 and D5), which
replaces the emulated 48 GB this change was first written for: under the
80 GiB lock the plan gives the cache 4-10% of the experts and leaves 25 GiB
of file cache, a condition that models neither of the owner's uses.

- Capped, RAM taken: no memory lock, the expert cache fixed with
  `--ssd-streaming-cache-experts` (the same slot count on both sides),
  uncached expert reads on both sides.
- Q4, at the development footprint (54 GiB) first; then 48 and 60 GiB. The
  kinds are `capped-mtp-code`, `capped-mtp-prose` and `capped-plain`.
- One smaller cache as well, 10% of the experts, where `170` saw the
  handshake lose on plain decode: it says whether the gate of D4 needs the
  cache-coverage term.
- At least 8 pairs per kind and size before a rule is applied. Runs that
  overlapped a foreign load never ground a drop or a neutral result.
- The baseline is `main` after `191-ssd-decode-layer-round-trip` has
  finished or closed (its design D4): both changes shorten the same GPU idle.
- The RAM-free condition is reported beside the result and decides nothing.

### D3. Keep rule

For the gated build of S1, against `main`, at every measured size:
- MTP decode (mtp-code and mtp-prose pooled per pack) is the target: kept
  when its pooled CI lies above zero on at least one pack;
- plain decode must not lose: no pooled CI wholly below zero, at any size;
- no other metric's CI wholly below zero.

If the table shows the handshake wins only at cache sizes outside the
48-60 GiB footprints, the change closes as "measured, not needed" with the
table.

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

The full reading is `190-ssd-capped-ram-bench` design D9. Two of its rows
bear on this change. That child measures at a fixed expert cache, which D2
takes. And it measured twice (`132` D3, `680`) that an expert pass committed
ahead and released by a CPU-signalled event restarts the GPU no faster than
a commit, about 100 us: the handshake is such a pass, so its gain can only
come from the drain and the encoding it removes, which `191` S0 measures.

## Risks / Trade-offs

- **A gate by coverage needs the selected ids on the CPU before the decision.**
  The streamed path reads them back already; the gate must not add a second
  read-back.
- **The rebase over `188`** may change both changes' figures: `188` lowered
  misses, which helps the ordinary path's overlap and may shrink the space
  where the handshake wins. Step 0 measures on top of it, so the table is the
  current truth.
- **The capped bench reads every miss from this Mac's SSD.** That is the
  hard end of the owner's condition (`190` design D3); the RAM-free run shows
  the other end.
