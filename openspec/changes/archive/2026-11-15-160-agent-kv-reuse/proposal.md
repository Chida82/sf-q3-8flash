# Proposal

## Why

Coding agents send long, growing conversations. When the server cannot reuse
a conversation's KV state, it prefills the whole prompt again, which costs
tens of seconds at 70K tokens. The 2026-11-13 review lists open upstream PRs
that make reuse hit more often in agent workloads. The figure it gives for
the largest: #1200 brings a return to a 73K conversation from 38.4 s to
0.98 s in its author's workflow. None is in `upstream/main`.

The review gives each PR a line, not a trace. Reachability came from hunk
function names and PR bodies. Whether each PR's Qwen path exists in the child,
and whether any changes the checkpoint format, was **not checked**. This
change therefore starts with that check and plans the ports from what it
finds.

| PR | Claimed effect (review) | Dependency / overlap |
|---|---|---|
| #1169 | exact tool-call replay across KV checkpoint restores; EOS commitment; checkpoint serialization | required by #1206 |
| #1206 | Qwen Responses final-answer cache reuse | needs #1169 |
| #1212 | reload evicted Qwen tool turns for clients that send reasoning back | - |
| #1194 | heal the forked live checkpoint on a token-mismatch miss | supersedes closed #1021 with #1170 |
| #1170 | keep the disk checkpoint the next request loads when storing an evict snapshot | - |
| #1281 | a short live prefix no longer hides a longer disk hit; persist a live session before a rewind | how rewind applies to Qwen's recurrent state was not checked |
| #1342 | continued KV checkpoint at the first chunk past each step | alternative to #1340 and #903; take one |
| #1228 | retain bounded cold-cache prefixes for long prompts | - |
| #1200 | retain bounded Qwen Responses prompt checkpoints | - |
| #1216 | longest text-prefix checkpoint in one pass | same choice, faster lookup |
| #1258 | skip store attempts when the session has no checkpoint | log noise, wasted work |

#1175, #1134 and #1157 also change reuse, but they fix correctness; they are
in `130`.

## What Changes

1. **Triage.** For each PR:
   - its reachability in the child, with the call chain;
   - whether it changes the disk checkpoint or session payload format;
   - which PRs it conflicts with.

   A PR that changes the format either keeps reading old checkpoints
   (AGENTS.md: snapshot format changes keep old-format compatibility) or waits
   for the owner's approval of a format break.
2. **A reuse workload** to measure against: a scripted agent conversation
   through `sf-q3-8flash-server`. It runs tool loops, a Responses
   continuation, a client that echoes reasoning, an eviction under a small
   live budget, and a restart. The script reports, per request, the cached
   and prefilled tokens and the wall time (design D2).
3. **Ports**, in dependency order (#1169 before #1206; one of
   #1342/#1340/#903). Each port is kept only if the workload shows more
   cached tokens or less wall time, and the token-exact restore checks pass.
4. **Closing:** registry lines, `docs/SERVER.md` on the cache tiers.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none) A response must not depend on whether the KV state was reused, and
that already holds. These PRs change only how often reuse happens. If triage
finds a format change, this change gets a spec delta (session state
compatibility) before any port.

## Impact

- `ds4_server.c` (live and disk tiers), `ds4_kvstore.*`, possibly `ds4.c`
  (session payload), `tests/ds4_test.c`, a new workload script under
  `speed-bench/` or `tests/`, `docs/SERVER.md`, `docs/upstream-prs.md`.
- After `90` and `130`: they share the server code, and `130`'s #1175
  validation must be in place before reuse widens.
