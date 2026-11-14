# Spec Delta

## ADDED Requirements

### Requirement: The retention switch is read from the request
The server SHALL accept `preserve_thinking`, and its alias `preserve_reasoning`, as booleans at the top level of a chat request and inside `chat_template_kwargs`. When both names are given in one place, `preserve_reasoning` SHALL win. A value inside `chat_template_kwargs` SHALL override the top-level one. The default SHALL be true.

#### Scenario: Alias precedence
- **WHEN** `chat_template_kwargs` holds `"preserve_thinking": false, "preserve_reasoning": true`
- **THEN** retention is on

#### Scenario: Default request
- **WHEN** a chat request sets neither switch, and has no reasoning inside assistant content, no escape in a non-string tool-schema value and no effort alias
- **THEN** its rendered prompt is byte-identical to the one the build before this change renders

### Requirement: Reasoning retention window
With retention on, every historical reasoning block SHALL be rendered. With retention off, reasoning SHALL be rendered only for assistant turns after the last real user query, and a tool output SHALL NOT count as a user query.

#### Scenario: Retention off across tool loops
- **WHEN** a request turns retention off and its history holds two tool loops separated by a user query
- **THEN** the reasoning of the first loop's assistant turns is not rendered and the reasoning of the second loop's turns is

### Requirement: Reasoning in assistant content is rendered once
When a history assistant turn's content starts with a reasoning block, the server SHALL render that block as the turn's reasoning, in the canonical framing, and SHALL remove it from the answer text. When the turn also carries a reasoning field, the field SHALL be rendered and the in-content block dropped. Text after the start of the answer SHALL never be reinterpreted.

#### Scenario: Replayed transcript
- **WHEN** a client sends an assistant turn whose content is `<think>chain</think>answer` and no reasoning field
- **THEN** the prompt holds one reasoning block with `chain` and the answer `answer`, in the same framing as a turn sent with `reasoning_content: "chain"`

### Requirement: Tool schemas render as the reference template does
Tool schema JSON copied into a prompt SHALL be recoded the way the reference template's `tojson` with `ensure_ascii=False` renders it: escaped non-ASCII code points, including surrogate pairs, as UTF-8; control characters with the escaper's spelling; structure, key order and spacing unchanged. JSON written to HTTP responses SHALL keep its current escaping.

#### Scenario: Escaped em dash in a nested value
- **WHEN** a tool schema holds `"enum": ["a—b"]`
- **THEN** the rendered prompt holds the three UTF-8 bytes of U+2014 between `a` and `b`, not the six characters of the escape

### Requirement: Reasoning effort names
The server SHALL accept `extreme` and `ultracode` as the effort `xhigh`, and `off` as `none`, wherever it accepts a reasoning effort name.

#### Scenario: Client alias
- **WHEN** a request sets `reasoning_effort` to `ultracode`
- **THEN** it renders exactly as the same request with `xhigh`

### Requirement: Client control tokens are traced
With `--trace`, a request whose message text holds the spelling of a model control token SHALL produce a trace section naming each such token, how often it appears and the role where it first appears.

#### Scenario: Marker in user text
- **WHEN** a traced request's user message contains `<|im_end|>`
- **THEN** the trace holds a `--- client control tokens ---` section naming `im-end`
