# mtp-speculation Specification

## Purpose

Built-in MTP speculative decoding for Qwen3.8 Flash Next: what `--mtp` must
preserve (greedy output, plain mode, session state) and how its predictor and
draft depth behave, so later speed work on the MTP cycle has a fixed contract.

## Requirements

### Requirement: Greedy output is unchanged by MTP
With built-in MTP enabled, greedy decoding of text prompts SHALL commit exactly
the tokens that plain greedy decoding commits for the same model, prompt and
context. This SHALL hold:

- for one session and for a batch of sessions decoded together;
- for every prefill chunk size, including chunks of one and two tokens;
- at pinned depth 2, pinned depth 3 and the automatic depth;
- in the unfused diagnostic mode.

#### Scenario: CLI greedy continuation
- **WHEN** the CLI generates at temperature 0 with and without `--mtp`, with the
  same prompt, context and prefill chunk
- **THEN** both outputs are byte-identical

#### Scenario: Tiny prefill chunks at depth 3
- **WHEN** the prefill chunk is 1 or 2 tokens and the depth is pinned to 3
- **THEN** the MTP output equals the plain output

#### Scenario: Batched sessions
- **WHEN** two or more sessions decode greedily as one speculative batch
- **THEN** every session commits the tokens its plain greedy decode commits

#### Scenario: Against the previous build
- **WHEN** the A/B harness runs a build with this capability against the
  previous step or the segment's start commit on the MTP kinds
- **THEN** the token gate passes

### Requirement: Plain mode is unaffected
Without `--mtp`, prefill and decode SHALL do no predictor work. Their logits
SHALL be bit-identical to those of the build before this capability.

#### Scenario: Plain bench is bit-identical
- **WHEN** the harness compares the segment's start commit with the final build
  on the plain kind with `--bitwise`
- **THEN** every prefill and decode logits dump is bit-identical

### Requirement: The predictor is primed over the prompt
With MTP enabled, prefilling a text-only prompt SHALL condition the draft
predictor on every prompt position, so the first draft after the prompt
already attends over the prompt. Priming SHALL NOT change the target model's
logits for the prompt. A prompt that contains image rows SHALL NOT be primed,
and its MTP output SHALL stay identical to that of the build before this
capability.

#### Scenario: MTP-mode prefill logits unchanged
- **WHEN** the same prompt is prefilled with MTP by the build before this
  capability and by the build with priming
- **THEN** the logits after prefill are bit-identical

#### Scenario: Acceptance after a code prompt
- **WHEN** the harness runs the `mtp-code` kind on the build with priming
  against the build without it
- **THEN** tokens per cycle rise, and MTP decode throughput is higher

#### Scenario: Image prompt
- **WHEN** a conversation with images is decoded greedily with `--mtp` by the
  build before this capability and by the build with it
- **THEN** every turn completes and both outputs are byte-identical

### Requirement: Draft depth follows recent acceptance
By default the session SHALL choose between depth 2 (one draft) and depth 3
(two drafts) per cycle from its recent first-draft acceptance: it SHALL
engage depth 3 after a run of accepted first drafts and leave it when
acceptance or the second draft falters. `DS4_QWEN4_MTP_DEPTH=2` or `=3` SHALL
pin the depth. Exact sampling at nonzero temperature SHALL keep running at
depth 2.

#### Scenario: Pinned depth
- **WHEN** `DS4_QWEN4_MTP_DEPTH=3` is set
- **THEN** every cycle that has a draft runs at depth 3, and the bench reports
  cycles that committed three tokens

#### Scenario: Automatic depth on code
- **WHEN** the automatic depth runs the `mtp-code` kind on a primed prompt
- **THEN** the bench reports cycles that committed three tokens

### Requirement: Session state stays compatible
The session payload and disk-KV checkpoint format SHALL be unchanged. A
checkpoint written by the build before this capability SHALL load in the new
build, and a checkpoint written by the new build SHALL load in the old build.
In both cases the greedy continuation SHALL equal the one the reading build
gives from a checkpoint it wrote itself for the same conversation. Rewind, snapshot restore and payload load SHALL discard any
predictor state that is pending for a position that no longer follows.

#### Scenario: Old checkpoint, new build
- **WHEN** a server built before this capability writes a disk-KV checkpoint
  with `--mtp`, and a server of the new build loads it for the conversation's
  next turn
- **THEN** the checkpoint is used, and the response equals the new build's
  response when it reads its own checkpoint for that turn

#### Scenario: New checkpoint, old build
- **WHEN** a server of the new build writes the checkpoint and a server built
  before this capability loads it for the next turn
- **THEN** the checkpoint is used, and the response equals the old build's
  response when it reads its own checkpoint

#### Scenario: Rewind after prefill
- **WHEN** a session prefilled with MTP is rewound or restored before its next
  token is evaluated
- **THEN** decoding from the rewound position equals a fresh session's decode
  of the same tokens
