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

### D3. Memory: the up-front slabs inside `80`'s admission

`80` admits a streaming run against min(87.5% of RAM, Metal's
recommendation), with the cache budget counted. The handshake allocates the
whole cache budget's slabs on first use instead of on demand. Check that:
- the allocated bytes equal the admitted cache budget, not more;
- first-use allocation happens after admission, so a run that admission
  would refuse is still refused;
- at emulated 48 GB, the run's peak footprint stays within the budget.

The emulated-memory runs follow the owner's rule from the 2026-09-26
incident: emulate only on the streamed B side, never on a resident run, and
keep scratch out of `/tmp`.

### D4. Measurement

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

## Risks / Trade-offs

- **The author measured on a 48 GB machine with Q2, where streaming is
  necessary.** On this 128 GB machine streaming is emulated, and SSD read
  speed differs. The gain may be smaller; D4 decides.
- **New `.inc` files** add to the reading surface. They are kept only if the
  change is kept, and the final pass checks they hold no dead code (the
  removed early-commit switch).
- **A deadlock** between the CPU spin and the GPU event would hang a request.
  The tests cover a failed load and a cancelled request mid-handshake, and the
  author's "every command-buffer wait services pending layers first" rule is
  checked by reading.
