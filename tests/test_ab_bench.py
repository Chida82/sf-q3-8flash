import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "ab_bench", Path(__file__).resolve().parents[1] / "speed-bench/ab_bench.py")
ab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ab)

HEADER = "ctx_tokens,prefill_tokens,prefill_tps,gen_tokens,gen_tps,gen_first_ms,gen_steady_tokens,gen_steady_tps,kvcache_bytes\n"
PLAIN_CSV = HEADER + ("8192,8192,1400.00,4,50.00,20.0,3,60.00,0\n"
                      "8704,512,1000.00,4,50.00,20.0,3,30.00,0\n"
                      "10752,2048,1300.00,4,50.00,20.0,3,60.00,0\n")
PLAIN_ERR = ("ds4-bench: gen[ctx=8192] decoded text: \"x\"\n"
             "ds4-bench: gen[ctx=8192] token ids: 1 2 3 4\n"
             "ds4-bench: gen[ctx=8704] token ids: 5 6 7 8\n"
             "ds4-bench: gen[ctx=10752] token ids: 9 10 11 12\n")
MTP_CSV = HEADER + "2048,2048,1400.00,128,70.00,28.0,127,71.00,0\n"
MTP_ERR = ("ds4-bench: gen[ctx=2048] token ids: 1 2 3\n"
           "ds4-bench: mtp[ctx=2048] cycles=70 tokens=128 k1=16/24.00ms k2=50/25.00ms k3=4/36.00ms\n")


def run(build, kind, n, values, warmup=False, tokens=None):
    return {"build": build, "kind": kind, "n": n, "warmup": warmup, "note": "",
            "metrics": {name: values for name in fake_metrics[kind]}, "duration": 10.0,
            "tokens": tokens or {8192: [1, 2, 3]}}


fake_metrics = {"plain": ["decode", "prefill 8192", "prefill +512", "prefill +2048"],
                "mtp-code": ["decode", "tokens/cycle", "prefill 2048", "k1 ms", "k2 ms", "k3 ms"]}


def quads(kind, a_values, b_values):
    runs = [run("A", kind, 0, 1.0, warmup=True), run("B", kind, 0, 1.0, warmup=True)]
    for q, (a1, b1, b2, a2) in enumerate(zip(a_values[::2], b_values[::2], b_values[1::2], a_values[1::2])):
        for i, (build, v) in enumerate((("A", a1), ("B", b1), ("B", b2), ("A", a2))):
            runs.append(run(build, kind, 4 * q + i + 1, v))
    return runs


def dump(path, logits, frontier=16, previous=0):
    values = [float(x) for x in logits]
    argmax = values.index(max(values))
    path.write_text(
        '{"source":"ds4-bench","model":"/m.gguf","backend":"metal","quality":false,"quant_bits":4,'
        f'"prompt_tokens":{frontier},"frontier_tokens":{frontier},"prefill_tokens":{frontier - previous},'
        f'"ctx":32,"vocab":{len(logits)},"argmax_id":{argmax},"argmax_logit":{logits[argmax]},'
        f'"logits":[{",".join(logits)}]}}\n')


class ParseTest(unittest.TestCase):
    def test_plain_run_metrics(self):
        r = ab.parse_run(PLAIN_CSV, PLAIN_ERR, "plain")
        self.assertEqual(r["tokens"][8704], [5, 6, 7, 8])
        m = r["metrics"]
        self.assertEqual((m["prefill 8192"], m["prefill +512"], m["prefill +2048"]), (1400.0, 1000.0, 1300.0))
        # pooled steady decode: 9 tokens over 0.05 + 0.1 + 0.05 s
        self.assertAlmostEqual(m["decode"], 45.0)

    def test_mtp_run_metrics(self):
        m = ab.parse_run(MTP_CSV, MTP_ERR, "mtp-code")["metrics"]
        self.assertAlmostEqual(m["tokens/cycle"], 128 / 70)
        self.assertEqual((m["k1 ms"], m["k2 ms"], m["k3 ms"]), (24.0, 25.0, 36.0))
        self.assertEqual(m["prefill 2048"], 1400.0)

    def test_missing_output_is_a_run_failure(self):
        with self.assertRaises(ab.Stop) as cm:
            ab.parse_run(MTP_CSV, "ds4-bench: gen[ctx=2048] token ids: 1\n", "mtp-code")
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("MTP lines", str(cm.exception))


