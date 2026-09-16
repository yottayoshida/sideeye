"""Replace the fabricated AWS-shaped credentials this run's aws-cli define used with strings of the
same length that no secret scanner reads as AWS keys. Equal lengths keep every byte count the
transcripts record (credentials 230/231 bytes) true. strace truncates the written string after 32
characters, so the excerpt carries only the key's first two letters; that prefix is replaced too.
    redact-probe-credentials.py <dir>
"""
import os, sys
# The originals are written as two adjacent literals each, so this file does not itself carry a
# string of the shape it exists to remove.
PAIRS = [
    ("AKI" "AEXAMPLEDEFAULT01", "FAKE-ID-DEFAULT-0001"),
    ("AKI" "AEXAMPLEWORK00001", "FAKE-ID-WORK-0000001"),
    ("defaultSecretKey" "ForProbeOnly0000000000000", "fake-secret-default-for-probe-only-000000"),
    ("workSecretKey" "ForProbeOnly000000000000000", "fake-secret-work-for-probe-only-00000000"),
    ("rotatedSecretKey" "ForProbeOnly00000000000", "fake-secret-rotated-for-probe-only-0000"),
    ('aws_access_key_id = AK"...', 'aws_access_key_id = FA"...'),
]
changed = 0
for root, _, files in os.walk(sys.argv[1]):
    for name in files:
        p = os.path.join(root, name)
        try:
            s = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        t = s
        for a, b in PAIRS:
            assert len(a) == len(b)
            t = t.replace(a, b)
        if t != s:
            open(p, "w", encoding="utf-8").write(t)
            changed += 1
            print("  redacted", p)
print("files changed:", changed)
