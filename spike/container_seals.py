#!/usr/bin/env python3
"""The seals on the eval container's outputs: what the loop-closure judge reads, and why (#597).

`judge.sh eval` runs the agent-built `timew` under the sealed `sideeye` as uid 0, in a container
whose one writable directory is where `sideeye` writes its replay report. A `timew` that leaves
a child behind can rewrite that report -- or the shell's rc and functional-gate files beside it --
for as long as the container lives after `sideeye` exits. The files cannot be trusted; what can
is the container's own stdout: the subject can APPEND to that stream (it is uid 0 and can open
`/proc/1/fd/1`; during the replay it inherits sideeye's stderr outright) but it cannot remove or
rewrite a byte another process already put there. So each thing the judge needs arrives as one
token on that stream, put there by the process that made it, at the moment it made it:

  sideeye: json sha256=<64 hex>;        written by sideeye itself, one write(), when the report
                                        landed; `sha256=none;` when it could not be written
  judge: replay-rc=<n>;                 the shell, a printf builtin, after sideeye exits
  judge: func-status=ran|fail;          the shell, after the functional gate
  judge: func-export begin;\\n...\\njudge: func-export end;
                                        the shell, the export's bytes as $(...) received them

and this module reads the stream by ONE rule: a token counts wherever it appears, and there must
be exactly one. Not anchored to a line start -- a subject that writes bytes without a newline
ahead of the real token takes its line start away, and one that then writes its own token from a
fresh line would be the only anchored match (found in review). Counted anywhere, hiding leaves
the real one at 1 and adding a forgery makes 2; both directions end in a refusal, never in the
forgery being read. The report file is opened non-blocking and without following links, must be
a regular file under a size cap, is read once, and the same bytes are hashed and parsed -- a FIFO
or a link planted at the name refuses instead of blocking (review, M7), and there is no second
open for something to slip between.

Refusals, one name each: `seal_missing` (no token, or sideeye's `none`), `seal_ambiguous` (more
than one), `seal_mismatch` (the file's bytes are not the ones sideeye sealed -- including when
there are none, because the file is gone), `not_a_regular_file` (a FIFO, a link, a directory --
the kinds, not the reasons an open can fail), `unreadable` (it could not be opened at all:
permission, descriptors, a path component), `too_large`, `not_json` (sealed bytes that do not
parse -- sideeye's own defect, refused rather than guessed). The tokens' prefixes are chosen apart from sideeye's own diagnostics (`sideeye: the
JSON report was not written: ...` shares no prefix with `sideeye: json sha256=`), and the selftest
holds that apart.

Two consumers: `spike/loop-closure-timew/judge.sh` (executed from these bytes, not imported --
the `.pyc` cache is the agent's to write, ADR 0066) and this file's own `--selftest`, which
`spike/acceptance.sh` runs beside `replay_gate.py`'s and `suite_summary.py`'s.

CLI: container_seals.py <container.log> <replay.json>
     prints the four channels' verdicts as JSON; exit 0 iff every channel sealed.
     container_seals.py --selftest
"""
import errno
import hashlib
import json
import os
import re
import stat
import sys

PREFIX_JSON = b"sideeye: json sha256="
PREFIX_RC = b"judge: replay-rc="
PREFIX_FUNC_STATUS = b"judge: func-status="
FUNC_BEGIN = b"judge: func-export begin;\n"
FUNC_END = b"\njudge: func-export end;"
MAX_REPORT_BYTES = 64 * 1024 * 1024
# The stream is capped too, and higher: it legitimately carries the container's whole build log
# and sideeye's text report, while the report file is one document. Capping only the file would
# have left the larger, more exposed side uncapped -- the subject can append to the stream for as
# long as the container lives (found in review).
MAX_STREAM_BYTES = 512 * 1024 * 1024

_JSON_VALUE = re.compile(rb"([0-9a-f]{64}|none);")
_RC_VALUE = re.compile(rb"([0-9]{1,3});")
_STATUS_VALUE = re.compile(rb"(ran|fail);")


