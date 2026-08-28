#!/usr/bin/env python3
"""The onboarding clock's audit and timeline extraction (PROTOCOL.md).

Reads the driver transcript (claude stream-json) and writes, beside it:
  timeline.tsv  every event's timestamp, kind, and a one-line head — the
                committed evidence the wall-clock is derived from. One row per
                content block, and one row per tool call found anywhere else,
                so no call can be hidden behind a later block in its event.
  meta.json     model, cli version, prompt sha, rc, target version, the policy
                the run declared, the scan's own volume, headline numbers, and
                the audit verdict

The audit's predicates, from the protocol (as amended 2026-08-28). Every tool
call is classified in THIS order, and the order is the point:

  1. the name is in the run's declared DISALLOWED set  -> audit_void
  2. the name is not in the run's declared ALLOWED set -> audit_adjudicate
  3. the name is allowed -> the tool's own predicate (Bash: a plain box
     invocation, judged on the quoted token stream rather than a string prefix)

and, independent of the name, on every call:

  4. a path-shaped key pointing at or into this repository -> audit_void
  5. this repository's root appearing anywhere else in the input -> adjudicate

WHY CLOSED-WORLD. Until 2026-08-28 predicate 2 was its mirror image: a
hardcoded list of denied names, and anything not on it passed with no scrutiny
at all. Measured that day from a plain terminal, `--allowedTools` grants rather
than confines — a command outside the declared scope runs — and denying `Bash`
by name only relocates execution: the driver reached for `Monitor`, which was
on neither list, and ran the same host command. Nothing in this file saw it.
The list of names to fear cannot be enumerated in advance, so the audit now
enumerates the names that are ALLOWED, which the launcher knows exactly, and
surfaces everything else.

WHY THE ORDER, AND WHY THE SPEC MUST REDUCE TO A NAME. Step 3 is why step 2
surfaces rather than voids, and why the allow spec is parsed: the launcher
declares `Bash(docker exec onboarding-box *)`, while the transcript calls the
tool `Bash`. Take the whole spec entry as a name and every legitimate box
invocation lands in step 2 and never reaches its own predicate — a failure that
still satisfies "every off-allowlist call is recorded", so only a test that
asserts a legitimate Bash call is NOT flagged can catch it. `--selftest` has
that assert.

Findings do not stop the extraction — they land in meta.json in two fields
whose difference the protocol defines: `audit_void` (a denied tool, a repo
path — voids the run outright) and `audit_adjudicate` (every shape the audit
surfaces without being able to judge it, for the human adjudication run 1's
precedent established). Both carry the tool's FULL input; a finding truncated
at 160 characters cannot be adjudicated and the raw transcript is not
committed, so that truncation was unrecoverable.

`unauditable`: a transcript with no tool calls is not a clean run, it is a run
nobody can check (the rule `judge.sh` states as "nothing-to-see is not clean").
The same holds for a policy that cannot be parsed. Both refuse to publish.

The clock itself: `clock_start` is the first timestamped event, and
`launch_started_at` is what the launcher stamped immediately before exec.
PROTOCOL.md names which one the criterion uses. They differ because run 1's
init event carried no timestamp, so the transcript-derived start silently began
at the first assistant turn instead.

The stop candidates are every Bash tool result whose paired command carries
`explore` as a word and whose output carries a verdict head (PASS/FAIL as the
report prints it). The tsv carries them all; RESULTS.md names the qualifying
one, checkable by eye.

`--selftest` runs the predicates over synthetic transcripts and exits non-zero
on any miss; the launcher runs it before every real run, and CI runs it on
every push. CI also drives the real entry point on a generated transcript,
because `--selftest` returns before the argument handling, the file writes and
the exit codes — the parts the launcher actually depends on.

Exit status: 0 when the run is auditable, non-zero when it is `unauditable`
(no tool calls, or a line the reader could not parse), when no event carried a
timestamp, or when the audit voids the run. The launcher captures it rather
than aborting on it, so the reading instructions still print for the run that
most needs opening.
"""
import argparse
import json
import re
import sys
from pathlib import Path

# The protocol amendment this extractor implements (PROTOCOL.md, Amendments).
# Re-projecting an older run with this extractor yields this classification,
# not the one that run's committed meta.json carries. run 1 predates the field
# entirely: its meta.json has no protocol_version and its timeline is the older
# one-row-per-event projection. The amendment names it.
PROTOCOL_VERSION = "2026-08-28"

# Keys whose value IS a filesystem path in this CLI's tools. A repo root here
# is a path the call points at, which is as far as the evidence goes: Write and
# Edit carry `file_path` too, so the direction is NOT determined and the finding
# does not claim one. It voids either way — writing into this repository is not
# the lighter half.
#
# `glob` and `pattern` are deliberately absent. They hold patterns, not paths,
# so a repo root inside one is caught by predicate 5 and adjudicated rather than
# voided.
PATH_KEYS = ("file_path", "path", "notebook_path", "cwd")

