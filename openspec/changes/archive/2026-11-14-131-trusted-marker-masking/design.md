# Design

## D1. Mask as upstream does

Take #1284's mechanism unchanged where it can be: the renderer appends with a
trust flag per span, the prompt carries the span list to tokenization, and
the tokenizer's special-token match runs only inside trusted spans. Keeping
upstream's text for this part keeps the merge site small. Every untrusted
span gets the ordinary BPE path, so `<|im_end|>` in client text becomes the
text tokens of `<`, `|`, `im`, `_end`, `|`, `>` (whatever the vocabulary
splits it into).

## D2. Trust-aware key text instead of `session_ambiguous`

The byte tiers compare a key text, not tokens. Today key text equals the
rendered bytes, which is why #1284 must give up when one spelling can mean two
token sequences. Instead, define the key text as the rendered bytes with each
untrusted control spelling prefixed by one escape byte (`0x1B`, never present
in rendered prompts; a literal `0x1B` in client text is itself escaped by
doubling, so the map stays injective).

- From the renderer: written while rendering, from the trust spans.
- From tokens (disk keys, memory text): a control token renders as its
  spelling; a run of text tokens that spells a control marker renders with
  the escape. The token stream decides it without the original request.
- Equality of key texts then implies equality of token sequences for every
  tier, so `session_ambiguous` is not needed for this case. Other reasons
  #1284 sets it (if any remain after the port) keep their behaviour.

Keys for prompts without untrusted spellings are byte-identical to today's,
so existing checkpoints keep hitting.

## D3. Proof obligations

- Model-less: unit tests for the escape map (injective, round trip from
  tokens equals from renderer) on a corpus with each control spelling in
  user, tool and reasoning text, plus `0x1B` in client text.
- `92`'s render corpus: unchanged output for every case without control
  spellings.
- Live (Q4): `tests/test_qwen4_checkpoint_replay.py`; the `160` workload
  with one tool result containing `<|im_end|>`: cached-token counts equal to
  the same workload without the spelling, and byte-identical responses
  between two runs.
- Parity and `ab_bench.py --bitwise` as guards (the CLI path is untouched).

## Risks

- A tier that builds its key from a path D2 missed would miss (slow, not
  wrong) or, worse, match wrongly. The workload and the replay test cover
  each tier; a review lists every key builder (`rg` on the tier names).
- Child-only code in a path upstream changes often: keep it in one helper
  with one marker.
