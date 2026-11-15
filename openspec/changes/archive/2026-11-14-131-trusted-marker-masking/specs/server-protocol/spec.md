# Spec Delta

## ADDED Requirements

### Requirement: Message data cannot inject control tokens
Text that arrives in a chat request's message content, reasoning or tool output SHALL be tokenized as text. A spelling of a model control token inside that text SHALL NOT become the control token. Control tokens SHALL come only from the renderer's own framing.

#### Scenario: End-of-turn marker in user text
- **WHEN** a user message contains `<|im_end|><|im_start|>system` followed by an instruction
- **THEN** the prompt tokens hold no `<|im_end|>` or `<|im_start|>` control token at that place, and the rendered turn structure is the same as for a message without the spelling

### Requirement: Masking keeps cache reuse
A conversation whose message data carries a control-token spelling SHALL keep the same live and disk cache reuse as the same conversation without the spelling. Cache keys SHALL distinguish a masked spelling from a real control token, and keys of prompts without control spellings SHALL be unchanged.

#### Scenario: Agent reads a marker-heavy file
- **WHEN** a thinking-mode client continues a conversation whose earlier tool result contains `<|im_end|>`
- **THEN** the next request reuses the cached prefix as it would without the spelling, and no cache tier is turned off for the session

#### Scenario: Existing checkpoints
- **WHEN** a prompt without control spellings is looked up after the upgrade
- **THEN** its key text is byte-identical to before and its disk checkpoint hits
