# Proposal

## Why

A Qwen turn can sample its stop token, `<|im_end|>`, inside an open
`<tool_call>` block. #1071 reports it on Qwen3.8 Q2: after 351 generated
tokens the model emitted `<|im_end|>` with the block still open, and the
request failed. In the child the same state takes one of two fallbacks:
- the decode loop accepts the stop (`ds4_server.c:12752`, and `:12817` for a
  drafted stop);
- a non-streamed request then runs the tool-error continuation
  (`continue_after_invalid_dsml`). It re-prompts the model with a
  model-visible error and decodes again;
- a streamed request cannot re-prompt. It defers to the parse-failure
  recovery (`ds4_server.c:13153-13166`, from #1163 in `130`), and the client
  gets the raw text of a call it cannot run.

Either way the agent loses the call. A tool block has no executable meaning
until `</tool_call>` closes it, so a stop token there is invalid output, not
the end of the turn.

#1071 (`1018c65`, one commit, `ds4_server.c` +51/-6) keeps decoding instead.
When the sampled token is a stop token inside an open call, it takes the best
non-stop token from the same logits with the existing
`ds4_session_argmax_ignoring_eos()`. A drafted stop token inside an open call
drops through the existing rewind-and-resample path, so the next sample sees
fresh logits. The override is bounded: after 24 suppressions
(`DS4_TOOL_CALL_STOP_SUPPRESS_LIMIT`) the stop is accepted and the existing
fallbacks run. Quality under the intake criteria: correct tool calls.

The review also found #997 (`4c6a9c3`): an unrecognized byte in the
structural part of a call parks the tool-syntax tracker for the rest of the
turn (`dsml_decode_tracker_update`, last `return` of the structural loop).
That holds greedy sampling and never sees `</tool_call>`. This change decides
"open call" from that tracker, so it takes #997's structural-advance fix with
it (design D2).

## What Changes

- In `generate_job_inner`, a stop token selected while the tool-syntax
  tracker is inside a call (not between calls, not in reasoning) is replaced
  by `ds4_session_argmax_ignoring_eos()`, at most 24 times per turn. A turn
  with overrides logs one warning and a trace event with their count.
- A drafted stop token inside an open call ends the block with
  `resample = true`. The decision is made per token from the tracker's state
  at that token, not once per block (design D1).
- The "incomplete tool call" warning gains the suppression count. The PR's
  generation-tail excerpt is not taken: it writes model output into the
  warning log.
- #997's first fix: the structural loop advances past a byte it does not
  recognize instead of returning with the cursor parked. Its second fix (a
  lone `<` of `</parameter>`) is already in the child, in another form.
- Unit tests in the `--server` group: the override decision as a small pure
  helper, and the tracker fed byte by byte over Qwen calls with stray bytes.

Output changes only in a state that is already invalid: a stop token inside an
unclosed call. Every turn that does not reach that state decodes exactly as
before (design D4).

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `server-protocol`: "Completed turns keep their answer" gains the rule that
  a stop token inside an open tool call does not end the turn, within a
  bound.

## Impact

- `ds4_server.c` (`generate_job_inner` stop sites, `dsml_decode_tracker_update`
  structural loop, the incomplete-call warning, unit tests).
- `docs/SERVER.md` ("Unfinished turns"); `docs/upstream-prs.md` (`1018c65`,
  `4c6a9c3`).
