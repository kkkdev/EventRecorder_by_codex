"""合成データだけで公開検査の検出・履歴網羅・非出力を確認する。"""
import contextlib
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import verify_publication as verify


class PublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = Path(__file__).resolve().parent.parent / ".build" / "publication-tests"
        cls.scratch.mkdir(parents=True, exist_ok=True)

    def test_tokens_and_private_paths(self):
        samples = {
            "github-token": "ghp_" + "A" * 36,
            "aws-key": "AK" + "IA" + "A" * 16,
            "google-key": "AI" + "za" + "A" * 35,
            "slack-token": "xo" + "xb-" + "A" * 32,
            "openai-token": "s" + "k-proj-" + "A" * 32,
            "private-key": "-----BEGIN " + "PRIVATE KEY-----",
            "jwt": "ey" + "J" + "A" * 10 + "." + "A" * 10 + "." + "A" * 10,
            "credential-url": "https://" + "user:password@host.invalid",
            "secret-assignment": 'password = "' + 'synthetic-secret"',
            "personal-email": "someone@" + "private.test",
            "local-user-path": "/Users/" + "private-person/work/source.swift",
            "real-session-id": "session_" + "20200101_120000",
            "private-network": "192." + "168.1.23",
            "meeting-url": "https://meet.google.com/" + "abc-defg-hij",
        }
        for category, sample in samples.items():
            with self.subTest(category=category):
                self.assertIn(category, verify.scan_text(sample))

    def test_public_examples(self):
        self.assertEqual(set(), verify.scan_text("https://example.com /Users/example/output " + verify.IDENTITY))
        self.assertEqual(set(), verify.scan_text("session_YYYYMMDD_HHMMSS https://developer.apple.com"))
        self.assertEqual(set(), verify.scan_text("kCVPixelFormatType_32BGRA"))
        self.assertIn("private-identity", verify.scan_text("Synthetic Person", {"Synthetic Person"}))

    def test_scanner_patterns_do_not_flag_themselves(self):
        self.assertEqual(set(), verify.scan_text(Path(verify.__file__).read_text()))

    def test_sensitive_paths_and_fixture(self):
        for path in verify.IGNORE_PROBES:
            if path.startswith("build/"):
                continue  # buildディレクトリはignore側の検査対象。
            with self.subTest(path=path):
                self.assertTrue(verify.private_path(path))
        self.assertFalse(verify.private_path(verify.PUBLIC_PROBES[0]))
        self.assertFalse(verify.private_path(verify.PUBLIC_PROBES[1]))
        self.assertFalse(verify.private_path(verify.PUBLIC_PROBES[2]))

    def test_deleted_secret_remains_in_history(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as directory:
            repo = Path(directory)
            verify.git(repo, "init", "-q")
            verify.git(repo, "config", "user.name", verify.ANONYMOUS_NAME)
            verify.git(repo, "config", "user.email", verify.ANONYMOUS_EMAIL)
            env = os.environ.copy()
            for key in ("AUTHOR", "COMMITTER"):
                env["GIT_" + key + "_NAME"] = verify.ANONYMOUS_NAME
                env["GIT_" + key + "_EMAIL"] = verify.ANONYMOUS_EMAIL
            token = "ghp_" + "Z" * 36
            sample = repo / "example.txt"
            sample.write_text(token)
            verify.git(repo, "add", "example.txt")
            subprocess.run(["git", "-C", directory, "-c", "commit.gpgsign=false", "commit", "-qm", "first"], env=env, check=True)
            sample.write_text("redacted")
            verify.git(repo, "add", "example.txt")
            subprocess.run(["git", "-C", directory, "-c", "commit.gpgsign=false", "commit", "-qm", "second"], env=env, check=True)
            count, blobs, findings = verify.scan_history(repo, "HEAD")
            self.assertEqual(2, count)
            self.assertEqual(2, blobs)
            self.assertIn("github-token", {category for _, category in findings})
            self.assertNotIn(token, repr(findings))

    def test_binary_error_is_redacted_and_fails_closed(self):
        token = "ghp_" + "Z" * 36
        with tempfile.TemporaryDirectory(dir=self.scratch) as directory:
            binary = Path(directory) / "sample"
            binary.write_bytes(b"\xff\0" + token.encode())
            output = io.StringIO()
            with patch("sys.argv", ["verify", "--binary", str(binary)]), contextlib.redirect_stdout(output):
                self.assertEqual(1, verify.main())
            self.assertNotIn(token, output.getvalue())
            with patch("sys.argv", ["verify", "--binary", str(binary) + ".missing"]), contextlib.redirect_stderr(output):
                self.assertEqual(2, verify.main())

    def test_non_anonymous_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as directory:
            repo = Path(directory)
            verify.git(repo, "init", "-q")
            env = os.environ.copy()
            for key in ("AUTHOR", "COMMITTER"):
                env["GIT_" + key + "_NAME"] = "Synthetic Person"
                env["GIT_" + key + "_EMAIL"] = "person@" + "private.test"
            tree = verify.git(repo, "mktree", data=b"").strip().decode()
            commit = subprocess.check_output(["git", "-C", directory, "commit-tree", tree], input=b"test\n", env=env).strip().decode()
            _, _, findings = verify.scan_history(repo, commit)
            self.assertIn("non-anonymous-author", {category for _, category in findings})
            self.assertIn("non-anonymous-committer", {category for _, category in findings})

    def test_same_blob_under_sensitive_filename_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as directory:
            repo = Path(directory)
            verify.git(repo, "init", "-q")
            blob = verify.git(repo, "hash-object", "-w", "--stdin", data=b"synthetic").strip()
            tree = verify.git(repo, "mktree", data=b"100644 blob " + blob + b"\tevents.json\n100644 blob " + blob + b"\tsafe.txt\n").strip().decode()
            env = os.environ.copy()
            for key in ("AUTHOR", "COMMITTER"):
                env["GIT_" + key + "_NAME"] = verify.ANONYMOUS_NAME
                env["GIT_" + key + "_EMAIL"] = verify.ANONYMOUS_EMAIL
            commit = subprocess.check_output(["git", "-C", directory, "commit-tree", tree], input=b"test\n", env=env).strip().decode()
            _, blobs, findings = verify.scan_history(repo, commit)
            self.assertEqual(1, blobs)
            self.assertIn("sensitive-path", {category for _, category in findings})


if __name__ == "__main__":
    unittest.main()
