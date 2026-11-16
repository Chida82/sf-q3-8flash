#!/usr/bin/env python3
"""Distribution check for exact-sampling MTP (openspec 150, design D2).

Runs the same prompt at temperature 1.0 with --mtp --mtp-exact-sampling on two
built trees (A and B), N seeds each, alternating A and B per seed, and keeps the
first K characters of each answer.  The default prompt asks for an 8-digit
number, so every position is one digit token with a spread distribution (the
procedure #1185 reports: paired 8-digit samples, paired permutation test).

Per position it computes the chi-square statistic of the 2 x C table of
characters, and a paired permutation p value: each permutation swaps the A and
B samples of a seed with probability 1/2.  Per-seed outputs are expected to
differ between builds (the RNG sequence moved); only the distributions must
agree.  Fails when any position has p < --alpha (default 0.01).
"""
import argparse
import collections
import json
import os
import random
import subprocess
import sys

PROMPT = "Write a random 8-digit number. Reply with the number only."


def sample(tree, model, prompt, seed, n_predict, env_extra):
    cmd = [os.path.join(tree, "sf-q3-8flash"), "-m", model, "--nothink", "--mtp",
           "--mtp-exact-sampling", "--temp", "1.0", "--seed", str(seed),
           "-n", str(n_predict), "-p", prompt]
    env = dict(os.environ, **env_extra)
    r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=300)
    if r.returncode != 0:
        sys.exit(f"{tree}: seed {seed} failed: {r.stderr[-400:]}")
    return r.stdout.strip()


def chi2(a, b):
    ca, cb = collections.Counter(a), collections.Counter(b)
    na, nb = len(a), len(b)
    s = 0.0
    for c in ca.keys() | cb.keys():
        oa, ob = ca[c], cb[c]
        tot = oa + ob
        ea, eb = tot * na / (na + nb), tot * nb / (na + nb)
        s += (oa - ea) ** 2 / ea + (ob - eb) ** 2 / eb
    return s


def paired_perm_p(a, b, perms, rng):
    obs = chi2(a, b)
    hits = 0
    for _ in range(perms):
        pa, pb = [], []
        for x, y in zip(a, b):
            if rng.random() < 0.5:
                x, y = y, x
            pa.append(x)
            pb.append(y)
        if chi2(pa, pb) >= obs - 1e-12:
            hits += 1
    return (hits + 1) / (perms + 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True)
    ap.add_argument("--a", required=True, help="reference tree (built)")
    ap.add_argument("--b", required=True, help="candidate tree (built)")
    ap.add_argument("--n", type=int, default=500, help="seeds per build")
    ap.add_argument("--k", type=int, default=8, help="positions compared")
    ap.add_argument("--perms", type=int, default=2000)
    ap.add_argument("--alpha", type=float, default=0.01)
    ap.add_argument("--prompt", default=PROMPT)
    ap.add_argument("--depth", choices=["auto", "2", "3"], default="auto",
                    help="DS4_QWEN4_MTP_DEPTH for both builds")
    ap.add_argument("--out", help="write samples and p values as JSON")
    args = ap.parse_args()

    env_extra = {} if args.depth == "auto" else {"DS4_QWEN4_MTP_DEPTH": args.depth}
    outs = {"a": [], "b": []}
    for i in range(args.n):
        seed = 1000 + i
        for key, tree in (("a", args.a), ("b", args.b)) if i % 2 == 0 else (("b", args.b), ("a", args.a)):
            outs[key].append(sample(tree, args.model, args.prompt, seed, args.k + 4, env_extra))
        if (i + 1) % 50 == 0:
            print(f"  {i + 1}/{args.n} seeds", flush=True)

    def pos(texts, k):
        return [(t[k] if k < len(t) else "<end>") for t in texts]

    rng = random.Random(150)
    pvals = []
    for k in range(args.k):
        a, b = pos(outs["a"], k), pos(outs["b"], k)
        p = paired_perm_p(a, b, args.perms, rng)
        pvals.append(p)
        print(f"position {k}: chi2 {chi2(a, b):7.2f}  p {p:.3f}")
    worst = min(pvals)
    if args.out:
        with open(args.out, "w") as f:
            json.dump({"n": args.n, "k": args.k, "perms": args.perms, "prompt": args.prompt,
                       "depth": args.depth, "p": pvals, "a": outs["a"], "b": outs["b"]}, f)
    if worst < args.alpha:
        print(f"FAIL: N={args.n} K={args.k}: min p {worst:.3f} < {args.alpha}")
        return 1
    print(f"PASS: N={args.n} K={args.k}: min p {worst:.3f} >= {args.alpha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