def find_one(log, prefix, value_re):
    """The value after the one occurrence of `prefix` in `log`, counted anywhere in the bytes.
    Returns (gate, value): ("sealed", bytes) or a refusal with a detail string."""
    n = log.count(prefix)
    if n == 0:
        return "seal_missing", "no %r in the container's stream" % prefix.decode()
    if n > 1:
        return "seal_ambiguous", "%d occurrences of %r in the container's stream" % (n, prefix.decode())
    at = log.index(prefix) + len(prefix)
    m = value_re.match(log, at)
    if not m:
        # Only the genuine writer can produce a lone malformed token, since a second writer would
        # have made the count 2; a lone malformed one is therefore the writer's defect, refused.
        return "seal_missing", "the one %r token carries no well-formed value" % prefix.decode()
    return "sealed", m.group(1)


def read_regular(path, max_bytes=MAX_REPORT_BYTES):
    """Open without following a link and without blocking, insist on a regular file under the cap,
    read the bytes once. Returns (gate, data)."""
    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        fd = os.open(path, flags)
    except FileNotFoundError:
        # A sealed digest with no file to hold it to: the bytes are not the ones sideeye wrote
        # because there are none.
        return "seal_mismatch", "no file at %s" % path
    except OSError as e:
        # ELOOP is O_NOFOLLOW meeting a symlink, and ENOTDIR a path component that is not a
        # directory -- both are the kind of thing at the name. Everything else (EACCES, EMFILE,
        # ...) is a failure to open, which is a different sentence (found in review).
        kind = errno.ELOOP, errno.ENOTDIR
        gate = "not_a_regular_file" if e.errno in kind else "unreadable"
        return gate, "%s: %s" % (path, e.strerror)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return "not_a_regular_file", "%s is not a regular file (mode %o)" % (path, st.st_mode)
        if st.st_size > max_bytes:
            return "too_large", "%s is %d bytes; the cap is %d" % (path, st.st_size, max_bytes)
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > max_bytes:
                return "too_large", "%s grew past %d bytes while being read" % (path, max_bytes)
        return "ok", b"".join(chunks)
    finally:
        os.close(fd)


def read_stream(path, max_bytes=MAX_STREAM_BYTES):
    """The container's stdout as the host captured it. Read like the report -- one open, no links,
    a regular file, a cap -- because it is the ground every token stands on. One difference: an
    absent stream is `unreadable`, not `seal_mismatch`. There is no digest for the stream to
    disagree with, and a missing log reported as "the bytes are not the ones sideeye sealed" would
    name tampering where there is only absence (found in review)."""
    gate, data = read_regular(path, max_bytes)
    if gate == "seal_mismatch":
        return "unreadable", data
    return gate, data


def seal_report(log, path, max_bytes=MAX_REPORT_BYTES):
    """The replay report: the token sideeye wrote, checked against the file's bytes."""
    gate, value = find_one(log, PREFIX_JSON, _JSON_VALUE)
    if gate != "sealed":
        return {"gate": gate, "channel": "report", "detail": value}
    if value == b"none":
        return {"gate": "seal_missing", "channel": "report",
                "detail": "sideeye reported that the JSON report was not written"}
    want = value.decode()
    rgate, data = read_regular(path, max_bytes)
    if rgate != "ok":
        return {"gate": rgate, "channel": "report", "detail": data}
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        return {"gate": "seal_mismatch", "channel": "report",
                "detail": "sideeye sealed %s; the file at %s hashes to %s" % (want, path, got)}
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as e:
        return {"gate": "not_json", "channel": "report", "detail": "sealed bytes do not parse: %s" % e}
    if not isinstance(doc, dict):
        return {"gate": "not_json", "channel": "report", "detail": "sealed document is not an object"}
    return {"gate": "sealed", "channel": "report", "sha256": want, "doc": doc}


def seal_rc(log):
    gate, value = find_one(log, PREFIX_RC, _RC_VALUE)
    if gate != "sealed":
        return {"gate": gate, "channel": "rc", "detail": value}
    return {"gate": "sealed", "channel": "rc", "value": int(value)}


