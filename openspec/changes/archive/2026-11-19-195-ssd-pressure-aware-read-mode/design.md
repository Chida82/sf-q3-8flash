# Design

## Context

Two descriptors exist after `190`: the model's buffered one and, with the
switch, a second one with `F_NOCACHE` read through page-aligned bounce
buffers. Prefill batches and row-path calls (decode, MTP verification) go
through the same pool (`ds4_gpu_stream_expert_pread_into`).

## Decisions

### D1. The neighbour

A scratch C tool: `mmap` N GiB anonymous, write every page, then touch a
page in every 64 MiB once a second (so the kernel sees it in use); on exit
it prints `task_info` compressed and swapped bytes and the slowest touch
pass. It never wires memory, so it cannot cause the wired-memory exhaustion
behind this Mac's panics; the run guard still applies, with its
compressor threshold measured from the start of the run, and the neighbour
is part of the guarded process tree.

### D2. Step 0 table

Q4, 9,701 slots (54 GiB), kinds `capped-mtp-code`, `capped-plain`, plus a
cold 32K prefill. Conditions: no neighbour / neighbour of 60 GiB; reads
buffered / uncached / split by class. 3 runs per cell. Columns: decode,
prefill, the neighbour's compressed and swapped GiB, its slowest touch.

What decides:
- if uncached with a neighbour is not slower than buffered with a neighbour
  and spares it, the class split and the pressure switch are compared on
  the RAM-free rows;
- if buffered still wins decode with a neighbour (the kernel keeps some
  file cache), S2 must keep decode buffered too and S1 is the candidate.

### D3. S2's signal

`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` (normal / warning / critical), the
same source `186` designs. The read mode flips at warning and back at
normal, with a hold time so it does not oscillate; counted in the stream
timing summary.

### D4. Keep rule

Two conditions must both hold, at 54 GiB:
- with the neighbour: the neighbour's compressed + swapped bytes fall, and
  decode of an MTP kind is not below buffered (pooled CI not wholly below
  zero);
- without a neighbour: no metric's CI wholly below zero against `main`.

## Risks / Trade-offs

- A pressure signal can come late: the first reads after a neighbour starts
  are still buffered. The neighbour's cost is measured, not assumed.
- macOS also uses the file cache for its own work; uncached reads give up
  readahead the kernel might have done. D2's prefill column shows it.
