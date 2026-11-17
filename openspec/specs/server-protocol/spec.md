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

### Requirement: Several tool calls per turn
A Qwen assistant turn SHALL be able to emit several tool calls. The server SHALL return every completed call of the turn. When streaming (OpenAI SSE, Anthropic), the server SHALL send each call whole as soon as it is closed, and SHALL NOT send any part of a call the turn did not complete.

#### Scenario: Two calls in one turn
- **WHEN** the model emits two tool calls in one turn
- **THEN** the response lists both calls in order, and a streamed response delivers each call with its whole arguments

#### Scenario: Second call cut
- **WHEN** the token limit or a stop token cuts the second call of a turn
- **THEN** the response, streamed or not, carries only the first call

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

### Requirement: Conversation structure is rendered as sent
A system message in the middle of a conversation SHALL be rendered at its position. After a Qwen thinking answer, the server SHALL evaluate the turn's closing `<|im_end|>` before it reuses the live session for the next request.

#### Scenario: Mid-conversation system message
- **WHEN** a client inserts a system message between two user turns
- **THEN** the prompt renders it there, and the prefix before it is reused from the live session

#### Scenario: Next turn after a thinking answer
- **WHEN** a client continues a conversation whose last assistant turn was a thinking answer served from the live session
- **THEN** the continuation starts after an evaluated `<|im_end|>`

### Requirement: Cache reuse checks what it reuses
The server SHALL reuse a live tool-output tier only when the request's earlier history matches the cached history. After a backend state reset, a live session SHALL count as a cache miss. The cold KV anchor SHALL be found in ChatML (Qwen) prompts. Prefill progress SHALL be reported against the full prompt.

#### Scenario: Rewritten history
- **WHEN** a client edits an earlier message and sends a tool output for the latest call
- **THEN** the server does not reuse the live KV for the edited part

#### Scenario: ChatML cold anchor
- **WHEN** a Qwen prompt is stored to the cold cache
- **THEN** the anchor is placed at a ChatML turn boundary

### Requirement: Response text and fields are exact
JSON written to clients SHALL be valid UTF-8, with invalid sequences replaced by U+FFFD. An integer `seed` SHALL be used exactly, without rounding through a double. An Anthropic response SHALL report the client stop sequence that matched in `stop_sequence`. A Responses API reply cut by `max_output_tokens` SHALL report that as its incomplete reason.

#### Scenario: Length cut inside a multibyte character
- **WHEN** a response is cut by the token limit in the middle of a UTF-8 sequence
- **THEN** the JSON body is valid UTF-8

#### Scenario: Large seed
- **WHEN** two requests use seeds 9007199254740993 and 9007199254740992 at temperature 1.0
- **THEN** the server samples with the two different seeds

#### Scenario: Anthropic stop
- **WHEN** generation stops because a client stop sequence matched
- **THEN** `stop_reason` is `stop_sequence` and `stop_sequence` holds the matched string
