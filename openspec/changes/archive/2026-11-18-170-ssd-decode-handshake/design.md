# Design

## Context

`80` made SSD streaming token-identical to resident on both packs, and
measured it at 128 GiB and at emulated 48 and 40 GB. #1328 changes when the
CPU learns a decode layer's experts relative to the GPU's work. It does not
change any expert kernel's arithmetic, by its author's account. Its base is
`b3f5018`, the commit `90` syncs to, so the port follows `90` and `120`.

## Decisions

### D1. Port as one unit

The six commits form one change, and the later ones fix the first one's
failure paths. They are ported together and reviewed as one diff. The
early-commit switch is not ported, since `9b7b1da` drops it.
`DS4_QWEN4_STREAM_HANDSHAKE` is kept while measuring. The final pass decides
whether it stays as a diagnostic switch.

### D2. Expert-id validation stays a hard gate

Today an out-of-range expert id fails the streamed call before any read. With
the handshake, the GPU has already been encoded to read through the address
table when the CPU sees the ids. Before porting, read how `e11a04e` and
`2d48e3b` handle an invalid id:
- what the GPU reads in that case (a guard slot, or nothing);
- whether the request fails with the same error.

A unit test injects an invalid id into a handshake layer and checks that no
out-of-range address is written and that the decode call fails. If the
deferred rejection lets the GPU read an unvalidated address, the change stops
here and goes to the owner.

**Settled by reading (task 1.3).** The service checks the ids exactly as the
ordinary path does, before any load, cache change or table write; an invalid
id fails the call with the batch open and no message, as today. The kernels
bound the table lookup by `n_total_expert` (`qwen4_expert_rows`), so the
invalid slot reads nothing; the IQ2/Q4_K mid kernels zero its row. One
difference: the valid slots' mid/down scratch is written before the failure
is known, where the ordinary path leaves it untouched; the request fails on
the 0 either way. No unvalidated address is read, so D2 does not stop the
change. Details and line references: `$SCR/c170/notes.txt`.

### D3. Memory: the up-front slabs inside `80`'s admission

`80` admits a streaming run against min(87.5% of RAM, Metal's
recommendation), with the cache budget counted. The handshake allocates the
whole cache budget's slabs on first use instead of on demand. Check that:
- the allocated bytes equal the admitted cache budget, not more;
- first-use allocation happens after admission, so a run that admission
  would refuse is still refused;
- at emulated 48 GB, the run's peak footprint stays within the budget.

**Settled by reading (task 1.3), except the footprint.** The handshake
allocates up to `ds4_gpu_stream_expert_cache_configured_budget()`, the count
admission passes to `ds4_gpu_set_streaming_expert_cache_budget`, with the
on-demand allocator's clamp and page-rounded slot size: the same total the
cache reaches when full, sooner. Allocation runs in the first streamed
single-token layer, always after admission. Whether making every slab
resident per layer commits pages earlier is measured in 3.3.

The emulated-memory runs follow the owner's rule from the 2026-09-26
incident: emulate only on the streamed B side, never on a resident run, and
keep scratch out of `/tmp`.

### D4. Measurement

The handshake skips Q4_K gate/up rows (`gate_type == 12`), which is the
Q4 pack's gate/up type: on Q4 only the early commit applies. The handshake
itself is measured on Q2 (16/10), whose GGUF is now on disk; Q4 checks the
early commit and that nothing regressed.

The resident harness cannot see this change. The measurement is
`ab_bench.py --a ../sf-q3-8flash-prev --b . --bench-arg --ssd-streaming
--bench-arg --simulate-used-memory <X>` on the plain and MTP kinds, at
emulated 48 GB.
- Streamed plain decode is the target metric. Kept when its pooled CI lies
  above zero and no other metric's lies wholly below zero.
- With bench arguments the harness prints no record row (`perf-harness`).
  The streamed figures go in the commit message.
- One resident harness run against the segment start gives the record row
  and shows the resident path unchanged.
- **Against upstream, for information (owner, 2026-11-17).** One best-effort
  comparison at emulated 48 GB on Q2: the PR's head `2d48e3b` against this
  branch (is the port at par), and against its own base if time allows (the
  gain the author claims).

### D5. Outcome: dropped (2026-11-18)

Measured on Q2 at emulated 48 GB, in windows with no other workload, pooled
over three harness runs (8 pairs per kind, bootstrap 95% CI of the median):

| Kind, cache | Decode, `main` -> branch | B/A |
|---|---|---|
| plain, 10.8K context, 3.35 GiB of experts | 29.2 -> 28.5 t/s | -2.7% [-2.9%, -2.1%] |
| mtp-code, 2K context | 37.4 -> 38.9 | +4.0% [+3.5%, +4.3%] |
| mtp-prose, 2K context | 37.9 -> 38.1 | +3.5% [-2.8%, +5.0%] |
| plain, 2K context, 9.5 GiB (by hand, aside) | 33.36 -> 34.77 | +3.9% [+3.3%, +5.3%] |

Prefill is unchanged in every kind. The target metric's CI lies wholly below
zero, so the rule of D4 drops the change.

The sign follows the cache size. The likely reason, from reading and not
from a profile: a handshake layer cannot run its cached experts while the
missing ones load (the PR's own header says doing so changed the output, so
its command buffer starts with the wait), and the ordinary path does overlap
them. With 3.35 GiB of cache most layers miss, and that overlap would be
worth more than the drain the handshake saves; with 9.5 GiB the saving wins.
Upstream's PR behaves the same: its head against its base, with the same
2400-expert cache, reads -2.2% [-2.7%, -1.8%], and the port is at par with
it (the child +2.1%).

What was established and stays true if the idea is reopened:
- the port is correct: `tests/test_qwen4_ssd_experts` passes with the
  handshake cases (failed read, invalid id, cancel and retry); streamed
  output is token-identical to resident on Q2 and Q4; the resident path is
  bitwise unchanged (Q4, 23 pairs);
- D3 holds: at emulated 48 GB the peak footprint equals `main`'s (90.27
  against 90.28 GiB with 80 locked), 9 GiB under lock plus plan;
- upstream skips the release when the experts fail to encode after the wait
  is encoded; the child's port signals it (`sf-keep(ssd)` in the port);
- upstream's Qwen admission ignores `--simulate-used-memory`; an emulated
  upstream run needs an explicit `--ssd-streaming-cache-experts`.

A version worth a new proposal would take the handshake only when the layer's
experts are all cached, or when the cache budget covers enough of the model,
and keep the ordinary path otherwise. The port is commit `dd8db0d` on the
local branch `perf/170-ssd-decode-handshake`.

## Risks / Trade-offs

- **The author measured on a 48 GB machine with Q2, where streaming is
  necessary.** On this 128 GB machine streaming is emulated, and SSD read
  speed differs. The gain may be smaller; D4 decides.
- **New `.inc` files** add to the reading surface. They are kept only if the
  change is kept, and the final pass checks they hold no dead code (the
  removed early-commit switch).
- **A deadlock** between the CPU and the GPU's release wait would hang a
  request. The final PR services each layer synchronously inside the call
  (the first commit's "every wait services pending layers first" rule is
  gone), so the GPU parks only between the experts' commit and the release.
  Reading found one exit that skipped the release (the experts failing to
  encode); the child releases and joins there (`sf-keep(ssd)`). The tests
  cover a failed load, an invalid id and a cancelled request.