# A match ends a path element only when what follows cannot continue one.
# Without this `/repo/checkout-old` matches `/repo/checkout` and a sibling
# directory reads as this repository — and, with the home directory,
# `/Users/abc` reads as `/Users/ab`.
#
# Stated as the COMPLEMENT of a delimiter set, not as a list of "path
# characters". Nearly any byte is legal in a filename — the first version of
# this rule allowed only `[A-Za-z0-9._-]` to continue an element, so
# `<root>+backup` and `<root>@2` still read as the root. What genuinely ends a
# path in the text this audit reads is a separator, whitespace, a quote, or the
# punctuation that closes a token in JSON or a shell command. The negative
# lookahead also succeeds at end of string, which is the other boundary.
_BOUNDARY = r"(?![^/\s\"'`,;:)\]}>|&\\])"


def _at_boundary(literal):
    return re.compile(re.escape(literal) + _BOUNDARY)

# The one transformation between the raw stream and the committed record,
# declared here: the driver's host home directory is spelled `~`. The raw
# transcript stays out of the repository for exactly this reason (a host path
# is not evidence, and the projection is re-runnable from the raw file).
#
# ORDER MATTERS AND IS LOAD-BEARING. The repo root lives under HOME, so
# normalising first would rewrite `/Users/x/repo` to `~/repo` and the repo
# predicates would then search for a string that no longer exists. Detection
# runs on the raw input; normalisation happens only when a finding is stored.
HOME = str(Path.home())

# A bare `str.replace` here turns a SIBLING of the home directory into a
# home-relative path: with HOME `/Users/ab`, the unrelated `/Users/abc/x`
# became `~c/x`.
_HOME_AT_BOUNDARY = _at_boundary(HOME)


def spell_home(s):
    return _HOME_AT_BOUNDARY.sub("~", s)


def head(s, n=160):
    s = " ".join(spell_home(str(s)).split())
    return s[:n]


def input_record(inp):
    """A call's input as committed evidence: serialised, then home-spelled.

    A STRING, not a structure, and the order matters. Rewriting a structure key
    by key can collide: `{"<HOME>/k": a, "~/k": b}` normalises both keys to
    `~/k` and one value is gone — silently, from the only record there is, since
    the raw transcript is not committed. That was a real regression, introduced
    while closing a leak through those same keys. Serialising first makes the
    collision impossible, because there are no keys left to collide.

    Unlike head() this does not truncate: this is the material a human
    adjudicates, and the bytes past 160 characters are exactly where a command
    hides what it did. Keys sorted so two runs of the same input compare equal.

    One honest consequence, so nobody assumes otherwise: when two keys differ
    only by the home spelling, the text holds a duplicate name. Both values are
    there to read, which is the point, but the string does not round-trip
    through a JSON parser. It is a record, not an interchange format.
    """
    return spell_home(json.dumps(inp, ensure_ascii=False, sort_keys=True))


def tool_names(spec):
    """The tool NAMES a CLI --allowedTools/--disallowedTools spec grants.

    `Bash(docker exec onboarding-box *)` names the tool `Bash` under a scope;
    the transcript calls it `Bash`. Splitting on commas mirrors how the CLI
    parses its own flag, so a comma inside a scope would break both the same
    way — the audit agreeing with the CLI is the correct behaviour, not a
    limitation to work around.
    """
    names = set()
    for entry in spec.split(","):
        entry = entry.strip()
        if entry:
            names.add(entry.split("(", 1)[0].strip())
    return names


def parse_policy(allowed_spec, disallowed_spec):
    """The declared policy, or a reason it cannot be read.

    Fails closed: an audit that does not know what was allowed cannot say
    anything is outside it, and would report every run clean.
    """
    allowed = tool_names(allowed_spec)
    if not allowed:
        raise ValueError("the allowed-tools spec names no tool; the audit cannot run")
    return {
        "allowed_spec": allowed_spec,
        "disallowed_spec": disallowed_spec,
        "allowed": sorted(allowed),
        "disallowed": sorted(tool_names(disallowed_spec)),
    }


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


def walk_tool_calls(node):
    """Every tool_use block anywhere in this event, however it is nested.

    The predecessor read `message.content[*]` and nothing else, so a call
    carried anywhere else — a different envelope, a future event shape — was
    not merely unjudged but absent from the census. Recursive, after the same
    walk in `spike/loop-closure-timew/judge.sh`.
    """
    out = []
    if isinstance(node, dict):
        if node.get("type") == "tool_use":
            # Found a call: do NOT descend into it. Its `input` is data the
            # driver composed, and this audit exists because the tools it may
            # reach cannot be enumerated — so their input schemas cannot be
            # assumed either. Descending made a dict merely SHAPED like a call
            # into a call: an input carrying
            # `{"type": "tool_use", "name": "WebFetch", ...}` as payload voided
            # the run for a request nobody made. Measured, then fixed. The
            # reference walk in judge.sh descends; on that experiment's inputs
            # it has not bitten, which is not a reason to inherit it here.
            return [node]
        for v in node.values():
            out.extend(walk_tool_calls(v))
    elif isinstance(node, list):
        for v in node:
            out.extend(walk_tool_calls(v))
    return out


