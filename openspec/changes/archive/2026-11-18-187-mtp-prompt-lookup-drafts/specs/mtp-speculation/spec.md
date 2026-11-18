## ADDED Requirements

### Requirement: Drafts may come from prompt lookup
With `--mtp`, when the last three committed tokens and the next one occurred
earlier in the prompt or the output and the two sites agree six or more tokens
back, the tokens that followed SHALL be a second source for the cycle's draft
rows. Verification SHALL decide acceptance as for a predictor draft, so greedy
output SHALL stay token-identical to plain decoding. The verify width SHALL
stay at two or three rows. `DS4_QWEN4_MTP_LOOKUP=0` SHALL turn the lookup off.

#### Scenario: Copying output
- **WHEN** the model's greedy output repeats a passage of the prompt
- **THEN** cycles drafted from the lookup commit more than one token, and the generated token ids are identical to plain decoding

#### Scenario: No match
- **WHEN** the committed tokens match no earlier occurrence of the minimum length
- **THEN** the predictor drafts the cycle as it did before this change

#### Scenario: Wrong lookup
- **WHEN** a looked-up token differs from the token verification selects
- **THEN** the cycle commits the verified token, discards the rest of the draft, the miss counts against the lookup's window, and the predictor's state is current for the next cycle

#### Scenario: Lookup off
- **WHEN** `DS4_QWEN4_MTP_LOOKUP=0` is set
- **THEN** every cycle is drafted by the predictor

### Requirement: The drafting source follows recent verdicts
The predictor SHALL run every cycle. Each source SHALL keep a window of its
last eight first-draft verdicts, scored on every cycle. The lookup SHALL be
heard only while six of its last eight were right. When both sources name the
same first token, the lookup's second token SHALL be the second draft; when
they differ, the source with the better window SHALL draft, the predictor on a
tie.

#### Scenario: Both sources agree
- **WHEN** a healthy lookup and the predictor name the same first draft and the lookup has a second token
- **THEN** the cycle verifies three rows with the lookup's second token, and the predictor's chained step is not run

#### Scenario: A failing lookup does not disturb the predictor's depth
- **WHEN** looked-up drafts miss
- **THEN** the predictor's window, which is scored on its own first draft every cycle, and its depth policy are unaffected

### Requirement: Lookup drafts keep exact sampling exact
With `--mtp-exact-sampling` at nonzero temperature a looked-up token SHALL be
treated as the predictor's draft is: a point proposal, accepted with its target
probability at its row, the first rejection emitting a residual sample. The
lookup depends only on tokens already drawn, so the rule holds unchanged.

#### Scenario: Sampled copy
- **WHEN** exact sampling runs over a passage the lookup matches
- **THEN** each looked-up token is accepted with its target probability, and the sampled distribution is the ordinary sampler's