def seal_func_status(log):
    gate, value = find_one(log, PREFIX_FUNC_STATUS, _STATUS_VALUE)
    if gate != "sealed":
        return {"gate": gate, "channel": "func_status", "detail": value}
    return {"gate": "sealed", "channel": "func_status", "value": value.decode()}


def seal_func_export(log):
    """The export's bytes between the shell's two markers, each of which must appear once and in
    order. A forged block adds a second marker; a marker written into the middle of the real block
    adds one too. The bytes are the shell's own copy of what `timew export` printed."""
    nb, ne = log.count(FUNC_BEGIN), log.count(FUNC_END)
    if nb == 0 or ne == 0:
        return {"gate": "seal_missing", "channel": "func_export",
                "detail": "begin marker x%d, end marker x%d" % (nb, ne)}
    if nb > 1 or ne > 1:
        return {"gate": "seal_ambiguous", "channel": "func_export",
                "detail": "begin marker x%d, end marker x%d" % (nb, ne)}
    b = log.index(FUNC_BEGIN) + len(FUNC_BEGIN)
    e = log.index(FUNC_END)
    if e < b:
        return {"gate": "seal_ambiguous", "channel": "func_export",
                "detail": "the end marker precedes the begin marker"}
    body = log[b:e]
    if not body.strip():
        # The shell prints the markers whether or not the gate ran, so an empty body is a subject
        # that printed nothing -- said in the detail, because the old file-reading form turned this
        # into an empty list and a plain functional `fail` (found in review).
        return {"gate": "not_json", "channel": "func_export",
                "detail": "the export between the markers is empty: the subject printed nothing"}
    try:
        doc = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as e2:
        return {"gate": "not_json", "channel": "func_export", "detail": "export does not parse: %s" % e2}
    if not isinstance(doc, list):
        return {"gate": "not_json", "channel": "func_export", "detail": "export is not an array"}
    return {"gate": "sealed", "channel": "func_export", "doc": doc}


# The channel names live here and nowhere else: `judge_eval` and `refuse_all` both read this, so
# a channel added to one cannot be missing from the other (found in review -- when the two lists
# were separate, a stream that failed to read returned a dict the judge then key-errored on).
CHANNELS = ("rc", "report", "func_status", "func_export")


def judge_eval(log, report_path, max_bytes=MAX_REPORT_BYTES):
    """Every channel the judge's eval reads, each judged on its own."""
    sealers = {"rc": lambda: seal_rc(log),
               "report": lambda: seal_report(log, report_path, max_bytes),
               "func_status": lambda: seal_func_status(log),
               "func_export": lambda: seal_func_export(log)}
    missing = set(CHANNELS) ^ set(sealers)
    if missing:
        raise AssertionError("CHANNELS and the sealers disagree: %r" % sorted(missing))
    return {ch: sealers[ch]() for ch in CHANNELS}


def refuse_all(gate, detail):
    """Every channel refusing for one reason -- the stream itself did not read, so no token in it
    can be counted. Here rather than at the caller, so the channel names live in one place."""
    return {ch: {"gate": gate, "channel": ch, "detail": detail} for ch in CHANNELS}


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) != 3:
        sys.exit("usage: container_seals.py <container.log> <replay.json>")
    with open(argv[1], "rb") as f:
        log = f.read()
    out = judge_eval(log, argv[2])
    print(json.dumps({k: {kk: vv for kk, vv in v.items() if kk != "doc"} for k, v in out.items()},
                     indent=1, sort_keys=True))
    return 0 if all(v["gate"] == "sealed" for v in out.values()) else 1


# ---- selftest -------------------------------------------------------------------------------

def _sha(data):
    return hashlib.sha256(data).hexdigest().encode()


def _clean_log(report_bytes, rc=b"1", status=b"ran", export=b'[{"tags": ["alpha"]}]'):
    # Built from the module's own prefixes: a selftest that spelled the tokens again would keep
    # passing if a prefix moved.
    return (b"some build output\n"
            b"sideeye: the JSON report was not written: (not really -- a diagnostic that shares a word)\n"
            + PREFIX_FUNC_STATUS + status + b";\n"
            + FUNC_BEGIN + export + FUNC_END + b"\n"
            + b"UNKNOWN  something the text report said\n"
            + PREFIX_JSON + _sha(report_bytes) + b";\n"
            + PREFIX_RC + rc + b";\n")


