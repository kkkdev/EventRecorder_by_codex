#!/usr/bin/env python3
"""公開履歴と配布バイナリのローカル検査。検出値は表示しない。"""
import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

ANONYMOUS_NAME = "EventRecorder contributors"
ANONYMOUS_EMAIL = "contributors@eventrecorder.invalid"
IDENTITY = f"{ANONYMOUS_NAME} <{ANONYMOUS_EMAIL}>"
PATTERNS = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "github-token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    "aws-key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "google-key": re.compile(r"\bAIza[A-Za-z0-9_-]{35}\b"),
    "slack-token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{16,}\b"),
    "openai-token": re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b"),
    "jwt": re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"),
    "credential-url": re.compile(r"https?://[^\s/:]+:[^\s/@]+@"),
    "secret-assignment": re.compile(
        r"(?i)\b(?:password|api[_-]?key|client[_-]?secret|access[_-]?token)\s*[:=]\s*[\"'][^\"'\n]{8,}[\"']"
    ),
    "private-network": re.compile(r"\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b"),
    "meeting-url": re.compile(r"https?://(?:meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}|[^/\s]*zoom\.us/[jw]/\d+|teams\.microsoft\.com/l/meetup-join/[^\s\"<>]+)"),
    "real-session-id": re.compile(r"\bsession_\d{8}_\d{6}\b"),
}
USER_PATH = re.compile(r"/Users/([\w.-]+)")
EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
PRIVATE_EXTENSIONS = {".caf", ".mp3", ".wav", ".aiff", ".mp4", ".mov", ".key", ".pem", ".p12", ".pfx"}
IGNORE_PROBES = (
    "recordings/session_example/manifest.json", "session_example/images/img_000001.jpg",
    "recording_tmp.caf", "recording.mp3", "recording.wav", "recording.aiff",
    "recording.mp4", "recording.mov", "events.json", "certificate.p12",
    "certificate.pfx", "ssh.key", "certificate.pem", "captures/capture.png",
    "screenshots/capture.jpg", "raw/report.json", "diagnostics/report.json",
    ".env", "debug.log", "build/EventRecorder.app/Contents/MacOS/EventRecorder",
)
PUBLIC_PROBES = ("scripts/fixtures/no_audio_session/manifest.json", "docs/images/example.png", ".env.example")


