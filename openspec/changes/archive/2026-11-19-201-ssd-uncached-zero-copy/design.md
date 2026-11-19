# Design

## Decisions

### D1. Step 0

A scratch timer around the `memcpy` in the uncached read, summed per load;
the stream timing summary's load wait beside it. Runs at 9,701 slots, the
`capped-*` kinds, 3 runs each. The ceiling is the copy time that sits on a
miss layer's critical path (its slowest task), over decode time.

### D2. Slots with slack

The slab's slot size becomes the expert's three tensors each rounded up
with one page before and after; the entry records, per tensor, the slot
offset where the tensor's first byte landed. The address table already
stores a buffer and an inner offset per tensor, so kernels see no change.
The buffered path reads into the same position, so a slot's layout does not
depend on the read mode.

### D3. Keep rule

`190`'s bench, capped and RAM taken, 54 GiB then 48 and 60: decode of any
kind with a pooled CI above zero, no metric's CI wholly below zero. The
slot count at each footprint falls by the slack (about 1.2%), and the
comparison is at the same footprint, so the loss of slots is inside the
measurement.

## Risks / Trade-offs

- Every reader of an entry's position must use the recorded inner offset;
  the model-less tests check reads at unaligned file offsets through both
  modes.