def path_key_hits(inp, root):
    """Path-shaped keys AT THE TOP LEVEL of a tool's input, pointing into root.

    Top level only, deliberately. A tool's own parameters are its top-level
    keys; anything nested is data the call is carrying, and reading that as a
    reach fabricates one — measured: a call whose payload merely contained
    `file_path: <repo>/README.md` voided the run. That is the phantom tool call
    fixed in walk_tool_calls, one level down, and the same answer applies:
    the audit cannot assume the schema of a tool it could not enumerate.

    A nested occurrence is not lost. It is caught by the mention predicate and
    adjudicated, where a human decides — which is the right disposition for
    something the audit cannot attribute. This one voids because a top-level
    path parameter IS the call's own target.

    Boundary by construction: `root + "/"` or exact equality, since the value is
    a whole path rather than text that happens to contain one.
    """
    if not isinstance(inp, dict):
        return []
    return [f"{k}={v}" for k, v in inp.items()
            if k in PATH_KEYS and isinstance(v, str)
            and (v == root or v.startswith(root + "/"))]


def mentions(text, root):
    """root appears as a whole path element, not as a prefix of a sibling."""
    return _at_boundary(root).search(text) is not None


def finding(kind, ts, name, inp):
    """A finding a human can act on: what, when, which tool, and the whole input.

    The kind is home-spelled too, not only the input. It is built from material
    the run produced — the matched path, a tokenizer error quoting the command —
    so a host path reaches the committed meta.json through it. That was measured
    once: the repository-path finding printed `/Users/<name>/...` in a file this
    repository commits, while the input beside it read `~/...`. One choke point
    rather than one call site per kind.
    """
    return {"timestamp": ts, "kind": spell_home(kind), "tool": name,
            "input_json": input_record(inp)}


def extract(events, repo_root, policy, run_meta):
    """Project the event stream into (rows, meta). Pure — no I/O."""
    root = repo_root.rstrip("/")
    allowed = set(policy["allowed"])
    disallowed = set(policy["disallowed"])

    model = next((e.get("model") for e in events if e.get("model")), None)
    result = next((e for e in events if e.get("type") == "result"), {})
    # The CLI's init event lists the tools the session actually received. It is
    # recorded when present and null when not: run 1's raw stream is gone, so
    # whether this CLI emits it is unverified until run 2 reads one.
    tools_available = next(
        (e["tools"] for e in events if isinstance(e.get("tools"), list)), None
    )

    cmd_by_id = {}
    rows, void, adjudicate, stop_candidates = [], [], [], []
    content_blocks = 0
    calls_seen = 0
    census = {}

    for ev in events:
        ts = ev.get("timestamp")
        kind = ev.get("type", "?")
        msg = ev.get("message") if isinstance(ev.get("message"), dict) else {}
        blocks = msg.get("content") or []

        # The authoritative call list for this event. Judged below, and also
        # used to guarantee every call reaches the timeline even when it sits
        # somewhere the readable projection does not walk.
        calls = walk_tool_calls(ev)
        projected = set()

        # Pair results against the authoritative list, not the readable one: a
        # result whose call was nested would otherwise pair with nothing, and
        # the stop candidate — which needs `explore` in the paired command — would
        # be lost. Registering from the projection alone is the same
        # projection-as-source-of-truth mistake this amendment is removing.
        for call in calls:
            cmd_by_id[call.get("id")] = (call.get("input") or {}).get("command", "")

        emitted = 0
        for blk in blocks:
            if not isinstance(blk, dict):
                continue
            content_blocks += 1
            note = ""
            if blk.get("type") == "tool_use":
                name = blk.get("name", "?")
                inp = blk.get("input") or {}
                note = f"tool_use {name}: {head(inp.get('command') or inp)}"
                projected.add(id(blk))
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
                    stop_candidates.append(
                        {"timestamp": ts, "command": head(paired), "head": head(text)}
                    )
            elif blk.get("type") == "text":
                note = f"text: {head(blk.get('text', ''))}"
            if note:
                rows.append((ts or "", kind, note))
                emitted += 1

        # A call the readable projection did not reach still gets a row. Without
        # this the timeline could describe an event whose only visible trace is
        # a later block, which is how the previous projection lost every call
        # but the last one in its event.
        for call in calls:
            if id(call) not in projected:
                inp = call.get("input") or {}
                rows.append(
                    (ts or "", kind,
                     f"tool_use {call.get('name', '?')} (nested): "
                     f"{head(inp.get('command') or inp)}")
                )
                emitted += 1

        if emitted == 0:
            note = ""
            if kind == "result":
                note = f"result: turns={ev.get('num_turns')} duration_ms={ev.get('duration_ms')}"
            rows.append((ts or "", kind, note))

        # The audit walks the authoritative list, not the readable projection.
        for call in calls:
            calls_seen += 1
            name = call.get("name") or "?"
            inp = call.get("input") or {}
            census[name] = census.get(name, 0) + 1

            if name in disallowed:
                void.append(finding("denied tool attempted", ts, name, inp))
            elif name not in allowed:
                adjudicate.append(
                    finding("tool outside the declared allow-set", ts, name, inp)
                )
            elif name == "Bash":
                for reason in box_flags(inp.get("command", "")):
                    adjudicate.append(finding(f"bash: {reason}", ts, name, inp))

            # Independent of the name classification, and measured on the RAW
            # input — see HOME's comment for why normalisation cannot come first.
            hits = path_key_hits(inp, root)
            if hits:
                void.append(
                    finding(f"path into this repository ({'; '.join(hits)})", ts, name, inp)
                )
            elif mentions(json.dumps(inp, ensure_ascii=False), root):
                adjudicate.append(
                    finding("this repository's root appears in the input", ts, name, inp)
                )

    first_ts = next((r[0] for r in rows if r[0]), None)
    tv = str(run_meta.get("target_version", "")).strip()

    # A line the reader could not parse is a line whose calls nobody saw. Counting
    # it and then reporting the rest clean is the exact shape this amendment came
    # to remove: measured, a Monitor call on a line with trailing garbage vanished
    # while a legitimate Bash call beside it produced `verdict: clean`. The promise
    # is about every off-allowlist call, so an unread line makes the run
    # uncheckable rather than clean, whatever survived on the other lines.
    if calls_seen == 0 or (run_meta.get("json_lines_rejected") or 0) > 0:
        verdict = "unauditable"
    elif void:
        verdict = "void"
    elif adjudicate:
        verdict = "needs adjudication"
    else:
        verdict = "clean"

    meta = {
        "model": model,
        "cli_version": run_meta.get("cli_version"),
        "prompt_sha256": run_meta.get("prompt_sha256"),
        "agent_rc": int(run_meta.get("agent_rc", 0)),
        "safe_mode": True,
        "protocol_version": PROTOCOL_VERSION,
        "target_version": tv.splitlines()[0] if tv else None,
        "policy": policy,
        "num_turns": result.get("num_turns"),
        "duration_ms": result.get("duration_ms"),
        "launch_started_at": run_meta.get("launch_started_at"),
        "clock_start": first_ts,
        # What the audit actually looked at. A verdict of "clean" over zero
        # examined calls and one over four hundred read identically without
        # this block, and the scan's own coverage is the thing most likely to
        # be wrong. The counters come from different boundaries — lines, events,
        # content blocks, and the recursive call walk — so an omission in one
        # does not vanish from all of them.
        "scan": {
            "json_lines_total": run_meta.get("json_lines_total"),
            "json_lines_rejected": run_meta.get("json_lines_rejected"),
            "events": len(events),
            "content_blocks": content_blocks,
            "tool_calls": calls_seen,
            "timeline_rows": len(rows),
            "tools_used": census,
            "tools_available": tools_available,
        },
        "verdict": verdict,
        "stop_candidates": stop_candidates,
        "audit_void": void,
        "audit_adjudicate": adjudicate,
    }
    return rows, meta


