# Design

## Context

The decode loop tracks `dsml_tracker.calls_end`, the text end of the last
closed call. After the loop, `calls_cut` is set when `text.len` exceeds it;
the text is cut back, finish becomes `tool_calls`, and the end-token commit
is skipped because the live KV ends past the call.

`server_generation_rewind` already exists for MTP's speculative boundary. It
calls `ds4_session_rewind` and, when the backend no longer matches the token
checkpoint, re-syncs the whole prefix. For Qwen the recurrent (GDN) state
cannot step back without a snapshot: a rewind with no matching snapshot
resets the graph, and the re-sync then rebuilds the full prefix, which is a
cold prefill.

## Decisions

### D1. Snapshot at each closed call, restore only when needed

When the tracker closes a call (`calls_end` advances), record the token
position and take the cheapest snapshot the session offers at that position.
The MTP rollback snapshots that verify cycles already take are the first
candidate; measure their cost per call. When the turn ends with `calls_cut`
and the model's own stop (not `length`, not an error):
- restore that snapshot;
- truncate the token checkpoint to the recorded position;
- commit `<|im_end|>`;
- continue as for a clean tool turn.

A turn that ends cleanly drops the snapshot unused. If no snapshot fits
(for example a cycle boundary inside the call's last tokens), fall back to
today's behaviour and log it.

Rejected:
- **Constrained sampling after `</tool_call>`:** it changes which tokens are
  generated and can create a call the model would not have made.
- **Rewind without a snapshot:** the re-sync is a full prefill, worse than
  today's disk reload.

### D2. Gate on frequency

Step 1 of the proposal decides whether D1 is built at all. The threshold is
any turn on `agent_reuse.py` that ends on the model's stop with trailing
output. Below it, the log line stays as the sentinel and the change closes
with figures only.

### D3. Exactness

The restored session must be byte-equal to a session that stopped at the
call:
- a unit or model-backed check compares the restored state's next-token
  logits with a session that decoded only up to `</tool_call>` and
  `<|im_end|>`;
- `tests/test_qwen4_checkpoint_replay.py` and the model gates pass.

## Risks

- Snapshot cost on every closed call: measure it, and keep the change only if
  the per-turn overhead is below the reload it saves.
- MTP: a closed call can land inside a verify cycle. The snapshot must be
  taken at a committed boundary.
