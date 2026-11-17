# Proposal

## Why

With `--ssd-streaming`, each single-token decode layer drains the GPU so the
CPU can read the router's expert ids, load the missing experts and bind them.
The GPU idles through every drain. #1328 (6 commits, built on `b3f5018`)
removes most of that idle time. From its first commit's message:
- **Early commit.** A layer's expert work is committed as soon as it is
  encoded, instead of waiting for the next layer's drain. `9b7b1da` later
  drops the switch for it.
- **Handshake.** A single-token decode layer is encoded before its experts
  are known:
  - the router's ids are copied to shared words at the end of a command
    buffer;
  - the next buffer starts with a wait on a shared event;
  - the experts run through the layer's address table;
  - the CPU encodes the next layer, waits for the ids, loads the missing
    experts, writes their addresses and releases the GPU.

  The handshake is on by default for every single-token layer, the
  single-token steps of `--mtp` included (`d1f6d00` dropped the MTP opt-in);
  `DS4_QWEN4_STREAM_HANDSHAKE=0` turns it off. The whole cache budget's slabs are
  allocated up front, so the kernels see every slab when they are encoded.

The author's figures (M4 Pro 48 GB, Q2, `ds4-bench --ssd-streaming`, 4K
prompt, three interleaved rounds; not reproduced here):
- decode 17.4-18.3 -> 20.9-21.8 t/s;
- steady decode 18.5-19.0 -> 22.5-23.0 t/s;
- prefill unchanged;
- MTP neutral (review).

Frontier logits and 64-token greedy continuations are reported bit-identical
to `main` on two prompts. The later commits harden the failure exits and
return a failed load's reservations everywhere, which overlaps #1125's
slot-leak fixes (`120`).

Two points the review flagged and this change must settle:
- The ordinary streamed path rejects invalid expert ids synchronously. The
  handshake defers that rejection to the next GPU wait. Validation at this
  boundary must not weaken (AGENTS.md).
- Allocating every slab up front changes when memory is committed. Whether it
  interacts with `80`'s engine-open admission and the documented memory policy
  (`ssd-streaming`) was not checked.

## What Changes

- Port the six commits after `90` and `120`:
  - the new `ds4_metal_stream_overlap.inc` and `ds4_metal_stream_handshake.inc`,
    the `ds4_metal.m` hooks and the `qwen4.metal` changes;
  - the `tests/test_qwen4_ssd_experts.c` and `qwen4_ssd_pread_probe.h`
    additions;
  - the doc lines.

  `120`'s slot-return fix is merged with `2d48e3b`'s, keeping one copy.
- Prove three things before measuring:
  - invalid expert ids are still rejected before any read of the addressed
    memory, and the request fails as it does today (design D2);
  - the up-front slab allocation stays inside the budget `80` admits
    (design D3);
  - streamed output is token-identical to resident, as `ssd-streaming`
    requires.
- Measure streamed decode at emulated smaller memory, and keep the change
  only on a gain (design D4).

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none) Streamed output stays token-identical to resident, the resident path
is untouched, and admission and the memory policy keep their specified
behaviour. If D3 finds that admission must change, a spec delta for
`ssd-streaming` is added before landing.

## Impact

- `ds4_metal.m`, new `ds4_metal_stream_*.inc`, `metal/qwen4.metal`,
  `Makefile`, `tests/test_qwen4_ssd_experts.c`, `tests/qwen4_ssd_pread_probe.h`,
  `docs/SSD_STREAMING.md`, `docs/QWEN38_FLASH_NEXT.md`,
  `docs/upstream-prs.md`.
- Resident runs: no change by construction. The handshake runs only for
  streamed single-token decode layers.
- Q2 is the author's pack. Its GGUF is now on disk, and the handshake only
  engages there (Q4's Q4_K gate/up rows keep the ordinary path, design D4).