def read_transcript(path):
    """Parse the stream, counting what it could not read.

    A line that does not parse is a line the audit did not see. It is counted
    rather than dropped, so `rejected: 0` is a measurement and not a silence.
    """
    events, total, rejected = [], 0, 0
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            total += 1
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                rejected += 1
                continue
            if isinstance(ev, dict):
                events.append(ev)
            else:
                rejected += 1
    # Deliberately no "parsed" count. A line can parse as JSON and still not be
    # an event — a bare string does — so a single word for both would be two
    # different quantities under one name. What is published instead is total
    # and rejected here, and the event count from the extractor: they come from
    # two boundaries, and `total - rejected == events` is a real agreement
    # rather than the same number printed twice.
    return events, {"json_lines_total": total, "json_lines_rejected": rejected}


# --------------------------------------------------------------------------
# selftest
# --------------------------------------------------------------------------

SELFTEST_ALLOWED = "Bash(docker exec onboarding-box *),Read,Edit,Write,Glob,Grep"
SELFTEST_DISALLOWED = "WebFetch,WebSearch,Task,Agent,Workflow,SendMessage"


def _use(i, name, inp, ts=None):
    return {"timestamp": ts or f"T{i}", "type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": f"id{i}", "name": name, "input": inp}]}}


def _bash(i, cmd):
    return _use(i, "Bash", {"command": cmd})


def _bash_result(i, text):
    return {"timestamp": f"T{i}r", "type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": f"id{i}", "content": text}]}}


def _run(events, repo_root="/repo/checkout"):
    policy = parse_policy(SELFTEST_ALLOWED, SELFTEST_DISALLOWED)
    return extract(events, repo_root, policy, {
        "cli_version": "cli-x", "prompt_sha256": "sha-x", "agent_rc": 0,
        "target_version": "jrnl v9.9\nnoise", "launch_started_at": "T-launch",
        "json_lines_total": len(events), "json_lines_rejected": 0,
    })


def _refuses(fn):
    try:
        fn()
    except ValueError:
        return True
    return False


