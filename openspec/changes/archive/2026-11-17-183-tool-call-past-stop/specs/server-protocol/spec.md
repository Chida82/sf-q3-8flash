# Spec Delta

## MODIFIED Requirements

### Requirement: Completed turns keep their answer
When a turn completes with an unterminated reasoning block, the server SHALL return the text as content instead of dropping it. When the model selects a stop token while a tool call is open (inside the call, not between calls and not in reasoning), the server SHALL NOT end the turn there: it SHALL continue with the most likely non-stop token, at most 24 times per decode pass (a tool-error continuation is a new pass), and SHALL decode every other state exactly as without this rule. When a turn still ends inside an unterminated tool call, the server SHALL apply its parse-failure recovery and SHALL NOT report `finish_reason: "error"` on a successful HTTP response.

#### Scenario: Missing reasoning close
- **WHEN** a thinking turn stops at EOS without `</think>`
- **THEN** the response carries the generated text as content

#### Scenario: Cut tool call
- **WHEN** generation ends inside a tool call's arguments
- **THEN** the response follows the parse-failure recovery and its finish reason is not `error`

#### Scenario: Stop token inside an open call
- **WHEN** the model selects `<|im_end|>` inside an open `<tool_call>` and then closes the call
- **THEN** the response, streamed or not, carries the closed call whole with `finish_reason: "tool_calls"`, and the server logs one suppression warning

#### Scenario: Stop token after a closed call
- **WHEN** the model selects `<|im_end|>` after `</tool_call>`, between calls
- **THEN** the turn ends there, as before

#### Scenario: Bound reached
- **WHEN** the model selects a stop token inside an open call more than 24 times in one decode pass
- **THEN** the stop is accepted and the unterminated-call recovery runs
