#!/usr/bin/env python3
"""What a prompt-lookup draft would have got right, offline (change 187, step 0).

usage: lookup_oracle.py VOCAB.txt [--kv DIR]... [--ids FILE]...
       lookup_oracle.py --self-test

  VOCAB.txt   the vocabulary as text (tests/test_tokenizer --export-vocab MODEL.gguf VOCAB.txt)
  --kv DIR    server disk-KV checkpoints, opened read only: the header, the key-text length
              and the payload's token list (layout of ds4_kvstore_read_header and
              qwen4_session_save_payload). Only counts are printed.
  --ids FILE  one conversation per line as space-separated token ids: the rendered chat
              prompt including the assistant turns (tests/test_tokenizer --dump-ids).

No model is opened. For every output position i of every assistant turn (context = all tokens
before i), and for k = 2..8: j = end of the last earlier occurrence of tokens[i-k:i]; the
lookup proposes tokens[j], tokens[j+1], ...; they are compared with tokens[i], tokens[i+1], ...
A turn is a file edit, a tool call or a prose answer by the functions it calls; each is also
reported for the part after </think>. Conversations that are prefixes of a longer one, and
turns already seen, are counted once.
"""
import hashlib
import os
import re
import struct
import sys
from collections import defaultdict

KS = range(2, 9)
RUN_BINS = [(0, 0), (1, 1), (2, 2), (3, 3), (4, 7), (8, 15), (16, 10**9)]
RUN_CAP = 64


def load_vocab(path):
    with open(path, 'rb') as f:
        n = int(f.readline())
        return [f.readline().rstrip(b'\n') for _ in range(n)]


def kv_tokens(path):
    """Token ids of one checkpoint, or None."""
    with open(path, 'rb') as f:
        h = f.read(52)
        if len(h) < 52 or h[:3] != b'KVC' or h[3] != 1 or h[20] != 2:
            return None
        ntok = struct.unpack_from('<I', h, 8)[0]
        f.seek(52 + struct.unpack_from('<I', h, 48)[0])
        ph = f.read(13 * 4)
        if len(ph) < 52 or struct.unpack('<13I', ph)[7] != ntok or not 0 < ntok <= 2_000_000:
            return None
        raw = f.read(4 * ntok)
        return list(struct.unpack(f'<{ntok}I', raw)) if len(raw) == 4 * ntok else None


class Stats:
    def __init__(self):
        self.turns = self.out = self.best2 = self.best3 = 0
        self.match = defaultdict(int)                 # k -> positions with a match
        self.right = defaultdict(lambda: [0, 0, 0])   # k -> first 1, 2, 3 looked-up tokens right
        self.runs = defaultdict(lambda: [0] * len(RUN_BINS))


def classify(text):
    calls = re.findall(r'<tool_call>\s*<function=([^>\s]+)', text)
    if not calls:
        return 'prose answers'
    if any(re.search(r'edit|write|replace|patch|create|insert', c, re.I) for c in calls):
        return 'file edits'
    return 'tool calls'


def measure(vocab, convs):
    im_start, im_end = vocab.index(b'<|im_start|>'), vocab.index(b'<|im_end|>')
    think_end = vocab.index(b'</think>') if b'</think>' in vocab else -1
    convs = sorted(convs, key=len, reverse=True)
    lengths = sorted({len(c) for c in convs})
    seen_prefix, seen_turn = set(), set()
    stats = defaultdict(Stats)
    used = 0
    for toks in convs:
        n = len(toks)
        raw = struct.pack(f'<{n}I', *toks)
        h, prev, digests = hashlib.blake2b(digest_size=16), 0, []
        for length in lengths:
            if length > n:
                break
            h.update(raw[4 * prev:4 * length])
            prev = length
            digests.append(h.copy().digest())
        if digests[-1] in seen_prefix:
            continue
        seen_prefix.update(digests)
        used += 1
        # assistant turns: <|im_start|> assistant \n ... <|im_end|>
        turns, i = [], 0
        while i < n:
            if toks[i] == im_start and i + 1 < n and vocab[toks[i + 1]] == b'assistant':
                s = i + 2
                if s < n and vocab[toks[s]].replace(b'\xc4\x8a', b'\n').strip() == b'':
                    s += 1
                e = s
                while e < n and toks[e] != im_end:
                    e += 1
                e = min(e + 1, n)
                turns.append((s, e))
                i = e
            else:
                i += 1
        is_out = bytearray(n)
        for s, e in turns:
            is_out[s:e] = b'\x01' * (e - s)
        # the last end position of every k-gram, and the proposal site at each output position
        last = {k: {} for k in KS}
        prop = {}
        for i in range(n):
            for k in KS:
                if i < k:
                    continue
                key = tuple(toks[i - k:i])
                if is_out[i] and key in last[k]:
                    prop.setdefault(i, {})[k] = last[k][key]
                last[k][key] = i
        hh, done = hashlib.blake2b(digest_size=16), 0
        for s, e in turns:
            hh.update(raw[4 * done:4 * e])
            done = e
            digest = hh.copy().digest()
            if digest in seen_turn:
                continue
            seen_turn.add(digest)
            text = (b''.join(vocab[t] for t in toks[s:e]).decode('utf-8', 'replace')
                    .replace('Ċ', '\n').replace('Ġ', ' '))   # byte-level BPE spelling
            kind = classify(text)
            visible = next((p + 1 for p in range(s, e) if toks[p] == think_end), s)
            for label, a in ((kind, s), (kind + ' (after </think>)', visible)):
                st = stats[label]
                st.turns += 1
                st.out += e - a
                for i in range(a, e):
                    two = three = False
                    for k, j in prop.get(i, {}).items():
                        run = 0
                        while run < RUN_CAP and i + run < e and toks[j + run] == toks[i + run]:
                            run += 1
                        st.match[k] += 1
                        for q in range(3):
                            st.right[k][q] += run > q
                        st.runs[k][next(b for b, (lo, hi) in enumerate(RUN_BINS) if lo <= run <= hi)] += 1
                        two |= run >= 2
                        three |= run >= 3
                    st.best2 += two
                    st.best3 += three
    return stats, used