def _reader_counts_rejects():
    import os
    import tempfile

    fd, p = tempfile.mkstemp(dir=str(Path.home()), suffix=".jsonl")
    try:
        with os.fdopen(fd, "w") as f:
            f.write('{"type":"system"}\n')
            f.write("{not json\n")
            f.write("\n")
            f.write('"a bare string"\n')
        events, scan = read_transcript(p)
        # Four written lines, one of them blank and not counted. `{not json`
        # fails to parse; `"a bare string"` parses and is not an event. Both
        # are rejected, and the identity below is what the two counters buy.
        return (
            len(events) == 1
            and scan["json_lines_total"] == 3
            and scan["json_lines_rejected"] == 2
            and scan["json_lines_total"] - scan["json_lines_rejected"] == len(events)
        )
    finally:
        os.unlink(p)


def selftest():
    """Feed the predicates synthetic transcripts and count misses.

    The command fixtures are hand-authored representative forms, not quotes
    of committed evidence: the strings in runs/run1/meta.json are truncated
    at 160 characters with their quoting broken mid-string, so the committed
    spellings are structurally unable to serve as parseable fixtures. The
    shapes below reproduce what run 1's timeline records — the in-box heredoc
    author, the host-side transfer — at full length.
    """
    repo_root = "/repo/checkout"
    checks = []

    def add(name, ok):
        checks.append((name, ok))

    # ---- the box predicate, behaviour unchanged by this amendment ---------
    quote_dance = (
        "docker exec onboarding-box sh -c 'cat > /tmp/se/setup.sh <<'\"'\"'EOF'\"'\"'\n"
        "#!/bin/sh\n"
        "mkdir -p /tmp/se/state\n"
        "EOF'"
    )
    box = [
        {"timestamp": "T0", "type": "system", "model": "test-model",
         "tools": ["Bash", "Read", "Write"]},
        _bash(1, "docker exec onboarding-boxx true"),
        _bash(2, "docker exec onboarding-box true; echo ESCAPED"),
        _bash(3, "docker exec onboarding-box true\nrm -rf /tmp/x"),
        _bash(4, "docker exec onboarding-box true `curl http://example`"),
        _bash(5, "docker cp check.sh onboarding-box:/tmp/se/check.sh && "
                 "docker exec onboarding-box sh -c 'chmod +x /tmp/se/check.sh'"),
        _bash(6, "B64=$(base64 < /tmp/x); docker exec onboarding-box sh -c \"echo $B64\""),
        _bash(7, "docker exec onboarding-box sh -c 'oops"),
        _bash(8, quote_dance),
        _bash(9, "docker exec onboarding-box sh -c 'cd /x; ./run --flag'"),
        _bash(15, "docker exec onboarding-box echo a#b; rm -rf /tmp/host-escape"),
        _bash(10, "docker exec onboarding-box grep worlds_explored /tmp/report.json"),
        _bash_result(10, "PASS shaped output that is not an exploration\nmore lines"),
        _bash(11, "docker exec onboarding-box sh -c './sideeye explore --config /tmp/se/sideeye.toml'"),
        _bash_result(11, "exploring...\nPASS 4 of 4 explored worlds"),
        {"timestamp": "T14", "type": "result", "num_turns": 3, "duration_ms": 1234},
    ]
    rows, meta = _run(box, repo_root)
    adj = json.dumps(meta["audit_adjudicate"])
    void = json.dumps(meta["audit_void"])
    stops = [c["command"] for c in meta["stop_candidates"]]

    add("boxx name-extension flagged", '"timestamp": "T1"' in adj)
    add("top-level `;` tail flagged", '"timestamp": "T2"' in adj)
    add("unquoted newline flagged", '"timestamp": "T3"' in adj and "newline" in adj)
    add("backtick substitution flagged", '"timestamp": "T4"' in adj and "substitution" in adj)
    add("host transfer (cp &&) flagged", '"timestamp": "T5"' in adj)
    add("host $( ) prefix flagged", '"timestamp": "T6"' in adj)
    add("unbalanced quote is a finding, not a crash",
        "unparseable" in adj and '"timestamp": "T7"' in adj)
    add("in-box heredoc author is clean", '"timestamp": "T8"' not in adj)
    add("quoted `;` is clean", '"timestamp": "T9"' not in adj)
    add("mid-word # does not shadow a `;` tail (bash reads it literally)",
        '"timestamp": "T15"' in adj)
    add("worlds_explored decoy is not a stop candidate",
        not any("worlds_explored" in c for c in stops))
    add("a real explore result is a stop candidate",
        any("sideeye explore" in c for c in stops))
    add("bash findings do not land in audit_void", "onboarding-boxx" not in void)
    add("target_version is a meta field, first line only", meta["target_version"] == "jrnl v9.9")
    add("protocol_version names the amendment", meta["protocol_version"] == PROTOCOL_VERSION)
    add("the init event's tool inventory is recorded",
        meta["scan"]["tools_available"] == ["Bash", "Read", "Write"])
    add("the scan publishes what it examined",
        meta["scan"]["tool_calls"] == 12 and meta["scan"]["tools_used"] == {"Bash": 12})

    # ---- FALSIFIABLE CHECK 1: off-allowlist calls are recorded whole ------
    # Two unknown names, because hardcoding the one measured on 2026-08-28
    # would pass a single-name assert. The first sits BEFORE a legitimate call
    # in the same event, because the previous projection kept only the last
    # block of an event. The command runs past 160 characters, because the
    # previous findings were truncated there.
    tail = "TAIL-MARKER-PAST-160"
    long_cmd = "echo " + ("A" * 200) + " " + tail
    off = [
        {"timestamp": "U1", "type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "u1", "name": "Monitor",
             "input": {"command": long_cmd}},
            {"type": "tool_use", "id": "u2", "name": "Bash",
             "input": {"command": "docker exec onboarding-box true"}}]}},
        _use(3, "TaskOutput", {"task_id": "abc"}, ts="U2"),
    ]
    rows_off, meta_off = _run(off, repo_root)
    adj_off = meta_off["audit_adjudicate"]
    off_tools = [f["tool"] for f in adj_off]

    add("check 1: the first unknown tool is surfaced by name", "Monitor" in off_tools)
    add("check 1: a second, different unknown tool is surfaced by name",
        "TaskOutput" in off_tools)
    add("check 1: the input past 160 characters survives in the finding",
        any(tail in f["input_json"] for f in adj_off))
    add("check 1: the legitimate Bash call beside it is not flagged",
        "Bash" not in off_tools)
    add("check 1: every tool call reaches the timeline",
        sum(1 for r in rows_off if "tool_use Monitor" in r[2]) == 1
        and sum(1 for r in rows_off if "tool_use TaskOutput" in r[2]) == 1
        and sum(1 for r in rows_off if "tool_use Bash" in r[2]) == 1)
    add("check 1: the census counts all three", meta_off["scan"]["tool_calls"] == 3)

    # A call nested where the readable projection does not walk is still judged
    # and still reaches the timeline.
    nested = [{"timestamp": "N1", "type": "assistant", "envelope": {
        "inner": [{"type": "tool_use", "id": "n1", "name": "Monitor",
                   "input": {"command": "echo nested"}}]}}]
    rows_n, meta_n = _run(nested, repo_root)
    add("check 1: a call outside message.content is judged",
        [f["tool"] for f in meta_n["audit_adjudicate"]] == ["Monitor"])
    add("check 1: and it reaches the timeline",
        any("tool_use Monitor (nested)" in r[2] for r in rows_n))

    # The qualifying exploration is found by pairing a result to its call's
    # command. Pairing from the readable projection alone would lose a nested
    # call's command and, with it, the stop candidate that decides the criterion.
    nested_stop = [
        {"timestamp": "S1", "type": "assistant", "envelope": {"inner": [
            {"type": "tool_use", "id": "s1", "name": "Bash",
             "input": {"command": "docker exec onboarding-box sh -c './sideeye explore'"}}]}},
        {"timestamp": "S2", "type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "s1",
             "content": "exploring...\nPASS 4 of 4 explored worlds"}]}},
    ]
    _, meta_s = _run(nested_stop, repo_root)
    add("check 1: a nested call's result still pairs, so the stop candidate survives",
        len(meta_s["stop_candidates"]) == 1
        and "sideeye explore" in meta_s["stop_candidates"][0]["command"])

    # ---- FALSIFIABLE CHECK 2: an unreadable run is never clean -----------
    rows_a, meta_a = _run([{"type": "system", "model": "m"}], repo_root)
    add("check 2a: no tool calls and no timestamps is unauditable, not clean",
        meta_a["verdict"] == "unauditable" and meta_a["clock_start"] is None)
    rows_b, meta_b = _run([
        {"timestamp": "V1", "type": "system", "model": "m"},
        {"timestamp": "V2", "type": "assistant", "message": {"content": [
            {"type": "text", "text": "I did nothing"}]}},
    ], repo_root)
    add("check 2b: no tool calls but timestamps present is still unauditable",
        meta_b["verdict"] == "unauditable" and meta_b["clock_start"] == "V1")
    add("check 2c: a policy naming no tool is refused",
        _refuses(lambda: parse_policy("", SELFTEST_DISALLOWED))
        and _refuses(lambda: parse_policy("   ,  ", SELFTEST_DISALLOWED)))
    add("check 2d: the reader counts a line it cannot parse", _reader_counts_rejects())

    # An unread line hides whatever calls it carried. Counting it and then
    # reporting the readable remainder clean is what review reproduced: a Monitor
    # call on a broken line vanished while a legitimate Bash call beside it kept
    # the verdict green. The fixture below has a real, allowed call, so this is
    # not the zero-call path taking the decision.
    policy = parse_policy(SELFTEST_ALLOWED, SELFTEST_DISALLOWED)
    _, meta_rej = extract([_bash(40, "docker exec onboarding-box true")], repo_root, policy, {
        "cli_version": "c", "prompt_sha256": "s", "agent_rc": 0, "target_version": "v",
        "launch_started_at": "L", "json_lines_total": 2, "json_lines_rejected": 1,
    })
    add("check 2e: a line the reader could not parse makes the run unauditable",
        meta_rej["verdict"] == "unauditable" and meta_rej["scan"]["tool_calls"] == 1)

    # ---- FALSIFIABLE CHECK 3: the classification order, and the names ----
    order = [
        _use(20, "WebFetch", {"url": "http://x"}),
        _bash(21, "docker exec onboarding-box true"),
        _bash(22, "docker cp x onboarding-box:/tmp/x"),
        _use(23, "Grep", {"pattern": "x", "path": "/tmp/box"}),
        _use(24, "Read", {"file_path": repo_root + "/src/engine.zig"}),
        _use(25, "Grep", {"pattern": "x", "glob": repo_root + "/**"}),
        _use(26, "Read", {"file_path": repo_root + "-old/src/engine.zig"}),
    ]
    rows_o, meta_o = _run(order, repo_root)
    v_kinds = {(f["timestamp"], f["kind"]) for f in meta_o["audit_void"]}
    a_kinds = {(f["timestamp"], f["kind"]) for f in meta_o["audit_adjudicate"]}
    v_ts = {t for t, _ in v_kinds}
    a_ts = {t for t, _ in a_kinds}

    add("check 3: a disallowed tool voids and is not demoted to adjudicate",
        "T20" in v_ts and "T20" not in a_ts)
    add("check 3: a legitimate box invocation carries no finding at all",
        "T21" not in v_ts and "T21" not in a_ts)
    add("check 3: a non-box Bash reaches its own predicate",
        any(t == "T22" and k.startswith("bash: ") for t, k in a_kinds))
    add("check 3: an allowed tool is not flagged on its name",
        "T23" not in v_ts and "T23" not in a_ts)
    add("check 3: a path-shaped key into the repository voids",
        any(t == "T24" and k.startswith("path into this repository") for t, k in v_kinds))
    add("check 3: the repository root elsewhere in the input is adjudicated",
        any(t == "T25" and "root appears" in k for t, k in a_kinds))
    add("check 3: a sibling directory is not this repository",
        "T26" not in v_ts and "T26" not in a_ts)

    # meta.json is committed and the raw transcript is not, precisely because a
    # host path is not evidence. Asserted over the WHOLE serialised meta rather
    # than over the fields known to carry paths: the leak measured on 2026-08-28
    # was in a finding's `kind`, a field nobody had thought of as a path carrier.
    under_home = str(Path.home()) + "/repo-under-home"
    _, meta_h = _run([
        _use(30, "Read", {"file_path": under_home + "/src/x.zig"}),
        _bash(31, "docker exec onboarding-box sh -c 'oops " + under_home + "/y"),
    ], under_home)
    add("no raw host home directory survives anywhere in meta.json",
        str(Path.home()) not in json.dumps(meta_h))
    add("...and that fixture did produce findings, so the assert saw something",
        len(meta_h["audit_void"]) + len(meta_h["audit_adjudicate"]) >= 2)

    # The home rewrite must respect a path boundary, and must reach dict keys.
    add("a sibling of the home directory is not rewritten as home-relative",
        spell_home(str(Path.home()) + "bc/x") == str(Path.home()) + "bc/x")
    add("the home directory itself, and a path under it, are rewritten",
        spell_home(str(Path.home())) == "~"
        and spell_home(str(Path.home()) + "/x") == "~/x")
    add("a key carrying the home directory is spelled `~` in the record",
        input_record({str(Path.home()) + "/k": "v"}) == '{"~/k": "v"}')
    # Rewriting a structure key by key collided and dropped a value. Serialising
    # first has no keys to collide, and this is the assert that says so.
    both = input_record({str(Path.home()) + "/k": "raw", "~/k": "tilde"})
    add("two keys that differ only by the home spelling both survive",
        "raw" in both and "tilde" in both)
    add("a sibling of the home directory survives `+` and `@` too",
        spell_home(str(Path.home()) + "+backup/x") == str(Path.home()) + "+backup/x"
        and spell_home(str(Path.home()) + "@2/x") == str(Path.home()) + "@2/x")

    # A call's own input is data the driver composed; the audit cannot assume the
    # schema of a tool it could not enumerate. Descending into it turned a payload
    # merely shaped like a call into a call, and voided a run for a request nobody
    # made.
    _, meta_p = _run([_use(41, "Monitor", {
        "command": "echo x",
        "payload": {"type": "tool_use", "name": "WebFetch",
                    "input": {"url": "https://example"}}})], repo_root)
    add("a tool_use-shaped payload inside a call's input is not a second call",
        meta_p["scan"]["tool_calls"] == 1
        and meta_p["scan"]["tools_used"] == {"Monitor": 1}
        and meta_p["verdict"] != "void")
    # Indexed access would raise rather than report a miss when a mutation empties
    # the list, and a selftest that crashes tells the harness nothing about which
    # predicate died.
    add("...and the payload still reaches the record, inside the call that carried it",
        any("WebFetch" in f["input_json"] for f in meta_p["audit_adjudicate"]))

    # One level down from the phantom call: a repository path carried as PAYLOAD
    # inside a real call's input is not that call reaching the repository. It is
    # surfaced for a human rather than voiding the run on the audit's guess.
    _, meta_np = _run([_use(42, "Monitor", {
        "command": "echo x",
        "payload": {"file_path": repo_root + "/README.md"}})], repo_root)
    add("a repository path nested in a payload adjudicates rather than voids",
        meta_np["verdict"] != "void" and meta_np["audit_void"] == []
        and any("root appears" in f["kind"] for f in meta_np["audit_adjudicate"]))
    add("...while the same key at the top level of the input still voids",
        _run([_use(43, "Read", {"file_path": repo_root + "/README.md"})],
             repo_root)[1]["verdict"] == "void")

    # The scope spec must reduce to the tool's name, or every legitimate box
    # call lands off-allowlist while the main promise still reads as kept.
    add("check 3: the scoped Bash spec reduces to the name `Bash`",
        "Bash" in tool_names(SELFTEST_ALLOWED))
    # A comma inside a scope is split by the CLI too, so the audit inherits the
    # same reading rather than out-guessing it. Pinned so the shared limit is
    # visible: the stray `b)` here is what a scope with a comma costs on both
    # sides, not a bug the audit could fix alone.
    add("check 3: a scope containing a comma splits the way the CLI splits it",
        tool_names("Bash(a,b),Read") == {"Bash", "b)", "Read"})

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  {'ok ' if ok else 'MISS'} {name}")
    if failed:
        sys.exit(f"selftest: {len(failed)} of {len(checks)} checks missed")
    print(f"selftest: {len(checks)} checks pass")


