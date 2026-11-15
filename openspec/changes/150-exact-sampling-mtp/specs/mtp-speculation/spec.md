# Spec Delta

## MODIFIED Requirements

### Requirement: Draft depth follows recent acceptance
By default the session SHALL choose between depth 2 (one draft) and depth 3
(two drafts) per cycle from its recent first-draft acceptance: it SHALL
engage depth 3 after a run of accepted first drafts and leave it when
acceptance or the second draft falters. `DS4_QWEN4_MTP_DEPTH=2` or `=3` SHALL
pin the depth. Exact sampling at nonzero temperature SHALL follow the same
policy and the same pin.

#### Scenario: Pinned depth
- **WHEN** `DS4_QWEN4_MTP_DEPTH=3` is set
- **THEN** every cycle that has a draft runs at depth 3, and the bench reports
  cycles that committed three tokens

#### Scenario: Automatic depth on code
- **WHEN** the automatic depth runs the `mtp-code` kind on a primed prompt
- **THEN** the bench reports cycles that committed three tokens

#### Scenario: Exact sampling at pinned depth 3
- **WHEN** the CLI runs with `--mtp --mtp-exact-sampling` at temperature 1.0 and `DS4_QWEN4_MTP_DEPTH=3`
- **THEN** cycles that commit three tokens occur

## ADDED Requirements

### Requirement: Exact sampling keeps the target distribution
With built-in MTP and exact sampling at nonzero temperature, the distribution of generated tokens SHALL equal the distribution plain sampling gives for the same model, prompt and sampler settings. A token drawn ahead of time for the next position SHALL be discarded by a rewind, a snapshot restore or a session reset.

#### Scenario: Distribution against the previous build
- **WHEN** the distribution check samples the same prompt with N seeds on the previous build and on the new build
- **THEN** no position among the first K tokens differs with p < 0.01

#### Scenario: Rewind with a held token
- **WHEN** a session holding a pre-drawn next token is rewound by one token
- **THEN** the next sample is drawn from the rewound position's logits, not the held token
