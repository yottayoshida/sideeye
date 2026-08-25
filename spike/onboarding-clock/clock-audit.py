#!/usr/bin/env python3
"""The onboarding clock's audit and timeline extraction (PROTOCOL.md).

Reads the driver transcript (claude stream-json) and writes, beside it:
  timeline.tsv  every event's timestamp, kind, and a one-line head — the
                committed evidence the wall-clock is derived from
  meta.json     model, cli version, prompt sha, rc, target version, headline
                numbers, and the audit verdict

The audit's predicates, from the protocol (as amended 2026-08-25):
  1. every Bash command is a plain `docker exec onboarding-box` invocation,
     judged on the quoted token stream, not a string prefix
  2. no tool call reads into this repository's checkout
  3. no denied tool is attempted
Findings do not stop the extraction — they land in meta.json in two fields
whose difference the protocol defines: `audit_void` (a denied tool, a repo
read — voids the run outright) and `audit_adjudicate` (every shape the box
predicate surfaces, including ones the permission layer legitimately allows,
for the human adjudication run 1's precedent established).

The clock itself: start is the first timestamped event; the stop candidates
are every Bash tool result whose paired command carries `explore` as a word
and whose output carries a verdict head (PASS/FAIL as the report prints it).
The tsv carries them all; RESULTS.md names the qualifying one, checkable by
eye.

`--selftest` runs the predicates over a synthetic transcript and exits
non-zero on any miss; the launcher runs it before every real run.
"""
import json
import re
import sys
from pathlib import Path

# The protocol amendment this extractor implements (PROTOCOL.md, Amendments).
# Re-projecting an older run with this extractor yields this classification,
# not the one that run's committed meta.json carries.
PROTOCOL_VERSION = "2026-08-25"

DENIED_TOOLS = (
    "WebFetch", "WebSearch", "Task", "Agent", "Workflow",
    "SendMessage", "PushNotification", "RemoteTrigger",
    "ScheduleWakeup", "CronCreate", "CronDelete",
)

# The one transformation between the raw stream and the committed timeline,
# declared here: the driver's host home directory is spelled `~`. The raw
# transcript stays out of the repository for exactly this reason (a host path
# is not evidence, and the projection is re-runnable from the raw file).
HOME = str(Path.home())


def head(s, n=160):
    s = " ".join(str(s).replace(HOME, "~").split())
    return s[:n]


def box_flags(cmd):
    """Why this Bash command is not a plain box invocation — [] means clean.

    Tokenizes with quoting in force (shlex, punctuation_chars), so a `;` or a
    newline inside quotes is payload for the box while the same character at
    the top level is a host-side command separator. Never raises: a command
    the tokenizer cannot parse is itself a finding.
    """
    import shlex

    try:
        lx = shlex.shlex(cmd, punctuation_chars=True)
        lx.whitespace_split = True
        # shlex's default commenters ('#') discards everything after a '#'
        # even mid-word, where bash treats it as a literal — so `echo a#b; rm`
        # would lose its `; rm` to a comment the shell never sees. No comment
        # handling at all: a leading-# bash comment then gets flagged as an
        # ordinary token, which is the flag-over-silence direction.
        lx.commenters = ""
        toks = list(lx)
    except ValueError as e:
        return [f"unparseable ({e})"]
    reasons = []
    if toks[:3] != ["docker", "exec", "onboarding-box"]:
        reasons.append("not a plain `docker exec onboarding-box` invocation")
    ops = [t for t in toks if t and all(c in "();<>|&" for c in t)]
    if ops:
        reasons.append(f"top-level shell operator(s): {' '.join(sorted(set(ops)))}")
    # shlex treats an unquoted newline as whitespace, so it can never appear
    # as a token — but to bash it is a command separator, the same escape as
    # `;`. A quoted newline survives inside its token; the counts differ only
    # when one was unquoted.
    if cmd.count("\n") != sum(t.count("\n") for t in toks):
        reasons.append("unquoted newline (a command separator to the shell)")
    # Backticks are neither quotes nor punctuation to shlex — they ride along
    # inside tokens. An unquoted `$(` splits at the `(` and is caught as an
    # operator above; a quoted one survives in its token and is caught here.
    # A quoted substitution expands inside the box and is legitimate — it is
    # still surfaced, because the audit cannot tell the two apart and the
    # protocol prefers a flag over silence.
    subst = [t for t in toks if "`" in t or "$(" in t]
    if subst:
        reasons.append("command-substitution marker (` or $() in the command")
    return reasons


