#!/usr/bin/env python3
"""Offline checks for the single-model downloader."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
Q2 = "Qwen3.8-Flash-Next-Q2.gguf"
Q4 = "Qwen3.8-Flash-Next-Q4.gguf"
VISION = "mmproj-Qwen3.8-Flash-Next-Q8_0.gguf"
ARTIFACTS = {
    Q2: (147207127040, "b1b93fa69aca5f187b0fb813aca8f3ec1beb5cf8cf0bd38cf041b93e0b6ccac9"),
    Q4: (177280286720, "680944460a8cbe93ba8b6d7b6107213ffb7e22320bd913000e563ca0a0f25a8a"),
}


def payload(name):
    return (name + "\n").encode()


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "source tree"
        self.root.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.out = self.root / "gguf files"
        self.script = self.root / "download.sh"
        text = (ROOT / "download.sh").read_text()
        for name, (size, sha) in ARTIFACTS.items():
            data = payload(name)
            text = text.replace(str(size), str(len(data)))
            text = text.replace(sha, hashlib.sha256(data).hexdigest())
        self.script.write_text(text)
        hf = self.bin / "hf"
        hf.write_text("""#!/usr/bin/env python3
from pathlib import Path
import sys
args = sys.argv[1:]
assert args[:2] == ['download', ('ggml-org/Qwen3.8-Flash-Next-GGUF' if args[2].startswith('mmproj') else 'antirez/qwen3.8-flash-next-gguf')]
out = Path(args[args.index('--local-dir') + 1])
out.mkdir(parents=True, exist_ok=True)
(out / args[2]).write_bytes((args[2] + '\\n').encode())
""")
        hf.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root / "home"), HF_TOKEN="",
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        DS4_GGUF_DIR=str(self.out))

    def run_download(self, target, ok=True):
        result = subprocess.run(["sh", str(self.script), target], env=self.env,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_models_are_verified_and_linked(self):
        for target, name in (("q2", Q2), ("q4", Q4)):
            self.assertIn("Verifying SHA-256", self.run_download(target))
            self.assertEqual((self.root / "qwen3.8-flash-next.gguf").resolve(), (self.out / name).resolve())
            self.assertIn("Already downloaded", self.run_download(target))

    def test_corrupt_model_is_rejected(self):
        self.out.mkdir()
        ((self.out / Q2).resolve()).write_bytes(b"bad")
        self.assertIn("Incorrect file size", self.run_download("q2", ok=False))
        self.assertFalse((self.root / "qwen3.8-flash-next.gguf").exists())

    def test_vision_does_not_replace_model_link(self):
        self.run_download("q2")
        linked = (self.root / "qwen3.8-flash-next.gguf").resolve()
        self.run_download("vision")
        self.assertEqual((self.root / "qwen3.8-flash-next.gguf").resolve(), linked)
        self.assertTrue((self.out / VISION).is_file())

    def test_help_and_invalid_target(self):
        help_text = self.run_download("--help")
        self.assertIn("q2", help_text)
        self.assertIn("q4", help_text)
        self.assertIn("vision", help_text)
        self.assertIn("Unknown component", self.run_download("other", ok=False))


if __name__ == "__main__":
    unittest.main()
