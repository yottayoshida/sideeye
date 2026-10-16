#!/usr/bin/env python3
"""normalise.py <raw stream-json> <out jsonl> <home> <repo root> <report> [<raw stderr> <out stderr>]

#618's normalisation (spike/authoring-cost/run-authoring.sh at 5510fda3), one copy for the subject's
and the graders' transcripts alike.
"""
import json
import re
import sys
from pathlib import Path

SECRET = re.compile(
    r"(sk-ant-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{36,}|gho_[A-Za-z0-9]{36,}"
    r"|glpat-[A-Za-z0-9_-]{20,}|xox[bp]-[A-Za-z0-9-]{10,}|Bearer\s+[A-Za-z0-9._-]+"
    r"|ANTHROPIC_API_KEY=\S+)"
)
GENERATED_PASSWORD = re.compile(r"""(password is\s+[\\"']*)([A-Za-z0-9][A-Za-z0-9._+/=-]{5,})""")


def main(argv):
    src, dst, home, repo, report = argv[:5]
    # At a boundary: a bare replace turns /Users/abc/x into ~c/x when home is /Users/ab.
    home_at_boundary = re.compile(re.escape(home) + r"(?=/|\b|$)")

    def scrub(text):
        text = SECRET.sub("[redacted]", home_at_boundary.sub("~", text))
        return GENERATED_PASSWORD.sub(r"\1[redacted]", text)

    out, rejected, repo_hits = [], 0, 0
    with open(src, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                rejected += 1
                continue
            raw = json.dumps(obj, ensure_ascii=False)
            # Before scrub: the repository lives under home, and scrubbing first erases the string.
            if repo in raw:
                repo_hits += 1
            out.append({"ts": obj.get("timestamp") or obj.get("ts") or "", "text": scrub(raw)})
    with open(dst, "w", encoding="utf-8") as fh:
        for obj in out:
            fh.write(json.dumps(obj, ensure_ascii=False) + "\n")
    Path(report).write_text(
        f"events\t{len(out)}\njson_lines_rejected\t{rejected}\nrepo_root_named_before_normalisation\t{repo_hits}\n",
        encoding="utf-8",
    )
    if len(argv) >= 7:
        err = Path(argv[5])
        Path(argv[6]).write_text(scrub(err.read_text(encoding="utf-8", errors="replace")) if err.exists() else "", encoding="utf-8")
    print(f"normalised {len(out)} event(s); rejected {rejected}; repo root named {repo_hits} time(s)")


if __name__ == "__main__":
    main(sys.argv[1:])