def extract(events, cli_version, prompt_sha, agent_rc, repo_root, target_version):
    """Project the event stream into (rows, meta). Pure — no I/O."""
    model = next((e.get("model") for e in events if e.get("model")), None)
    result = next((e for e in events if e.get("type") == "result"), {})

    # tool_use id -> command, so a result row can say what it answers.
    cmd_by_id = {}
    rows, void, adjudicate, stop_candidates = [], [], [], []
    for ev in events:
        ts = ev.get("timestamp")
        kind = ev.get("type", "?")
        note = ""
        msg = ev.get("message") if isinstance(ev.get("message"), dict) else {}
        for blk in msg.get("content") or []:
            if not isinstance(blk, dict):
                continue
            if blk.get("type") == "tool_use":
                name = blk.get("name", "?")
                inp = blk.get("input") or {}
                cmd = inp.get("command", "")
                cmd_by_id[blk.get("id")] = cmd
                note = f"tool_use {name}: {head(cmd or inp)}"
                if name == "Bash":
                    for reason in box_flags(cmd):
                        adjudicate.append(f"{reason} at {ts}: {head(cmd)}")
                if name in DENIED_TOOLS:
                    void.append(f"denied tool {name} attempted at {ts}")
                target = str(inp.get("file_path", "")) + str(inp.get("path", ""))
                if repo_root.rstrip("/") in target:
                    void.append(f"repo read at {ts}: {head(target)}")
            elif blk.get("type") == "tool_result":
                content = blk.get("content")
                if isinstance(content, list):
                    content = " ".join(
                        c.get("text", "") for c in content if isinstance(c, dict)
                    )
                paired = cmd_by_id.get(blk.get("tool_use_id"), "")
                note = f"tool_result for [{head(paired, 60)}]: {head(content)}"
                text = str(content)
                if re.search(r"\bexplore\b", paired) and (
                    "\nPASS" in text or text.startswith("PASS")
                    or "\nFAIL" in text or text.startswith("FAIL")
                ):
                    stop_candidates.append({"timestamp": ts, "command": head(paired), "head": head(text)})
            elif blk.get("type") == "text":
                note = f"text: {head(blk.get('text', ''))}"
        if not note and kind == "result":
            note = f"result: turns={ev.get('num_turns')} duration_ms={ev.get('duration_ms')}"
        rows.append((ts or "", kind, note))

    first_ts = next((r[0] for r in rows if r[0]), None)
    tv = str(target_version).strip()
    meta = {
        "model": model,
        "cli_version": cli_version,
        "prompt_sha256": prompt_sha,
        "agent_rc": int(agent_rc),
        "safe_mode": True,
        "protocol_version": PROTOCOL_VERSION,
        "target_version": tv.splitlines()[0] if tv else None,
        "num_turns": result.get("num_turns"),
        "duration_ms": result.get("duration_ms"),
        "clock_start": first_ts,
        "stop_candidates": stop_candidates,
        "audit_void": void,
        "audit_adjudicate": adjudicate,
    }
    return rows, meta


