#!/usr/bin/env python3
"""#400: a case path that is not a regular file is refused, and the run returns.

Why this is not a `zig build test` case. The defect being guarded is a process that
never returns, and a unit test cannot bound its own runtime. The unit-test steps in
CI carry no `timeout-minutes`, so a regression would hold a runner for the GitHub
default of six hours instead of failing. The deadline has to live outside the process
it is measuring.

Four groups. Two paths read caller-named files and they are bounded differently, because
what they are allowed to refuse differs:

  case path is a FIFO                       -- refuse by kind (#400)
    1. the run returns inside the deadline  <- O_NONBLOCK on the open
    2. it exits 3 (SETUP ERROR)
    3. it says the case could not be READ   <- the descriptor is classified first
    4. and NOT that it could not be parsed  <- the empty-file path is not taken
  --config on a FIFO whose writer is late   -- must NOT refuse by kind
    5. the config is not declared unreadable
    6. the config's contents arrive         <- the read waits and retries
    7. the run gets past setup
  control: a regular file with invalid contents
    8-10. exit 3, the PARSE message, not the read message
  --config is bounded                       -- it waits, but not forever
    11-16. no writer / idle writer -> refused AT the deadline (a lower bound on
           elapsed time, not just the message: a build that stops retrying refuses
           the same way in milliseconds); late writer -> read; /dev/zero -> stopped
           by the byte cap, not the deadline; /dev/null and an empty regular file ->
           answered at once, never retried

Groups 5-7 and 11-16 are the only things in the repository that separate the shipped
`--config` behaviour from two designs that were tried and rejected: passing `O_NONBLOCK`
with nothing to handle it (which reads a late config as empty), and clearing the flag
after the open (which does the same, and leaves an idle writer unbounded). Both leave
`zig build test` fully green.

Without (3) the run still returns and still exits 3: a FIFO with no writer answers EOF
on the first read, the empty buffer fails to parse as JSON, and the next refusal catches
it with the wrong reason. The control at the bottom pins that difference by feeding a
real file whose contents are invalid and requiring the *other* message — so a change
that deleted the classification would turn the FIFO case's message into the control's
and be caught here rather than passing as "still exits 3".

Usage: case-path-deadline.py [path-to-sideeye]
"""

import os
import shutil
import subprocess
import sys
import threading
import time
import tempfile

# Measured cost of the refusal on a warm local run: 0.26 s. Five seconds is ~20x that,
# which leaves room for a cold CI runner without letting a multi-second regression pass
# as "returned". The defect this bounds is unbounded, not slow, so the margin does not
# need to be generous.
DEADLINE = 5.0

READ_MSG = "could not be read"
PARSE_MSG = "could not be parsed"
CONFIG_UNREADABLE = "--config could not be read"

# How long the config's writer waits before writing. It must outlast the binary's
# start-up and its attempt to read, or the writer wins the race and the pipe already
# holds the config — which is how the first version of that leg passed against a build
# with the defect in it.
WRITER_DELAY = 1.0


class Failure(Exception):
    """The thing under test misbehaved."""


class Apparatus(Exception):
    """The harness could not run the thing under test at all.

    Kept distinct from Failure because it must not read as a defect in the binary.
    The precheck below cannot catch every case: `os.access(X_OK)` is true for a
    binary built for another architecture, and running one raises OSError from
    `Popen` rather than producing an exit code. That exact accident happened during
    development — a Linux cross-build left in `zig-out` on a macOS host — and a
    traceback exiting 1 was indistinguishable from a real failure.
    """


def run(binary, case_path):
    """Return (rc, combined output). Raises on a deadline or a dead apparatus."""
    try:
        p = subprocess.run(
            [binary, "replay", case_path],
            capture_output=True,
            text=True,
            timeout=DEADLINE,
        )
    except subprocess.TimeoutExpired:
        raise Failure(
            f"`sideeye replay` did not return within {DEADLINE}s for {case_path!r}. "
            "This is the #400 defect: the open waits for a writer that never comes."
        )
    except OSError as e:
        raise Apparatus(f"could not execute {binary!r}: {e}")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def check(label, cond, detail):
    if cond:
        print(f"  ok   {label}")
        return True
    print(f"  FAIL {label}: {detail}")
    return False


