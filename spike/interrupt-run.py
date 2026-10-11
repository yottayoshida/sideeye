#!/usr/bin/env python3
"""Stop a Sideeye run with a signal while a child it started is running, and judge the end (#819).

Usage: interrupt-run.py <SIGNAME> <marker> <ignore-hup: 0|1> <command...>

The command starts with SIGINT, SIGTERM and SIGHUP at their default (or SIGHUP ignored, for the
`nohup` control): a `&` job of a non-interactive shell starts with SIGINT ignored, which a
correct engine keeps ignored, so the suite's own shell cannot stand in for a terminal. The signal
goes only once a process carrying <marker> as an argv element is running; sent earlier, it would
reach an engine with no child and a broken engine would pass. Make <marker> unique to the run
(the callers add their shell's pid): only processes that appear during the run are judged, and
only those in the session the command starts are killed, so nothing else on the host is touched.

Exit 0 when the run ended by that signal, nothing carrying <marker> (or any comma-separated
marker in IR_ALSO) is left, no cgroup directory of the run's is left, and stderr has the stop
line. With ignore-hup 1, exit 0 when the run was not ended by any signal. IR_STDIN names a file
written to the command's stdin, which then stays open.
"""
import os
import signal
import subprocess
import sys
import time

sig = getattr(signal, sys.argv[1])
marker = sys.argv[2].encode()
ignore_hup = sys.argv[3] == "1"
cmd = sys.argv[4:]
also = [m.encode() for m in os.environ.get("IR_ALSO", "").split(",") if m]


def processes():
    """(pid, argv) for every process but this one."""
    me = os.getpid()
    if os.path.isdir("/proc/self"):
        for p in os.listdir("/proc"):
            if p.isdigit() and int(p) != me:
                try:
                    yield int(p), open("/proc/%s/cmdline" % p, "rb").read().split(b"\0")
                except OSError:
                    pass
        return
    out = subprocess.run(["ps", "-axww", "-o", "pid=,command="], capture_output=True).stdout
    for line in out.splitlines():
        parts = line.split()
        if parts and int(parts[0]) != me:
            yield int(parts[0]), parts[1:]


def carrying(markers):
    """Pids carrying a marker that were not there before the run: only those are the run's. The
    command itself is never one — where `ps` is all there is, its arguments split on spaces carry
    the marker too."""
    return {pid: argv for pid, argv in processes() if pid not in present_before and pid != launched and any(m in argv[1:] for m in markers)}


def cgroup_dirs():
    try:
        rel = [l[3:] for l in open("/proc/self/cgroup").read().splitlines() if l.startswith("0::")][0]
        return sorted(d for d in os.listdir("/sys/fs/cgroup" + rel) if d.startswith("sideeye-"))
    except (OSError, IndexError):
        return []


def defaults():
    for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, signal.SIG_IGN if ignore_hup and s == signal.SIGHUP else signal.SIG_DFL)


present_before = set()
launched = None
present_before = set(carrying([marker] + also))


def ours(pid):
    try:
        return os.getsid(pid) == p.pid
    except OSError:
        return False


cg_before = cgroup_dirs()
stdin = subprocess.PIPE if os.environ.get("IR_STDIN") else subprocess.DEVNULL
p = subprocess.Popen(cmd, preexec_fn=defaults, start_new_session=True, stdin=stdin, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
launched = p.pid
if stdin == subprocess.PIPE:
    p.stdin.write(open(os.environ["IR_STDIN"], "rb").read())
    p.stdin.flush()
deadline = time.time() + 60
while not carrying([marker]):
    if p.poll() is not None or time.time() > deadline:
        p.kill()
        sys.exit("the marked child never ran (the command ended %r)" % p.returncode)
    time.sleep(0.05)
p.send_signal(sig)
try:
    p.wait(timeout=20)
except subprocess.TimeoutExpired:
    p.kill()
    p.wait()
    sys.exit("the run had not ended 20 s after the signal")
time.sleep(1)
left, cg_after = carrying([marker] + also), cgroup_dirs()
for pid in [pid for pid in left if ours(pid)]:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
err = p.stderr.read()
if ignore_hup:
    if p.returncode < 0:
        sys.exit("a SIGHUP ignored at startup ended the run (signal %d)" % -p.returncode)
    sys.exit(0)
if p.returncode != -sig:
    sys.exit("wanted the run to end by signal %d, it ended %r; stderr %r" % (sig, p.returncode, err[-300:]))
if left:
    sys.exit("left running: %r" % {pid: b" ".join(argv).decode(errors="replace")[:120] for pid, argv in left.items()})
if cg_after != cg_before:
    sys.exit("cgroup directories left: %r" % sorted(set(cg_after) - set(cg_before)))
if b"stopped by signal %d" % sig not in err:
    sys.exit("no stop line on stderr: %r" % err[-300:])
