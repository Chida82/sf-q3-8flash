## ADDED Requirements

### Requirement: Drafts may come from prompt lookup
With `--mtp`, a cycle SHALL draft the tokens that followed an earlier
occurrence of the tokens just committed, when that match has at least the
minimum length; otherwise the predictor SHALL draft as before. Verification
SHALL decide acceptance as for a predictor draft, so greedy output SHALL stay
token-identical to plain decoding. `DS4_QWEN4_MTP_LOOKUP=0` SHALL turn lookup
drafting off.

#### Scenario: Copying output
- **WHEN** the model's greedy output repeats a passage of the prompt
- **THEN** cycles drafted from the lookup commit more than one token, and the generated token ids are identical to plain decoding

#### Scenario: No match
- **WHEN** the committed tokens match no earlier occurrence of the minimum length
- **THEN** the predictor drafts the cycle as it did before this change

#### Scenario: Wrong lookup
- **WHEN** a looked-up token differs from the token verification selects
- **THEN** the cycle commits the verified token, discards the rest of the draft, and the predictor's state is current for the next cycle

#### Scenario: Lookup off
- **WHEN** `DS4_QWEN4_MTP_LOOKUP=0` is set
- **THEN** every cycle is drafted by the predictor