def main():
    binary = sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/sideeye"
    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        print(f"not an executable: {binary}", file=sys.stderr)
        return 2

    # $HOME rather than the system temp dir: on macOS the temp prefix is blocked for
    # some of the tooling around this repo, and a FIFO there is awkward to clean up.
    work = tempfile.mkdtemp(prefix="sideeye-400-", dir=os.path.expanduser("~"))
    ok = True
    try:
        fifo = os.path.join(work, "case.json")
        os.mkfifo(fifo)

        print(f"case path is a FIFO with no writer ({fifo}):")
        try:
            rc, out = run(binary, fifo)
        except Apparatus as e:
            print(f"  APPARATUS {e}")
            return 2
        except Failure as e:
            print(f"  FAIL {e}")
            return 1
        ok &= check("returned inside the deadline", True, "")
        ok &= check("exit 3 (SETUP ERROR)", rc == 3, f"exit was {rc}")
        ok &= check(
            f"the refusal says {READ_MSG!r}",
            READ_MSG in out,
            f"output was: {out.strip()[:300]}",
        )
        ok &= check(
            f"and not {PARSE_MSG!r}",
            PARSE_MSG not in out,
            "the run read the FIFO as an empty file and blamed the JSON — "
            "the descriptor was not classified before reading",
        )

        # The control. A real file that is unreadable-as-a-case must reach the OTHER
        # refusal; without this, an implementation that answered "could not be read" for
        # every input would pass everything above.
        bad = os.path.join(work, "not-a-case.json")
        with open(bad, "w") as f:
            f.write("this is not json\n")

        # The other half of the fix, and the reason it is here rather than in a unit
        # test: the correct behaviour is *waiting*. `O_NONBLOCK` belongs only where the
        # descriptor is about to be classified; passed unconditionally it reaches
        # `--config`, whose read then fails EAGAIN on a pipe the writer has not filled
        # yet. The right implementation blocks and the wrong one returns fast, so an
        # in-process assertion cannot separate them — the deadline can.
        cfg_text = (
            '[world]\nstate = "%s"\n\n[define]\nsetup = "true"\n'
            'operation = "true"\ncheck = "true"\n' % os.path.join(work, "state")
        )
        print("\n--config on a pipe whose writer is slow (the P0 regression's own test):")
        # A named FIFO, not an inherited descriptor and not a shell pipeline. Both of
        # those were tried and neither reproduces the regression on macOS: `/dev/stdin`
        # and `/dev/fd/N` are resolved there as a dup of the existing description, so a
        # fresh `O_NONBLOCK` never reaches the pipe and the broken build passes. A FIFO
        # opened by name gets its own description on both platforms, which is what the
        # flag acts on.
        #
        # The shape is the regression's own: the reader arrives first and the config is
        # written a second later. Blocking, that waits and then reads; non-blocking, the
        # first read fails EAGAIN and the config is declared unreadable.
        cfg_fifo = os.path.join(work, "cfg.fifo")
        os.mkfifo(cfg_fifo)
        out3 = ""
        rc3 = None
        try:
            p3 = subprocess.Popen(
                [os.path.abspath(binary), "explore", "--config", cfg_fifo],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
        except OSError as e:
            print(f"  APPARATUS could not start the config run: {e}")
            return 2
        try:
            # Long enough to lose the race deliberately: the binary has to reach its read
            # before anything is written. With the writer immediate, the broken build
            # passes this leg — which is how the first version of it measured nothing.
            time.sleep(WRITER_DELAY)
            # Non-blocking on the write end too: against a build with the defect the
            # child has already given up and closed its descriptor, and a blocking open
            # here would then wait for a reader that is never coming — the harness would
            # hang on the very build it exists to catch. ENXIO means exactly that, and
            # the assertions below read the child's own output rather than this.
            try:
                wfd = os.open(cfg_fifo, os.O_WRONLY | os.O_NONBLOCK)
            except OSError:
                wfd = -1
            if wfd != -1:
                with os.fdopen(wfd, "w") as wf:
                    wf.write(cfg_text)
            out3 = p3.communicate(timeout=DEADLINE)[0] or ""
            rc3 = p3.returncode
        except subprocess.TimeoutExpired:
            p3.kill()
            p3.communicate()
            print(f"  FAIL the config read did not return within {DEADLINE}s")
            return 1
        # Two symptoms, because the defect has two faces depending on whether a writer
        # has opened the FIFO yet. With one open and nothing sent, a non-blocking read
        # fails EAGAIN and the config is declared unreadable. With none open, the same
        # read gets EOF and the config arrives *empty* — which parses, and then fails on
        # a missing key. Measured: this harness's own writer opens late, so the mutant
        # takes the second path, and an assertion that only looked for the first would
        # have passed against it.
        ok &= check(
            "the config is not declared unreadable",
            CONFIG_UNREADABLE not in out3,
            "a non-blocking read of a pipe with a writer but no bytes yet failed. "
            f"Output: {out3.strip()[:200]}",
        )
        ok &= check(
            "the config's contents actually arrived",
            "state is required" not in out3,
            "the config was read as EMPTY — the same 'could not be read becomes was "
            "empty' shape as #400, reached through a flag that should not be on this "
            f"open. Output: {out3.strip()[:200]}",
        )
        ok &= check(
            "and the run got past setup (exit is not 3)",
            rc3 != 3,
            f"exit was 3; output: {out3.strip()[:200]}",
        )

        print(f"\ncontrol — a regular file with invalid contents ({bad}):")
        try:
            rc2, out2 = run(binary, bad)
        except Apparatus as e:
            print(f"  APPARATUS {e}")
            return 2
        except Failure as e:
            print(f"  FAIL {e}")
            return 1
        ok &= check("exit 3 (SETUP ERROR)", rc2 == 3, f"exit was {rc2}")
        ok &= check(
            f"the refusal says {PARSE_MSG!r}",
            PARSE_MSG in out2,
            f"output was: {out2.strip()[:300]}",
        )
        ok &= check(
            f"and not {READ_MSG!r}",
            READ_MSG not in out2,
            "a readable regular file was reported as unreadable — the classification "
            "is refusing ordinary files",
        )

        ok &= config_legs(binary, work, cfg_text)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print()
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


def config_legs(binary, work, cfg_text):
    """The `--config` read is bounded: it waits for a peer, but not forever.

    Four inputs, and each one is here because it separates the shipped design from a
    design that was tried and rejected:

      - FIFO with no writer      -> the open used to wait forever
      - FIFO, writer open, no data -> `fcntl`-clearing designs block here with no
                                      deadline to stop them (measured, >3 s)
      - /dev/zero                -> an unbounded read; the byte cap must fire, not the
                                    deadline, so this one is also a timing assertion
      - /dev/null and an empty regular file
                                 -> must NOT be retried. A rule that retries any
                                    zero-length read spends the whole deadline here and
                                    ends with the wrong message. This is the pair that
                                    pins the retry predicate to "a peer may still
                                    arrive" rather than "no bytes came back".
    """
    ok = True

    def probe(label, path, want_rc, want_msg, not_msg, max_s=None, min_s=None, prep=None):
        # `min_s` is what makes the EAGAIN arm of the retry rule observable. Deleting
        # that arm leaves "bounded" retrying on every error, so the idle-writer legs
        # still end at the deadline with the same message and the same exit code —
        # measured, that mutation survived a version of this leg that asserted only the
        # outcome. What separates them is that a build which does not recognise EAGAIN
        # gives up at once instead of waiting.
        nonlocal ok
        t0 = time.time()
        if prep:
            prep()
        try:
            p = subprocess.run(
                [os.path.abspath(binary), "explore", "--config", path],
                capture_output=True, text=True, timeout=DEADLINE,
            )
        except subprocess.TimeoutExpired:
            print(f"  FAIL {label}: did not return within {DEADLINE}s")
            ok = False
            return
        except OSError as e:
            raise Apparatus(f"could not run the config probe: {e}")
        el = time.time() - t0
        out = (p.stdout or "") + (p.stderr or "")
        good = p.returncode == want_rc and want_msg in out and not_msg not in out
        if max_s is not None and el > max_s:
            good = False
        if min_s is not None and el < min_s:
            good = False
        mark = "ok " if good else "FAIL"
        print(f"  {mark} {label} (rc={p.returncode}, {el:.2f}s)")
        if not good:
            print(f"       want rc={want_rc}, {want_msg!r} present, {not_msg!r} absent"
                  + (f", under {max_s}s" if max_s is not None else "")
                  + (f", at least {min_s}s" if min_s is not None else ""))
            print(f"       got: {out.strip()[:160]}")
            ok = False

    print("\n--config is bounded:")

    f1 = os.path.join(work, "cfg-nowriter.fifo")
    os.mkfifo(f1)
    # min_s: it has to WAIT, not just refuse. A build that stops retrying answers the
    # same way in milliseconds, which is a different program with the same output.
    probe("FIFO, no writer -> deadline", f1, 3, READ_MSG, "state is required", min_s=1.5)

    f2 = os.path.join(work, "cfg-idle.fifo")
    os.mkfifo(f2)
    held = {}

    def open_writer():
        # Held open for the run's duration, writing nothing. Retried, because a
        # non-blocking write-open of a FIFO with no reader fails ENXIO and sideeye may
        # not have opened its end yet.
        #
        # **The retry is not politeness; without it this leg silently stops measuring
        # what it is for.** A writer that never attaches leaves the input identical to
        # the no-writer leg above: the run still waits the full deadline, still satisfies
        # `min_s`, and **a build that does not recognise EAGAIN passes** — measured, by
        # forcing the failure and running the wrong-errno mutant against it. The
        # assertion after the probe is what turns that from a green run into a red one.
        for _ in range(300):
            try:
                held["fd"] = os.open(f2, os.O_WRONLY | os.O_NONBLOCK)
                return
            except OSError:
                time.sleep(0.01)

    threading.Thread(target=open_writer, daemon=True).start()
    before = ok
    probe("FIFO, writer idle -> deadline", f2, 3, READ_MSG, "state is required", min_s=1.5)
    if "fd" in held:
        os.close(held["fd"])
    elif before == ok:
        # Only when the probe itself passed. A build that refuses for an unrelated
        # reason returns before the writer can attach, and blaming EAGAIN there would
        # send triage at the wrong mutation — measured with an isFifoFd-disabled build,
        # which refuses in 0.01 s and is already red from the probe above.
        print("  FAIL FIFO, writer idle: the writer never attached, so this leg measured "
              "the no-writer case instead — and that version of it passes a build "
              "that ignores EAGAIN")
        ok = False
    else:
        print("  note FIFO, writer idle: the writer never attached, but the probe was "
              "already failing — this leg's own predicate is unmeasured either way")

    f3 = os.path.join(work, "cfg-late.fifo")
    os.mkfifo(f3)

    wrote = {}

    def late_writer():
        # Non-blocking on the write end, for the reason the case leg above gives: against
        # a build that refuses fast there is no reader left, and a blocking open would
        # wait for one that is never coming. `daemon=True` would hide that rather than
        # prevent it.
        time.sleep(WRITER_DELAY)
        for _ in range(100):
            try:
                fd = os.open(f3, os.O_WRONLY | os.O_NONBLOCK)
            except OSError:
                time.sleep(0.01)
                continue
            os.write(fd, cfg_text.encode())
            os.close(fd)
            wrote["ok"] = True
            return

    threading.Thread(target=late_writer, daemon=True).start()
    # Past the config stage: exit 2 with a verdict-side refusal means the config parsed.
    before = ok
    probe("FIFO, writer late -> config read", f3, 2, "no_shim_marker", READ_MSG)
    if "ok" not in wrote and before == ok:
        # Same guard as the idle leg: a writer that gave up silently turns an apparatus
        # failure into what reads as a defect in the binary. Only reported when the probe
        # itself passed, so a build that is red for its own reason is not mislabelled.
        print("  FAIL FIFO, writer late: the writer never wrote, so this leg did not "
              "measure whether a late config is picked up")
        ok = False

    # The cap, not the deadline: a run that took ~2 s here would mean the deadline
    # fired, i.e. the byte ceiling never did.
    probe("/dev/zero -> cap, not deadline", "/dev/zero", 3, READ_MSG,
          "state is required", max_s=1.0)

    # The two that must not be retried. A margin well under the engine's deadline: if
    # either is being retried, this takes ~2 s and the message changes as well.
    probe("/dev/null -> empty, not retried", "/dev/null", 3, "state is required",
          READ_MSG, max_s=1.0)
    empty = os.path.join(work, "empty.toml")
    open(empty, "w").close()
    probe("empty regular -> empty, not retried", empty, 3, "state is required",
          READ_MSG, max_s=1.0)

    return ok


if __name__ == "__main__":
    sys.exit(main())