class VerdictTest(unittest.TestCase):
    def test_pairs_median_and_range(self):
        runs = quads("plain", [100, 100, 100, 100], [101, 103, 102, 110])
        t = next(x for x in ab.verdict(runs, ["plain"]) if x["metric"] == "decode")
        self.assertEqual(t["n"], 4)
        self.assertAlmostEqual(t["ratio"], 1.025)
        self.assertAlmostEqual(t["lo"], 1.01)
        self.assertAlmostEqual(t["hi"], 1.10)

    def test_dropped_pair_leaves_the_other(self):
        runs = quads("plain", [100, 100], [101, 150])
        runs[4]["flag"] = runs[5]["flag"] = "pair dropped"  # (B2, A2)
        t = next(x for x in ab.verdict(runs, ["plain"]) if x["metric"] == "decode")
        self.assertEqual(t["n"], 1)
        self.assertAlmostEqual(t["ratio"], 1.01)

    def test_inconclusive_below_two_pairs(self):
        runs = quads("plain", [], [])  # warm-up only: the budget fitted no quad
        for r in runs:
            r.update(rows={}, mtp={})
        ctx = {"date": "2026-09-24 20:00 UTC", "device": "M5", "mactop": "2", "model": "/m.gguf",
               "model_name": "m.gguf", "env": [], "preheat": 210,
               "elapsed": 1, "budget": 480, "kinds": ["plain"],
               "A": {"path": "a", "commit": "a1", "dirty": False},
               "B": {"path": "b", "commit": "b1", "branch": "perf/x", "dirty": True}}
        text, thin = ab.summary(ctx, runs, ab.verdict(runs, ["plain"]), "PASS", "PASS (tokens)")
        self.assertTrue(thin)
        self.assertIn("INCONCLUSIVE", text)

    def test_record_row_has_fixed_cells(self):
        full = ab.verdict(quads("plain", [1, 1], [1, 1]) + quads("mtp-code", [1, 1], [1, 1]), ["plain", "mtp-code"])
        plain = ab.verdict(quads("plain", [1, 1], [1, 1]), ["plain"])
        cells = [ab.record_row("perf/x", "d", "c", "m", 2, "PASS", t).count("|") for t in (full, plain)]
        self.assertEqual(cells[0], cells[1])
        self.assertEqual(cells[0], ab.record_header().splitlines()[0].count("|"))


class ScheduleTest(unittest.TestCase):
    def test_stops_before_an_overrunning_quad(self):
        clock = [0.0]

        def runner(build, kind, phase):
            clock[0] += 10.0
            return {"build": build, "kind": kind, "phase": phase, "duration": 10.0}

        runs = []
        # warm-up 20 s, one quad predicted at 44 s; a second would end after 104 s
        ab.schedule(["plain"], 95.0, runner, lambda done: None, runs, clock=lambda: clock[0])
        self.assertEqual([r["build"] for r in runs], list("AB") + list("ABBA"))
        self.assertLessEqual(clock[0], 95.0)

    def test_preheats_until_its_deadline(self):
        clock = [0.0]

        def runner(build, kind, phase):
            clock[0] += 10.0
            return {"build": build, "kind": kind, "phase": phase, "duration": 10.0}

        runs = []
        # warm-up ends at 40 s; preheat runs until 60 s, alternating builds on the first kind
        ab.schedule(["mtp-code", "plain"], 120.0, runner, lambda done: None, runs,
                    preheat_until=60.0, clock=lambda: clock[0])
        preheat = [(r["build"], r["kind"]) for r in runs if r["phase"] == "preheat"]
        self.assertEqual(preheat, [("A", "mtp-code"), ("B", "mtp-code")])
        self.assertEqual(runs[6]["phase"], "timed")