def git(repo, *args, data=None):
    return subprocess.run(["git", "-C", str(repo), *args], input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def private_terms(source):
    """元履歴の名前・メールをメモリ内だけで利用する。"""
    terms = set()
    if source:
        for row in git(source, "log", "--all", "--format=%an%x00%ae%x00%cn%x00%ce").decode().splitlines():
            for value in row.split("\0"):
                if value not in (ANONYMOUS_NAME, ANONYMOUS_EMAIL):
                    terms.add(value)
                    if "@" not in value:
                        terms.update(part for part in re.split(r"[\s._-]+", value) if len(part) >= 4)
    # 短い共通語のusernameは誤検知し得るため、絶対path検査へ任せる。
    username = Path.home().name
    if len(username) >= 6 and ("." in username or "_" in username):
        terms.add(username)
    return terms


def scan_text(text, terms=()):
    findings = {label for label, pattern in PATTERNS.items() if pattern.search(text)}
    if any(match.group(1) != "example" for match in USER_PATH.finditer(text)):
        findings.add("local-user-path")
    for match in EMAIL.finditer(text):
        domain = match.group().rsplit("@", 1)[1].lower()
        if domain not in {"example.com", "example.net", "example.org"} and not domain.endswith(".invalid"):
            findings.add("personal-email")
    if any(re.search(r"(?<![\w])" + re.escape(term) + r"(?![\w])", text, re.IGNORECASE) for term in terms):
        findings.add("private-identity")
    return findings


def private_path(path):
    parts = PurePosixPath(path).parts
    return (PurePosixPath(path).suffix.lower() in PRIVATE_EXTENSIONS
            or any(part.startswith("session_") for part in parts)
            or any(part in {"recordings", "captures", "screenshots", "raw", "diagnostics", ".git"} for part in parts)
            or PurePosixPath(path).name == "events.json"
            or (PurePosixPath(path).name.startswith(".env") and PurePosixPath(path).name != ".env.example")
            or PurePosixPath(path).suffix.lower() == ".log")


def scan_history(repo, ref, terms=()):
    if ref.startswith("-"):
        raise ValueError("Invalid ref")
    resolved = git(repo, "rev-parse", "--verify", ref + "^{commit}").decode().strip()
    commits = git(repo, "rev-list", resolved).decode().splitlines()
    findings = []
    objects = set()
    for commit in commits:
        raw = git(repo, "cat-file", "commit", commit).decode("utf-8")
        headers = raw.split("\n\n", 1)[0].splitlines()
        for key in ("author", "committer"):
            lines = [line for line in headers if line.startswith(key + " ")]
            if len(lines) != 1 or not re.fullmatch(key + " " + re.escape(IDENTITY) + r" \d+ [+-]\d{4}", lines[0]):
                findings.append((commit[:12], "non-anonymous-" + key))
        for category in scan_text(raw, terms):
            findings.append((commit[:12], category))
        # 各treeの全pathを検査。rev-listのpath表示は複数pathのblobを網羅しない。
        for entry in git(repo, "ls-tree", "-r", "-z", commit).split(b"\0"):
            if not entry:
                continue
            info, path = entry.split(b"\t", 1)
            _, kind, oid = info.split()
            path_text = path.decode("utf-8")
            if kind != b"blob":
                findings.append((commit[:12], "unsupported-object"))
                continue
            objects.add(oid.decode())
            if private_path(path_text) or scan_text(path_text, terms):
                findings.append((oid.decode()[:12], "sensitive-path"))
    for oid in sorted(objects):
        raw = git(repo, "cat-file", "blob", oid)
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            findings.append((oid[:12], "binary-source-artifact"))
            continue
        if b"\0" in raw:
            findings.append((oid[:12], "binary-source-artifact"))
        for category in scan_text(text, terms):
            findings.append((oid[:12], category))
    return len(commits), len(objects), sorted(set(findings))


def check_ignores(repo):
    failures = []
    for path, expected in [(p, True) for p in IGNORE_PROBES] + [(p, False) for p in PUBLIC_PROBES]:
        result = subprocess.run(["git", "-C", str(repo), "check-ignore", "--no-index", "-q", "--", path])
        if result.returncode not in (0, 1) or (result.returncode == 0) != expected:
            failures.append("ignore-rule")
    fixture = "scripts/fixtures/no_audio_session/manifest.json"
    if subprocess.run(["git", "-C", str(repo), "ls-files", "--error-unmatch", "--", fixture],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        failures.append("missing-synthetic-fixture")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--ref", default="HEAD", help="公開する単一ref（旧refも含む--allではない）")
    parser.add_argument("--private-source-repo", type=Path, help="個人identityを検査する元repo（値は出力しない）")
    parser.add_argument("--binary", type=Path, help="履歴の代わりに配布実行ファイルを検査")
    args = parser.parse_args()
    try:
        terms = private_terms(args.private_source_repo)
        if args.binary:
            categories = scan_text(args.binary.read_bytes().decode("utf-8", errors="replace"), terms)
            for category in sorted(categories):
                print("FAIL binary:", category)
            if categories:
                return 1
            print("Binary privacy verification passed")
        else:
            commits, blobs, findings = scan_history(args.repo, args.ref, terms)
            for location, category in findings:
                print("FAIL object", location + ":", category)
            ignore_failures = check_ignores(args.repo)
            for category in ignore_failures:
                print("FAIL:", category)
            if findings or ignore_failures:
                return 1
            print(f"Publication verification passed: {commits} commits, {blobs} unique blobs; ignore/fixture OK")
        return 0
    except (OSError, ValueError, UnicodeError, subprocess.CalledProcessError):
        print("Verification could not complete; publication blocked", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