def selftest():
    """Feed the predicates a synthetic transcript and count misses.

    The command fixtures are hand-authored representative forms, not quotes
    of committed evidence: the strings in runs/run1/meta.json are truncated
    at 160 characters with their quoting broken mid-string (2 of 3 raise
    ValueError in shlex), so the committed spellings are structurally unable
    to serve as parseable fixtures. The shapes below reproduce what run 1's
    timeline records — the in-box heredoc author, the host-side transfer —
    at full length.
    """
    repo_root = "/repo/checkout"

    def bash_use(i, cmd):
        return {"timestamp": f"T{i}", "type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": f"id{i}", "name": "Bash", "input": {"command": cmd}}]}}

    def bash_result(i, text):
        return {"timestamp": f"T{i}r", "type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": f"id{i}", "content": text}]}}

    quote_dance = (
        "docker exec onboarding-box sh -c 'cat > /tmp/se/setup.sh <<'\"'\"'EOF'\"'\"'\n"
        "#!/bin/sh\n"
        "mkdir -p /tmp/se/state\n"
        "EOF'"
    )
    events = [
        {"timestamp": "T0", "type": "system", "model": "test-model"},
        bash_use(1, "docker exec onboarding-boxx true"),
        bash_use(2, "docker exec onboarding-box true; echo ESCAPED"),
        bash_use(3, "docker exec onboarding-box true\nrm -rf /tmp/x"),
        bash_use(4, "docker exec onboarding-box true `curl http://example`"),
        bash_use(5, "docker cp check.sh onboarding-box:/tmp/se/check.sh && "
                    "docker exec onboarding-box sh -c 'chmod +x /tmp/se/check.sh'"),
        bash_use(6, "B64=$(base64 < /tmp/x); docker exec onboarding-box sh -c \"echo $B64\""),
        bash_use(7, "docker exec onboarding-box sh -c 'oops"),
        bash_use(8, quote_dance),
        bash_use(9, "docker exec onboarding-box sh -c 'cd /x; ./run --flag'"),
        bash_use(15, "docker exec onboarding-box echo a#b; rm -rf /tmp/host-escape"),
        bash_use(10, "docker exec onboarding-box grep worlds_explored /tmp/report.json"),
        bash_result(10, "PASS shaped output that is not an exploration\nmore lines"),
        bash_use(11, "docker exec onboarding-box sh -c './sideeye explore --config /tmp/se/sideeye.toml'"),
        bash_result(11, "exploring...\nPASS 4 of 4 explored worlds"),
        {"timestamp": "T12", "type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "id12", "name": "WebFetch", "input": {"url": "http://x"}}]}},
        {"timestamp": "T13", "type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "id13", "name": "Read",
             "input": {"file_path": repo_root + "/src/engine.zig"}}]}},
        {"timestamp": "T14", "type": "result", "num_turns": 3, "duration_ms": 1234},
    ]

    rows, meta = extract(events, "cli-x", "sha-x", 0, repo_root, "jrnl v9.9\nnoise")
    adjudicate = "\n".join(meta["audit_adjudicate"])
    void = "\n".join(meta["audit_void"])
    stops = [c["command"] for c in meta["stop_candidates"]]

    checks = [
        ("boxx name-extension flagged", " at T1:" in adjudicate),
        ("top-level `;` tail flagged", " at T2:" in adjudicate),
        ("unquoted newline flagged", " at T3:" in adjudicate and "newline" in adjudicate),
        ("backtick substitution flagged", " at T4:" in adjudicate and "substitution" in adjudicate),
        ("host transfer (cp &&) flagged", " at T5:" in adjudicate),
        ("host $( ) prefix flagged", " at T6:" in adjudicate),
        ("unbalanced quote is a finding, not a crash", "unparseable" in adjudicate and " at T7:" in adjudicate),
        ("in-box heredoc author is clean", " at T8:" not in adjudicate),
        ("quoted `;` is clean", " at T9:" not in adjudicate),
        ("mid-word # does not shadow a `;` tail (bash reads it literally)", " at T15:" in adjudicate),
        ("worlds_explored decoy is not a stop candidate",
         not any("worlds_explored" in c for c in stops)),
        ("a real explore result is a stop candidate",
         any("sideeye explore" in c for c in stops)),
        ("denied tool lands in audit_void", "WebFetch" in void),
        ("repo read lands in audit_void", "repo read" in void),
        ("bash findings do not land in audit_void", "onboarding-boxx" not in void),
        ("target_version is a meta field, first line only", meta["target_version"] == "jrnl v9.9"),
        ("protocol_version names the amendment", meta["protocol_version"] == PROTOCOL_VERSION),
        ("timeline rows cover every event", len(rows) == len(events)),
    ]
    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  {'ok ' if ok else 'MISS'} {name}")
    if failed:
        sys.exit(f"selftest: {len(failed)} of {len(checks)} checks missed")
    print(f"selftest: {len(checks)} checks pass")


def main():
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        return
    if len(sys.argv) != 8:
        sys.exit(
            "usage: clock-audit.py <transcript> <outdir> <cli_version> <prompt_sha> "
            "<agent_rc> <repo_root> <target_version>  (or --selftest)"
        )
    transcript, outdir, cli_version, prompt_sha, agent_rc, repo_root, target_version = sys.argv[1:8]
    events = []
    with open(transcript) as f:
        for line in f:
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(ev, dict):
                events.append(ev)

    rows, meta = extract(events, cli_version, prompt_sha, agent_rc, repo_root, target_version)

    with open(f"{outdir}/timeline.tsv", "w") as f:
        f.write("timestamp\tkind\tnote\n")
        for ts, kind, note in rows:
            f.write(f"{ts}\t{kind}\t{note}\n")
    with open(f"{outdir}/meta.json", "w") as f:
        json.dump(meta, f, indent=1)

    if meta["clock_start"] is None:
        sys.exit("no timestamped events — the clock cannot be derived; do not publish this run")
    print(
        f"timeline: {len(rows)} events; stop candidates: {len(meta['stop_candidates'])}; "
        f"void: {len(meta['audit_void'])}; adjudicate: {len(meta['audit_adjudicate'])}"
    )
    for v in meta["audit_void"]:
        print(f"  VOID: {v}")
    for v in meta["audit_adjudicate"]:
        print(f"  ADJUDICATE: {v}")


if __name__ == "__main__":
    main()