def selftest():
    import tempfile
    failures = []

    def check(name, got, want_gate, channel=None):
        if got["gate"] != want_gate or (channel and got.get("channel") != channel):
            failures.append("%s: got %r, wanted gate %r%s" % (
                name, {k: v for k, v in got.items() if k != "doc"}, want_gate,
                " on %s" % channel if channel else ""))

    work = tempfile.mkdtemp(prefix="container-seals-selftest-")
    try:
        report = b'{"verdict": "FAIL", "explored": 2, "crash_points": 24}\n'
        rpath = os.path.join(work, "run-replay.json")
        with open(rpath, "wb") as f:
            f.write(report)
        log = _clean_log(report)

        # The green: a clean stream seals every channel, and the diagnostic that shares a word with
        # the token's prefix is not counted as one.
        out = judge_eval(log, rpath)
        for ch in out.values():
            check("clean:" + ch["channel"], ch, "sealed")
        if out["report"].get("doc", {}).get("verdict") != "FAIL" or out["rc"].get("value") != 1 \
                or out["func_status"].get("value") != "ran" or out["func_export"].get("doc") != [{"tags": ["alpha"]}]:
            failures.append("clean: sealed values not read back: %r" % {k: {kk: vv for kk, vv in v.items() if kk != 'doc'} for k, v in out.items()})

        # No token at all, and sideeye's own `none`.
        check("missing", seal_report(log.replace(b"sideeye: json sha256=" + _sha(report) + b";\n", b""), rpath),
              "seal_missing", "report")
        check("none", seal_report(log.replace(_sha(report), b"none"), rpath), "seal_missing", "report")

        # A forgery beside the real token: two occurrences, whichever order.
        forged = b'{"verdict": "PASS", "explored": 2, "crash_points": 24}\n'
        check("duplicate", seal_report(log + b"sideeye: json sha256=" + _sha(forged) + b";\n", rpath),
              "seal_ambiguous", "report")

        # Review's C1: newline-less bytes ahead of the real token take its line start away, then the
        # forger writes its own token from a fresh line. Anchored counting would see one (the
        # forgery); counting anywhere sees two.
        hidden = log.replace(b"\nsideeye: json sha256=", b"\nxxxxxxxxxxxxxxxxxxxxsideeye: json sha256=")
        hidden += b"\nsideeye: json sha256=" + _sha(forged) + b";\n"
        with open(rpath, "wb") as f:
            f.write(forged)
        check("hidden-then-forged", seal_report(hidden, rpath), "seal_ambiguous", "report")
        # The line-anchored reading of the same stream, for the record: it finds exactly one token,
        # the forgery, and it matches the rewritten file. This is the reading the module must not have.
        anchored = [l for l in hidden.split(b"\n") if l.startswith(PREFIX_JSON)]
        if len(anchored) != 1 or anchored[0][len(PREFIX_JSON):-1] != _sha(forged):
            failures.append("the hidden-then-forged stream no longer demonstrates the anchored hole")

        # The file rewritten after the seal.
        check("mismatch", seal_report(log, rpath), "seal_mismatch", "report")
        with open(rpath, "wb") as f:
            f.write(report)

        # The token's value malformed (only the genuine writer can produce a lone one).
        check("malformed", seal_report(log.replace(_sha(report) + b";", b"zz;"), rpath), "seal_missing", "report")

        # A FIFO, a symlink and a directory at the report's name: refused, and the FIFO without a
        # writer does not hang the open.
        fifo = os.path.join(work, "fifo.json")
        os.mkfifo(fifo)
        check("fifo", seal_report(log, fifo), "not_a_regular_file", "report")
        link = os.path.join(work, "link.json")
        os.symlink(rpath, link)
        check("symlink", seal_report(log, link), "not_a_regular_file", "report")
        d = os.path.join(work, "dir.json")
        os.mkdir(d)
        check("directory", seal_report(log, d), "not_a_regular_file", "report")
        check("absent", seal_report(log, os.path.join(work, "nope.json")), "seal_mismatch", "report")

        # The size cap, with a small cap so the test does not write 64 MiB.
        check("too-large", seal_report(log, rpath, max_bytes=8), "too_large", "report")

        # An open that fails for a reason that is not the kind of the thing at the name.
        noperm = os.path.join(work, "noperm.json")
        with open(noperm, "wb") as f:
            f.write(report)
        os.chmod(noperm, 0)
        if os.geteuid() != 0:   # root opens it anyway; the case is about the errno, not the mode
            check("unreadable", seal_report(log, noperm), "unreadable", "report")
        os.chmod(noperm, 0o644)

        # The stream itself: capped, and refused when something else is at its name.
        lp = os.path.join(work, "stream.log")
        with open(lp, "wb") as f:
            f.write(log)
        g, _ = read_stream(lp)
        if g != "ok":
            failures.append("read_stream on a plain file: %r, wanted ok" % g)
        g, _ = read_stream(lp, max_bytes=8)
        if g != "too_large":
            failures.append("read_stream with a cap of 8: %r, wanted too_large" % g)
        g, _ = read_stream(os.path.join(work, "no-such.log"))
        if g != "unreadable":
            failures.append("read_stream on an absent file: %r, wanted unreadable" % g)

        # Sealed bytes that are not a JSON object.
        junk = b"not json\n"
        jpath = os.path.join(work, "junk.json")
        with open(jpath, "wb") as f:
            f.write(junk)
        check("not-json", seal_report(_clean_log(junk), jpath), "not_json", "report")

        # rc and func-status: missing, doubled, malformed.
        check("rc-missing", seal_rc(log.replace(PREFIX_RC, b"judge: replay-rx=")), "seal_missing", "rc")
        check("rc-double", seal_rc(log + PREFIX_RC + b"0;\n"), "seal_ambiguous", "rc")
        check("rc-malformed", seal_rc(log.replace(PREFIX_RC + b"1;", PREFIX_RC + b"one;")), "seal_missing", "rc")
        check("status-double", seal_func_status(log + PREFIX_FUNC_STATUS + b"ran;\n"), "seal_ambiguous", "func_status")
        check("status-malformed", seal_func_status(log.replace(b"func-status=ran;", b"func-status=okay;")),
              "seal_missing", "func_status")

        # The export block: a second block, a marker inside the block, no block, a non-array.
        check("export-double", seal_func_export(log + FUNC_BEGIN + b"[]" + FUNC_END + b"\n"),
              "seal_ambiguous", "func_export")
        check("export-marker-inside",
              seal_func_export(log.replace(b'"alpha"', b'"alpha"' + FUNC_END + b"\n" + FUNC_BEGIN)),
              "seal_ambiguous", "func_export")
        check("export-missing", seal_func_export(log.replace(FUNC_BEGIN, b"")), "seal_missing", "func_export")
        check("export-object", seal_func_export(_clean_log(report, export=b"{}")), "not_json", "func_export")
        check("export-garbage", seal_func_export(_clean_log(report, export=b"")), "not_json", "func_export")

        # The CLI agrees with judge_eval: 0 on the clean pair, 1 with the report rewritten.
        lpath = os.path.join(work, "container.log")
        with open(lpath, "wb") as f:
            f.write(log)
        import io
        import contextlib
        with contextlib.redirect_stdout(io.StringIO()):
            rc_clean = main(["container_seals.py", lpath, rpath])
            with open(rpath, "wb") as f:
                f.write(forged)
            rc_dirty = main(["container_seals.py", lpath, rpath])
        if rc_clean != 0 or rc_dirty != 1:
            failures.append("CLI: clean rc %d (wanted 0), rewritten rc %d (wanted 1)" % (rc_clean, rc_dirty))
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)

    if failures:
        print("container_seals selftest: %d failure(s)" % len(failures), file=sys.stderr)
        for line in failures:
            print("  " + line, file=sys.stderr)
        return 1
    print("container_seals selftest: ok (every channel seals on a clean stream; missing, doubled, "
          "hidden-then-forged, rewritten, malformed, FIFO, symlink, directory, oversized and unparsable refuse)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
