#!/usr/bin/env python3
"""The onboarding clock's audit and timeline extraction (PROTOCOL.md).

Reads the driver transcript (claude stream-json) and writes, beside it:
  timeline.tsv  every event's timestamp, kind, and a one-line head — the
                committed evidence the wall-clock is derived from
  meta.json     model, cli version, prompt sha, rc, headline numbers, and the
                audit verdict

The audit's predicates, from the protocol:
  1. every Bash command is a `docker exec onboarding-box` invocation
  2. no tool call reads into this repository's checkout
  3. no denied tool is attempted
A violation does not stop the extraction — it lands in meta.json as
audit_violations, and the protocol says what a non-empty list means: void.

The clock itself: start is the first timestamped event; the stop candidates
are every Bash tool result whose paired command mentions `explore` and whose
output carries a verdict head (PASS/FAIL as the report prints it). The tsv
carries them all; RESULTS.md names the qualifying one, checkable by eye.
"""
import json
import sys
from pathlib import Path

# The one transformation between the raw stream and the committed timeline,
# declared here: the driver's host home directory is spelled `~`. The raw
# transcript stays out of the repository for exactly this reason (a host path
# is not evidence, and the projection is re-runnable from the raw file).
HOME = str(Path.home())


def head(s, n=160):
    s = " ".join(str(s).replace(HOME, "~").split())
    return s[:n]


def main():
    transcript, outdir, cli_version, prompt_sha, agent_rc, repo_root = sys.argv[1:7]
    events = []
    with open(transcript) as f:
        for line in f:
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(ev, dict):
                events.append(ev)

    model = next((e.get("model") for e in events if e.get("model")), None)
    result = next((e for e in events if e.get("type") == "result"), {})

    # tool_use id -> command, so a result row can say what it answers.
    cmd_by_id = {}
    rows, violations, stop_candidates = [], [], []
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
                if name == "Bash" and not cmd.strip().startswith("docker exec onboarding-box"):
                    violations.append(f"non-box Bash at {ts}: {head(cmd)}")
                if name in ("WebFetch", "WebSearch", "Task", "Agent", "Workflow"):
                    violations.append(f"denied tool {name} attempted at {ts}")
                target = str(inp.get("file_path", "")) + str(inp.get("path", ""))
                if repo_root.rstrip("/") in target:
                    violations.append(f"repo read at {ts}: {head(target)}")
            elif blk.get("type") == "tool_result":
                content = blk.get("content")
                if isinstance(content, list):
                    content = " ".join(
                        c.get("text", "") for c in content if isinstance(c, dict)
                    )
                paired = cmd_by_id.get(blk.get("tool_use_id"), "")
                note = f"tool_result for [{head(paired, 60)}]: {head(content)}"
                text = str(content)
                if "explore" in paired and ("\nPASS" in text or text.startswith("PASS") or "\nFAIL" in text or text.startswith("FAIL")):
                    stop_candidates.append({"timestamp": ts, "command": head(paired), "head": head(text)})
            elif blk.get("type") == "text":
                note = f"text: {head(blk.get('text', ''))}"
        if not note and kind == "result":
            note = f"result: turns={ev.get('num_turns')} duration_ms={ev.get('duration_ms')}"
        rows.append((ts or "", kind, note))

    with open(f"{outdir}/timeline.tsv", "w") as f:
        f.write("timestamp\tkind\tnote\n")
        for ts, kind, note in rows:
            f.write(f"{ts}\t{kind}\t{note}\n")

    first_ts = next((r[0] for r in rows if r[0]), None)
    meta = {
        "model": model,
        "cli_version": cli_version,
        "prompt_sha256": prompt_sha,
        "agent_rc": int(agent_rc),
        "safe_mode": True,
        "num_turns": result.get("num_turns"),
        "duration_ms": result.get("duration_ms"),
        "clock_start": first_ts,
        "stop_candidates": stop_candidates,
        "audit_violations": violations,
    }
    with open(f"{outdir}/meta.json", "w") as f:
        json.dump(meta, f, indent=1)

    if first_ts is None:
        sys.exit("no timestamped events — the clock cannot be derived; do not publish this run")
    print(f"timeline: {len(rows)} events; stop candidates: {len(stop_candidates)}; violations: {len(violations)}")
    for v in violations:
        print(f"  VIOLATION: {v}")


if __name__ == "__main__":
    main()
