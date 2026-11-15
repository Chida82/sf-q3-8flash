# server-protocol Specification

## Purpose
How the server turns protocol requests into model input: which bytes of a request may become control tokens, and how cache keys stay faithful to that.

## Requirements

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

### Requirement: Visible reuse keys predict the next rendering
A reuse key the server stores at the end of a Qwen assistant turn SHALL be a byte prefix of the prompt that the server renders for the next request carrying that turn unchanged. The key builders and the chat renderer SHALL write an assistant answer's body with the same whitespace rule.

#### Scenario: Plain answer ending in a newline
- **WHEN** a Responses client continues a conversation whose last assistant answer, without tool calls, ends in `\n`
- **THEN** the request's rendered prompt starts with the stored Responses-visible key, and the server reuses that checkpoint instead of prefilling the conversation again

#### Scenario: Prompts are unchanged
- **WHEN** any conversation is rendered after the fix
- **THEN** its prompt bytes are identical to before