class CorrectnessTest(unittest.TestCase):
    def test_token_mismatch_reports_position(self):
        ref = run("A", "plain", 1, 1.0, tokens={8704: [1, 2, 3, 4]})
        bad = run("B", "plain", 2, 1.0, tokens={8704: [1, 2, 9, 4]})
        self.assertEqual(ab.check_tokens(bad, ref), "FAIL: B differs from A: plain, frontier 8704, token index 2")
        self.assertIsNone(ab.check_tokens(ref, ref))

    def test_nondeterministic_baseline(self):
        ref = run("A", "plain", 1, 1.0, tokens={8192: [1, 2]})
        again = run("A", "plain", 5, 1.0, tokens={8192: [1, 2, 3]})
        self.assertIn("baseline is nondeterministic", ab.check_tokens(again, ref))

    def check(self, a_logits, b_logits):
        with tempfile.TemporaryDirectory() as tmp:
            dirs = [Path(tmp) / "A-plain", Path(tmp) / "B-plain"]
            for d, logits in zip(dirs, (a_logits, b_logits)):
                d.mkdir()
                dump(d / "frontier_000016.logits.json", logits)
                dump(d / "frontier_000016.decode.logits.json", logits)
            return ab.check_logits(dirs[0], dirs[1], (16,))

    def test_bitwise_identical(self):
        self.assertIsNone(self.check(["1.00000012", "0.5", "0", "0.25"], ["1.00000012", "0.5", "0", "0.25"]))

    def test_bitwise_one_bit(self):
        problem = self.check(["1.00000012", "0.5", "0", "0.25"], ["1.00000024", "0.5", "0", "0.25"])
        self.assertIn("vocabulary index 0", problem)

    def test_bitwise_signed_zero(self):
        problem = self.check(["1.00000012", "0.5", "0", "0.25"], ["1.00000012", "0.5", "-0", "0.25"])
        self.assertIn("vocabulary index 2", problem)


class EnvironmentTest(unittest.TestCase):
    def test_mactop_stream_and_missing_field(self):
        sample = {"timestamp": "2026-09-24T20:00:00+02:00", "thermal_state": "Nominal",
                  "soc_metrics": {"gpu_freq_mhz": 1500, "gpu_active": 90.0, "gpu_power": 30.0, "gpu_temp": 50.0}}
        text = "[" + json.dumps(sample) + "\n," + json.dumps(sample) + "\n,{\"timest"
        samples = ab.parse_mactop(text)  # a partial last line is tolerated
        self.assertEqual(len(samples), 2)
        self.assertEqual(ab.reading(samples[0])["freq"], 1500)
        del sample["soc_metrics"]["gpu_power"]
        with self.assertRaises(ab.Stop) as cm:
            ab.reading(sample, "2.1.5")
        self.assertIn("mactop 2.1.5 output has no soc_metrics.gpu_power", str(cm.exception))

    @staticmethod
    def readings(freq_temp_state, start=0):
        return [{"time": start + i, "freq": f, "active": 90.0, "power": 30.0, "temp": t, "thermal": st}
                for i, (f, t, st) in enumerate(freq_temp_state)]

    def test_disturbed_run_drops_its_pair(self):
        freqs = (1378, 1382, 1354, 1298, 1244, 1221, 1262, 932)  # third A/A: run 8 hit a disturbance
        timed = [{"kind": "plain", "build": b, "n": i + 1, "freq": f, "note": ""}
                 for i, (b, f) in enumerate(zip("ABBAABBA", freqs))]
        ab.drop_disturbed(timed, ["plain"], 0.90)
        self.assertEqual([bool(r.get("flag")) for r in timed], [False] * 6 + [True, True])
        self.assertIn("run 8 at 932 MHz", timed[6]["flag"])
        plateau = [{"kind": "plain", "build": b, "n": i + 1, "freq": f, "note": ""}
                   for i, (b, f) in enumerate(zip("ABBA", (1207, 1304, 1266, 1350)))]
        ab.drop_disturbed(plateau, ["plain"], 0.90)
        self.assertFalse(any(r.get("flag") for r in plateau))

    def test_judge_marks_runs_without_active_samples(self):
        runs = [{"start": 0, "end": 3, "note": ""}, {"start": 10, "end": 13, "note": ""}]
        readings = self.readings([(1200, 70.0, "Heavy")] * 4) + self.readings([(1200, 70.0, "Heavy")], start=11)
        ab.judge(runs, readings)
        self.assertEqual(runs[0]["freq"], 1200)
        self.assertEqual(runs[0]["thermal"], ["Heavy"])
        self.assertIn("unjudged", runs[1]["note"])

    def test_inherited_ds4_variables_are_dropped(self):
        env = ab.child_env(["DS4_QWEN4_MTP_DEPTH=3"], {"DS4_METAL_QWEN4_SOURCE": "x.metal", "PATH": "/bin"})
        self.assertEqual(env, {"PATH": "/bin", "DS4_QWEN4_MTP_DEPTH": "3"})


if __name__ == "__main__":
    unittest.main()
