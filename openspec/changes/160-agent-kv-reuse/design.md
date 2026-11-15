# Design

## Context

Eleven PRs, one to three commits each, by several authors, all in the
server's cache tiers. They were measured, where at all, on their authors'
workloads; #1280 and some others on DeepSeek V4.1. Qwen differs in one way
that matters for reuse: its recurrent (GDN) state cannot be rewound
token by token. A Qwen session goes back only to a snapshot, or resets and
replays. Any PR that assumes a rewindable KV cache needs care here.

## Decisions

### D1. Triage before any port

For each PR, `$SCR/c160/triage.txt` records:
- the child functions its hunks change, and the request path that reaches
  them;
- whether it writes or reads a different checkpoint or payload layout:
  diff the kvstore header and extension definitions in `ds4_kvstore.h`, and
  the `qwen4_session_save/load_payload` byte layout;
- for #1281's rewind persistence, how the Qwen session rewinds
  (`ds4_session_sync_internal`, snapshot or replay);
- its overlaps.

A PR that does not reach Qwen, or whose only effect assumes rewindable KV,
is dropped with its reason.

### D2. The workload decides, not the authors' figures

`speed-bench/agent_reuse.py --server-bin B --model M` starts the server with
`--kv-disk-dir` in a temp dir and a small live budget, then plays a fixed
script:
- an OpenAI tool loop of five calls;
- a Responses continuation of the same task;
- a client that echoes `reasoning_content`;
- a second conversation that evicts the first;
- a return to the first;
- a server restart, then a return again.

Per request it prints the prompt tokens, cached tokens, prefilled tokens and
wall time, and at the end the totals. Each run uses fixed seeds and
temperature 0, so the responses must match byte for byte between builds:
that is the correctness gate.

A port is kept when, against the step before, it raises cached tokens or cuts
wall time on the requests it targets, the responses stay byte-identical, and
no other request loses cached tokens.

### D3. One continued-checkpoint rule

#903, #1340 and #1342 solve the same problem: continued checkpoints that are
never written during a long prefill. #1342 does not depend on the chunk
schedule, so it is the first candidate. #1340 changes the default interval to
8192, which is the Qwen prefill chunk. Take one, by D2.

## Risks / Trade-offs

- **Wrong reuse is worse than no reuse.** Every step runs the token-exact
  restore checks (`tests/test_qwen4_checkpoint_replay.py`,
  `./ds4_test --server`) besides D2's response comparison.
- **The workload is synthetic.** It covers the shapes the PRs name. It does
  not prove the gain on a real agent session, so the report gives both the
  workload figures and one real session replay, if the owner provides one.
- **The scope may shrink a lot at triage.** That is an acceptable result: the
  change then lands only the PRs that survived, or none.
