## ADDED Requirements

### Requirement: Visible reuse keys predict the next rendering
A reuse key the server stores at the end of a Qwen assistant turn SHALL be a byte prefix of the prompt that the server renders for the next request carrying that turn unchanged. The key builders and the chat renderer SHALL write an assistant answer's body with the same whitespace rule.

#### Scenario: Plain answer ending in a newline
- **WHEN** a Responses client continues a conversation whose last assistant answer, without tool calls, ends in `\n`
- **THEN** the request's rendered prompt starts with the stored Responses-visible key, and the server reuses that checkpoint instead of prefilling the conversation again

#### Scenario: Prompts are unchanged
- **WHEN** any conversation is rendered after the fix
- **THEN** its prompt bytes are identical to before
