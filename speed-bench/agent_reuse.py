#!/usr/bin/env python3
"""Agent KV-reuse workload for sf-q3-8flash-server.

Plays a fixed agent-shaped script against a server it starts itself, and
reports for every request how much of the prompt the server took from a cache
and how much it had to prefill.  It exists to judge cache-tier changes on the
shapes coding agents produce, not on the authors' own workflows:

  a.tool1-5     OpenAI chat tool loop of five calls on a long task (conv A);
                the client does not send reasoning back
  a.resp1-3     the same task continued through /v1/responses: a follow-up,
                its tool output, then a user turn after the final answer
  b.tool1-3     a second conversation (conv B) whose client echoes
                reasoning_content; it evicts A from the live session
  side          a short side request ("Say hi.") with the same system prompt
  a.return1     back to A through /v1/responses; B, which shares the system
                prompt and tools with A, is the live session it displaces
  b.return1     back to B, which A evicted in turn
  (restart)     the server stops (shutdown store) and starts again
  a.return2     back to A from disk
  b.return2     back to B from disk

Both conversations share the system prompt and the tool catalogue, as two
tasks of one agent do.  Tool results are fixed slices of --doc-file chosen by
conversation and step, never by model output, so the prompts depend only on
the model's own answers.

Each run uses temperature 0 and a fixed seed, so two builds must return the
same bytes for every request: that is the correctness gate.  A build that
changes only cache reuse keeps the responses identical and changes the
cached/prefilled counts and the wall time.

  python3 speed-bench/agent_reuse.py --server-bin ./sf-q3-8flash-server \\
      --model qwen3.8-flash-next.gguf --out base.json
  python3 speed-bench/agent_reuse.py --compare base.json cand.json

The server gets --kv-disk-dir in a fresh temporary directory (deleted at the
end unless --keep) and a small --kv-disk-space-mb, so eviction happens within
the script.  Extra server flags go through --server-arg, once per flag
(for example --server-arg=--mtp).  Only the standard library is used.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

SYSTEM = (
    "You are a careful code-review agent. Work only through the tools you are "
    "given, one step at a time, and keep answers short."
)

TOOLS = [
    {"name": "read_section",
     "description": "Read one numbered section of the working document.",
     "parameters": {"type": "object",
                    "properties": {"section": {"type": "integer"}},
                    "required": ["section"]}},
    {"name": "grep",
     "description": "Search the working document for a phrase.",
     "parameters": {"type": "object",
                    "properties": {"pattern": {"type": "string"}},
                    "required": ["pattern"]}},
]

NUDGE = "Continue: call one tool for the next step."


def chat_tools():
    return [{"type": "function", "function": t} for t in TOOLS]


def responses_tools():
    return [dict(type="function", **t) for t in TOOLS]


class Conv:
    """Client-side history in OpenAI chat form; `echo` sends reasoning back."""

    def __init__(self, name, doc, task, echo):
        self.name = name
        self.doc = doc
        self.echo = echo
        self.step = 0
        self.messages = [{"role": "system", "content": SYSTEM},
                         {"role": "user", "content": task}]

    def tool_result(self, call):
        # A fixed slice of the document per (conversation, step): the result
        # never depends on the model's arguments, so prompts stay comparable.
        self.step += 1
        size = 3000
        start = (self.step * 7919 + len(self.name) * 104729) % max(1, len(self.doc) - size)
        return f"[{call['name']} #{self.step}]\n" + self.doc[start:start + size]

    def add_answer(self, answer):
        msg = {"role": "assistant", "content": answer["content"]}
        if self.echo and answer["reasoning"]:
            msg["reasoning_content"] = answer["reasoning"]
        if answer["calls"]:
            msg["tool_calls"] = [
                {"id": c["id"], "type": "function",
                 "function": {"name": c["name"], "arguments": c["arguments"]}}
                for c in answer["calls"]]
        self.messages.append(msg)
        for c in answer["calls"]:
            self.messages.append({"role": "tool", "tool_call_id": c["id"],
                                  "content": self.tool_result(c)})


def responses_input(messages):
    """The chat history as Responses input items, in the same order."""
    items = []
    for m in messages:
        if m["role"] == "tool":
            items.append({"type": "function_call_output",
                          "call_id": m["tool_call_id"], "output": m["content"]})
            continue
        if m["role"] != "assistant" or m.get("content"):
            items.append({"type": "message", "role": m["role"],
                          "content": m.get("content") or ""})
        for c in m.get("tool_calls") or []:
            items.append({"type": "function_call", "call_id": c["id"],
                          "name": c["function"]["name"],
                          "arguments": c["function"]["arguments"]})
    return items


def response_digest(answer):
    """Hash of what the model produced; server-chosen ids are excluded."""
    body = {"content": answer["content"], "reasoning": answer["reasoning"],
            "calls": [[c["name"], c["arguments"]] for c in answer["calls"]],
            "finish": answer["finish"]}
    return hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()


def post(url, payload, timeout):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"},
                                 method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def parse_chat(body):
    choice = body["choices"][0]
    msg = choice.get("message") or {}
    usage = body.get("usage") or {}
    calls = [{"id": c.get("id") or "", "name": c["function"]["name"],
              "arguments": c["function"].get("arguments") or "{}"}
             for c in msg.get("tool_calls") or []]
    return ({"content": msg.get("content") or "",
             "reasoning": msg.get("reasoning_content") or "",
             "calls": calls, "finish": choice.get("finish_reason") or ""},
            usage.get("prompt_tokens", 0),
            (usage.get("prompt_tokens_details") or {}).get("cached_tokens", 0))


def parse_responses(body):
    content, reasoning, calls = [], [], []
    for item in body.get("output") or []:
        kind = item.get("type")
        if kind == "message":
            content += [p.get("text", "") for p in item.get("content") or []]
        elif kind == "reasoning":
            for part in (item.get("summary") or []) + (item.get("content") or []):
                reasoning.append(part.get("text", ""))
        elif kind == "function_call":
            calls.append({"id": item.get("call_id") or "", "name": item["name"],
                          "arguments": item.get("arguments") or "{}"})
    usage = body.get("usage") or {}
    finish = body.get("status") or ""
    if body.get("incomplete_details"):
        finish += ":" + str(body["incomplete_details"].get("reason"))
    return ({"content": "".join(content), "reasoning": "\n".join(reasoning),
             "calls": calls, "finish": finish},
            usage.get("input_tokens", 0),
            (usage.get("input_tokens_details") or {}).get("cached_tokens", 0))


class Server:
    def __init__(self, args, workdir):
        self.args = args
        self.cmd = [args.server_bin, "-m", args.model, "--port", str(args.port),
                    "--ctx", str(args.ctx),
                    "--kv-disk-dir", os.path.join(workdir, "kv"),
                    "--kv-disk-space-mb", str(args.kv_disk_space_mb)]
        self.cmd += args.server_arg
        self.log_path = os.path.join(workdir, "server.log")
        self.proc = None

    def start(self):
        log = open(self.log_path, "ab")
        self.proc = subprocess.Popen(self.cmd, stdout=log, stderr=subprocess.STDOUT)
        log.close()
        url = f"http://127.0.0.1:{self.args.port}/v1/models"
        deadline = time.monotonic() + self.args.ready_timeout
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"server exited with {self.proc.returncode}; see {self.log_path}")
            try:
                with urllib.request.urlopen(url, timeout=5):
                    return
            except (urllib.error.URLError, OSError):
                time.sleep(2)
        raise RuntimeError(f"server not ready after {self.args.ready_timeout}s; see {self.log_path}")

    def stop(self):
        # SIGTERM lets the server write its shutdown KV checkpoint.
        if not self.proc or self.proc.poll() is not None:
            return
        self.proc.terminate()
        try:
            self.proc.wait(timeout=600)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


class Runner:
    def __init__(self, args):
        self.args = args
        self.base = f"http://127.0.0.1:{args.port}/v1"
        self.rows = []

    def common(self):
        return {"model": "sf-q3-8flash", "temperature": 0.0, "seed": self.args.seed,
                "max_tokens": self.args.max_tokens, "stream": False}

    def record(self, label, api, answer, prompt, cached, wall):
        row = {"label": label, "api": api, "prompt_tokens": prompt,
               "cached_tokens": cached, "prefilled": prompt - cached,
               "wall_s": round(wall, 3), "finish": answer["finish"],
               "digest": response_digest(answer), "response": answer}
        self.rows.append(row)
        print(f"{label:<10} {api:<9} prompt={prompt:>7} cached={cached:>7} "
              f"prefilled={prompt - cached:>7} wall={wall:8.2f}s "
              f"finish={answer['finish']:<12} resp={row['digest'][:12]}", flush=True)

    def chat(self, label, conv, user=None):
        if user is not None:
            conv.messages.append({"role": "user", "content": user})
        elif conv.messages[-1]["role"] == "assistant":
            conv.messages.append({"role": "user", "content": NUDGE})
        payload = dict(self.common(), messages=conv.messages, tools=chat_tools())
        if self.args.reasoning_effort:
            payload["reasoning_effort"] = self.args.reasoning_effort
        t0 = time.perf_counter()
        answer, prompt, cached = parse_chat(post(self.base + "/chat/completions", payload,
                                                 self.args.request_timeout))
        self.record(label, "chat", answer, prompt, cached, time.perf_counter() - t0)
        conv.add_answer(answer)

    def responses(self, label, conv, user=None):
        if user is not None:
            conv.messages.append({"role": "user", "content": user})
        elif conv.messages[-1]["role"] == "assistant":
            conv.messages.append({"role": "user", "content": NUDGE})
        payload = self.common()
        payload.pop("max_tokens")
        payload.update(input=responses_input(conv.messages), tools=responses_tools(),
                       max_output_tokens=self.args.max_tokens, store=False)
        if self.args.reasoning_effort:
            payload["reasoning"] = {"effort": self.args.reasoning_effort}
        t0 = time.perf_counter()
        answer, prompt, cached = parse_responses(post(self.base + "/responses", payload,
                                                      self.args.request_timeout))
        self.record(label, "responses", answer, prompt, cached, time.perf_counter() - t0)
        conv.add_answer(answer)


def run(args):
    with open(args.doc_file, encoding="utf-8") as f:
        text = f.read()
    doc_a = text[:args.doc_chars]
    doc_b = text[len(text) // 2:len(text) // 2 + args.doc_chars // 2]
    a = Conv("a", doc_a, "Working document:\n\n" + doc_a +
             "\n\nTask: find where the plot turns. Read sections and grep as needed.",
             echo=False)
    b = Conv("b", doc_b, "Working document:\n\n" + doc_b +
             "\n\nTask: list the named characters. Read sections and grep as needed.",
             echo=True)

    workdir = tempfile.mkdtemp(prefix="agent_reuse_")
    server = Server(args, workdir)
    runner = Runner(args)
    print(f"workdir {workdir}\nserver  {' '.join(server.cmd)}", flush=True)
    try:
        server.start()
        for i in range(1, 6):
            runner.chat(f"a.tool{i}", a)
        runner.responses("a.resp1", a, "Now grep for the first named place.")
        runner.responses("a.resp2", a)
        runner.responses("a.resp3", a, "Give the answer in one line.")
        for i in range(1, 4):
            runner.chat(f"b.tool{i}", b)
        side = Conv("side", "", "Say hi.", echo=False)
        runner.chat("side", side)
        runner.responses("a.return1", a, "One more check: read the next section.")
        runner.chat("b.return1", b, "One more check: read the next section.")
        server.stop()
        print("(restart)", flush=True)
        server.start()
        runner.chat("a.return2", a, "Last step: summarize your findings.")
        runner.chat("b.return2", b, "Last step: summarize your findings.")
    finally:
        server.stop()
        if args.keep:
            print(f"kept {workdir}")
        else:
            shutil.rmtree(workdir, ignore_errors=True)

    rows = runner.rows
    print(f"total     prompt={sum(r['prompt_tokens'] for r in rows)} "
          f"cached={sum(r['cached_tokens'] for r in rows)} "
          f"prefilled={sum(r['prefilled'] for r in rows)} "
          f"wall={sum(r['wall_s'] for r in rows):.2f}s")
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump({"server": server.cmd, "requests": rows}, f, indent=1)
            f.write("\n")


def compare(path_a, path_b):
    """Return 0 when every response is byte-identical; print the cache deltas."""
    with open(path_a, encoding="utf-8") as f:
        rows_a = json.load(f)["requests"]
    with open(path_b, encoding="utf-8") as f:
        rows_b = json.load(f)["requests"]
    differ = 0
    if [r["label"] for r in rows_a] != [r["label"] for r in rows_b]:
        print("request lists differ")
        return 1
    for ra, rb in zip(rows_a, rows_b):
        same = ra["digest"] == rb["digest"]
        differ += not same
        print(f"{ra['label']:<10} {'same' if same else 'DIFFERENT':<9} "
              f"cached {ra['cached_tokens']:>7} -> {rb['cached_tokens']:>7}  "
              f"wall {ra['wall_s']:8.2f}s -> {rb['wall_s']:8.2f}s")
    print(f"responses: {'identical' if not differ else f'{differ} differ'}")
    return 1 if differ else 0


def self_test():
    conv = Conv("t", "x" * 4000, "task", echo=True)
    answer = {"content": "", "reasoning": "think", "finish": "tool_calls",
              "calls": [{"id": "call_1", "name": "grep", "arguments": "{\"pattern\":\"a\"}"}]}
    conv.add_answer(answer)
    assert conv.messages[2]["reasoning_content"] == "think"
    assert conv.messages[3]["tool_call_id"] == "call_1"
    items = responses_input(conv.messages)
    assert [i["type"] for i in items] == ["message", "message", "function_call",
                                         "function_call_output"]
    renamed = dict(answer, calls=[dict(answer["calls"][0], id="call_2")])
    assert response_digest(answer) == response_digest(renamed)
    body = {"status": "completed", "usage": {"input_tokens": 9,
            "input_tokens_details": {"cached_tokens": 4}},
            "output": [{"type": "function_call", "call_id": "c", "name": "grep",
                        "arguments": "{}"}]}
    parsed, prompt, cached = parse_responses(body)
    assert parsed["calls"][0]["id"] == "c" and (prompt, cached) == (9, 4)
    print("self-test ok")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--server-bin", help="sf-q3-8flash-server binary to test")
    p.add_argument("--model", help="GGUF path passed to the server")
    p.add_argument("--port", type=int, default=18912)
    p.add_argument("--ctx", type=int, default=131072)
    p.add_argument("--kv-disk-space-mb", type=int, default=4096,
                   help="disk KV budget; small enough that the script evicts")
    p.add_argument("--server-arg", action="append", default=[],
                   help="extra server flag, repeatable (use --server-arg=--flag)")
    p.add_argument("--doc-file", default=os.path.join(here, "promessi_sposi.txt"))
    p.add_argument("--doc-chars", type=int, default=120000,
                   help="conversation A's document size; B gets half")
    p.add_argument("--max-tokens", type=int, default=1024)
    p.add_argument("--reasoning-effort", default="low",
                   help="sent with every request; empty for the server default")
    p.add_argument("--seed", type=int, default=1234)
    p.add_argument("--ready-timeout", type=int, default=1200)
    p.add_argument("--request-timeout", type=int, default=3600)
    p.add_argument("--out", help="write per-request results as JSON")
    p.add_argument("--keep", action="store_true", help="keep the temp dir (KV files, server.log)")
    p.add_argument("--compare", nargs=2, metavar=("BASE", "CAND"),
                   help="compare two --out files instead of running")
    p.add_argument("--self-test", action="store_true",
                   help="check the request/response plumbing without a server")
    args = p.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.compare:
        return compare(*args.compare)
    if not args.server_bin or not args.model:
        p.error("--server-bin and --model are required to run the workload")
    run(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