def report(stats):
    for label in sorted(stats):
        st = stats[label]
        if not st.out:
            continue
        print(f'\n== {label}: {st.turns} turns, {st.out} output tokens')
        print(f'   any k: first two right {100 * st.best2 / st.out:.1f}% of output tokens, '
              f'first three right {100 * st.best3 / st.out:.1f}%')
        print('   k  match%  first  first two  first three (% of output tokens)'
              ' | given a match: 1st 2nd 3rd | run length 0 1 2 3 4-7 8-15 16+ (% of matches)')
        for k in KS:
            m, r = st.match[k], st.right[k]
            runs = ' '.join(f'{100 * x / max(m, 1):.0f}' for x in st.runs[k])
            print(f'   {k}  {100 * m / st.out:5.1f}  {100 * r[0] / st.out:5.1f}  {100 * r[1] / st.out:9.1f}'
                  f'  {100 * r[2] / st.out:11.1f}                     '
                  f'| {100 * r[0] / max(m, 1):3.0f} {100 * r[1] / max(m, 1):3.0f} {100 * r[2] / max(m, 1):3.0f}'
                  f'            | {runs}')


def self_test():
    vocab = [b'<|im_start|>', b'<|im_end|>', b'</think>', b'user', b'assistant', b'\xc4\x8a'] + \
            [b'w%d' % i for i in range(10)]
    text = list(range(6, 12))                                   # six words
    conv = [0, 3, 5] + text + [1, 0, 4, 5] + text + [1]         # the answer repeats the question
    st = measure(vocab, [conv, conv[:9]])[0]['prose answers']   # the second is a prefix: counted once
    # output = six words + <|im_end|>; from the second word on, the 2-token suffix occurred before
    assert (st.turns, st.out, st.match[2]) == (1, 7, 6), (st.turns, st.out, st.match[2])
    assert st.right[2] == [6, 5, 4] and st.runs[2] == [0, 1, 1, 1, 3, 0, 0], (st.right[2], st.runs[2])
    assert st.match[8] == 0 and st.best2 == 5
    print('lookup oracle self-test: ok')


def main():
    if sys.argv[1:] == ['--self-test']:
        return self_test()
    if len(sys.argv) < 4 or len(sys.argv) % 2:
        sys.exit(__doc__)
    vocab, convs, sources = load_vocab(sys.argv[1]), [], defaultdict(int)
    for flag, value in zip(sys.argv[2::2], sys.argv[3::2]):
        if flag == '--kv':
            for name in sorted(os.listdir(value)):
                if name.endswith('.kv'):
                    toks = kv_tokens(os.path.join(value, name))
                    sources['checkpoints' if toks else 'unreadable checkpoints'] += 1
                    if toks:
                        convs.append(toks)
        elif flag == '--ids':
            for line in open(value):
                ids = [int(x) for x in line.split()]
                if ids:
                    convs.append(ids)
                    sources['id lines'] += 1
        else:
            sys.exit(__doc__)
    stats, used = measure(vocab, convs)
    print('sources:', dict(sources))
    print(f'conversations used {used} of {len(convs)} (the rest are prefixes of a longer one)')
    report(stats)


if __name__ == '__main__':
    main()