def main():
    # Named flags, not positions. The two policy strings are adjacent and have
    # the same shape, so a positional call site could swap them — inverting the
    # allow and deny sets — and every test here would still pass, since the
    # selftest builds its own policy and never reads the launcher's call. The
    # order cannot be got wrong if there is no order.
    ap = argparse.ArgumentParser(
        description="The onboarding clock's audit and timeline extraction.")
    ap.add_argument("--selftest", action="store_true",
                    help="run the predicates over synthetic transcripts and exit")
    for flag, helptext in (
        ("--transcript", "the driver's stream-json transcript"),
        ("--outdir", "where timeline.tsv and meta.json are written"),
        ("--cli-version", "the claude CLI version the launcher measured"),
        ("--prompt-sha", "sha256 of prompt.md as handed to the driver"),
        ("--agent-rc", "the driver process's exit status"),
        ("--repo-root", "this repository's checkout, which the driver must not reach"),
        ("--target-version", "the target's installed version, read before the clock"),
        ("--allowed", "the --allowedTools string handed to the CLI, verbatim"),
        ("--disallowed", "the --disallowedTools string handed to the CLI, verbatim"),
        ("--launch-started-at", "UTC stamp taken one line before the driver exec"),
    ):
        ap.add_argument(flag, help=helptext)
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return

    missing = [f for f in ("transcript", "outdir", "cli_version", "prompt_sha",
                           "agent_rc", "repo_root", "target_version", "allowed",
                           "disallowed", "launch_started_at")
               if getattr(args, f) is None]
    if missing:
        ap.error("missing required argument(s): "
                 + ", ".join("--" + m.replace("_", "-") for m in missing))

    try:
        policy = parse_policy(args.allowed, args.disallowed)
    except ValueError as e:
        sys.exit(f"cannot read the declared policy: {e}")

    outdir = args.outdir
    events, scan = read_transcript(args.transcript)
    run_meta = {
        "cli_version": args.cli_version,
        "prompt_sha256": args.prompt_sha,
        "agent_rc": args.agent_rc,
        "target_version": args.target_version,
        "launch_started_at": args.launch_started_at,
    }
    run_meta.update(scan)

    rows, meta = extract(events, args.repo_root, policy, run_meta)

    with open(f"{outdir}/timeline.tsv", "w") as f:
        f.write("timestamp\tkind\tnote\n")
        for ts, kind, note in rows:
            f.write(f"{ts}\t{kind}\t{note}\n")
    with open(f"{outdir}/meta.json", "w") as f:
        json.dump(meta, f, indent=1)

    s = meta["scan"]
    print(
        f"lines: {s['json_lines_total']} ({s['json_lines_rejected']} unparseable); "
        f"events: {s['events']}; blocks: {s['content_blocks']}; "
        f"tool calls: {s['tool_calls']} {s['tools_used']}; "
        f"timeline rows: {s['timeline_rows']}; "
        f"stop candidates: {len(meta['stop_candidates'])}"
    )
    print(f"verdict: {meta['verdict']}")
    for v in meta["audit_void"]:
        print(f"  VOID: {v['kind']} at {v['timestamp']} [{v['tool']}]")
    for v in meta["audit_adjudicate"]:
        print(f"  ADJUDICATE: {v['kind']} at {v['timestamp']} [{v['tool']}]")

    if meta["verdict"] == "unauditable":
        why = []
        if s["tool_calls"] == 0:
            why.append("the transcript holds no tool calls")
        if s["json_lines_rejected"]:
            why.append(f"{s['json_lines_rejected']} line(s) could not be read")
        sys.exit(
            f"unauditable: {'; '.join(why)} — nothing-to-see is not clean; "
            "do not publish this run"
        )
    if meta["clock_start"] is None:
        sys.exit("no timestamped events — the clock cannot be derived; do not publish this run")
    if meta["verdict"] == "void":
        sys.exit("the audit voids this run; see audit_void in meta.json")


if __name__ == "__main__":
    main()
