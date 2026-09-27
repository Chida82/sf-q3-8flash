# Spec Delta

## ADDED Requirements

### Requirement: Greedy identity is checked on both packs
The repository SHALL provide a check that, for a fixed set of text prompts,
runs greedy CLI generation without and with built-in MTP on a given model and
reports every prompt whose outputs differ. It SHALL run at the automatic depth
and at pinned depths 2 and 3. It SHALL name the first differing word and exit
with a failure status when any output differs. The Q2 and Q4 packs SHALL both
pass it before a change that touches MTP, prefill or decode lands.

#### Scenario: Identical outputs
- **WHEN** the check runs on a model and build where MTP greedy output equals plain greedy output for every prompt and depth
- **THEN** it reports every pair as identical and exits 0

#### Scenario: A diverging prompt
- **WHEN** one prompt's MTP output differs from its plain output at one depth
- **THEN** the check names the prompt, the depth and the first differing word, and exits 1

#### Scenario: The Q2 networking case
- **WHEN** the check runs on the Q2 pack with upstream's networking prompt at 256 tokens
- **THEN** the MTP output is byte-identical to the plain output
