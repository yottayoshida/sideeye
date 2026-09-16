#!/usr/bin/env python3
"""The launcher's memory for the loop-closure measurement (#515, #592).

`judge.sh` opens with "nothing the agent can edit is trusted", and ADR 0058 said where that
sentence stopped being true: the judge's INPUTS. The transcript and the control verdicts sit in
`spike/runs/` on the host, the seal sits beside the stage, the judge's own scripts sit in this
repository, and the agent runs as the same user with `Bash` and `Write`. The digest `audit`
verifies against was computed from the file after the run and handed over by the operator — only
as good as the file was, and as honest as whoever typed it.

This script is where the digests live instead. It is python rather than shell for one measured
reason: `sh` reads a script as it runs, so for the tens of minutes an agent is alive the launcher's
unread second half is an ordinary file the agent can write — and so is `judge.sh` for the minutes
its `docker build` takes. CPython compiles this whole file before the first line runs. The shell
launchers do their pre-run gates and then `exec` into `judge` below, so nothing of them survives
into the agent's run; `judge.sh` is fed to `sh -s` on stdin from bytes this process has just
verified, so the bytes that run are the bytes that were checked.

    measure.py run --out FILE --err FILE --cwd DIR [--roots PATH ...] -- CMD ...
        Spawn CMD in its own session, write its stdout to FILE through this process's handle
        while hashing the stream, wait, then list what it left behind — processes still in its
        group, containers mounting any of --roots — record them, and kill/stop them. One JSON
        line on stdout: {"sha256", "bytes", "rc", "leftover_pids", "leftover_containers", ...}.
        A SIGINT to this process kills the group and is recorded; in a new session the
        operator's Ctrl-C would otherwise never reach the agent. `judge` records an
        interrupted run and does not judge it (`resume` does, on request).

    measure.py judge --root ROOT --repo REPO --variant cli|mcp --prompt FILE [--allow-mcp NAME]
                     [--meta k=v ...] [--judge PATH] -- CMD ...
        Take the pre-run digests (the seal's manifest and protocol, the control verdicts, the
        judge's scripts, the prompt), run the agent as `run` does, write agent-meta.json, snapshot
        repo/'s working tree, write $ROOT/inputs.json, then run audit -> eval -> [secondary] ->
        finalize, verifying before each step that everything the step reads still matches, and
        hashing each step's output as it lands. Stops without calling the judge when anything
        differs, naming what.

    measure.py resume --root ROOT --repo REPO [--from STEP] [--judge PATH]
        Continue a run that stopped (a container that failed, say) from $ROOT/inputs.json,
        with the same checks. The operator supplies no digest; the file the launcher wrote
        after the agent's death is the only source.

    measure.py --selftest
        One case per refusal channel, each asserting the reason it is named for.

Standard library only — `python3 -I` implies `-P`, so a sibling module could not be imported
anyway, and nothing here needs one. The interpreter, its stdlib, `sh`, `ps` and `docker` are
trusted; they are outside the digest set and ADR 0066 says so.
"""
import argparse
import hashlib
import json
import os
import select
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

STEPS = ("audit", "eval", "secondary", "finalize")
# What each judge step leaves in $RESULTS, and what the next step must find unchanged.
STEP_OUTPUT = {"audit": "audit.json", "eval": "run-verdict.json",
               "secondary": "run-secondary.json", "finalize": "manifest.json"}
# Further files a step leaves that a later step reads, recorded when present: eval's rebuild
# writes the stage-diff record and appends to the rebuild history, and finalize reads the history
# for its printout across attempts (found in review).
# eval's verdict now rests on the container's own stdout, read back as sealed tokens (#597); the
# stream is recorded beside the verdict so finalize holds the ground the verdict stood on.
STEP_EXTRA = {"eval": ["run-stage-diff.json", "run-stage-diffs.jsonl"]}
# Not "recorded when present" like the rest: eval's verdict is read out of this stream, and the run
# whose binary is the agent's is the one that would benefit from the file being gone. A step that
# does not leave them is refused rather than attested for what it did leave (found in review).
STEP_EXTRA_REQUIRED = {"eval": ["run-container.log", "run-container.err"]}
CHUNK = 65536


class Refusal(Exception):
    """Something the launcher recorded is not what is on disk now. The message names it."""


# ---------------------------------------------------------------- digests

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def digest_files(paths):
    """{abspath: sha256} for every path; a path that is not a regular file is a refusal, not a
    skip — an input the launcher cannot read is not an input it can vouch for."""
    out = {}
    for p in paths:
        p = os.path.abspath(p)
        if not os.path.isfile(p):
            raise Refusal("cannot record an input that is not a regular file: %s" % p)
        out[p] = sha256_file(p)
    return out


def tree_snapshot(root, skip_top=(".git",)):
    """Every entry under root except the skipped top-level names: type, owner bits, and the
    content digest of regular files (a symlink's digest is over its target text). Sorted, so the
    tree digest is a function of the tree and nothing else."""
    root = os.path.abspath(root)
    entries = {}
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        if rel_dir == ".":
            dirnames[:] = [d for d in dirnames if d not in skip_top]
        dirnames.sort()
        for name in sorted(dirnames + filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.normpath(os.path.join(rel_dir, name)) if rel_dir != "." else name
            st = os.lstat(full)
            mode = stat.S_IMODE(st.st_mode) & 0o700
            if stat.S_ISLNK(st.st_mode):
                kind, digest = "link", sha256_bytes(os.readlink(full).encode("utf-8", "surrogateescape"))
            elif stat.S_ISDIR(st.st_mode):
                kind, digest = "dir", ""
            elif stat.S_ISREG(st.st_mode):
                kind, digest = "file", sha256_file(full)
            else:
                kind, digest = "other", ""
            entries[rel] = "%s %03o %s" % (kind, mode, digest)
    lines = "".join("%s %s\n" % (v, k) for k, v in sorted(entries.items()))
    return {"root": root, "entries": entries, "sha256": sha256_bytes(lines.encode("utf-8", "surrogateescape"))}


def tree_diff(before, after):
    """The relative paths whose line differs between two snapshots' entries."""
    keys = set(before) | set(after)
    return sorted(k for k in keys if before.get(k) != after.get(k))


# ---------------------------------------------------------------- leftovers

def group_members(pgid):
    """pids still in process group pgid, other than this process. Linux reads /proc — the
    acceptance container carries no `ps` — and Darwin asks `ps`, whose `sess` column is 0 for
    every process there (measured 2026-09-16), so the group is the unit, not the session."""
    me = os.getpid()
    found = []
    if os.path.isdir("/proc") and sys.platform.startswith("linux"):
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open("/proc/%s/stat" % name, "rb") as f:
                    raw = f.read()
            except OSError:
                continue
            # `pid (comm) state ppid pgrp ...` — comm may hold spaces and parentheses.
            tail = raw[raw.rfind(b")") + 2:].split()
            if len(tail) > 2 and tail[2].isdigit() and int(tail[2]) == pgid and int(name) != me:
                found.append(int(name))
        return sorted(found)
    try:
        out = subprocess.run(["ps", "-axo", "pid=,pgid="], capture_output=True, text=True, check=False).stdout
    except OSError:
        return None
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            if int(parts[1]) == pgid and int(parts[0]) != me:
                found.append(int(parts[0]))
    return sorted(found)


def containers_mounting(roots, docker="docker"):
    """Running containers whose bind mounts touch any of roots — the mount's SOURCE on the host,
    read from `docker inspect`, in either direction (a mount of the root or below it, or of an
    ancestor that contains it). `docker ps --filter volume=` matches the destination path
    inside the container, which is why it was not used. None when docker is not there to ask:
    "not observed" is not "none"."""
    roots = [os.path.abspath(r) for r in roots]
    try:
        ps = subprocess.run([docker, "ps", "-q"], capture_output=True, text=True, check=False)
    except OSError:
        return None
    if ps.returncode != 0:
        return None
    ids = [i for i in ps.stdout.split() if i]
    if not ids:
        return []
    insp = subprocess.run([docker, "inspect"] + ids, capture_output=True, text=True, check=False)
    if insp.returncode != 0:
        return None
    try:
        data = json.loads(insp.stdout)
    except ValueError:
        return None
    hits = []
    for c in data:
        # A tmpfs mount has an empty Source; matched as a prefix it would touch every root and
        # stop a container that has nothing to do with the run (found in review).
        sources = [s for s in (m.get("Source") for m in c.get("Mounts") or []) if s]
        touching = sorted({s for s in sources for r in roots
                           if s == r or s.startswith(r + os.sep) or r.startswith(s.rstrip(os.sep) + os.sep)})
        if touching:
            hits.append({"id": c.get("Id", "")[:12], "image": c.get("Config", {}).get("Image"),
                         "mounts": touching})
    return hits


def run_recorded(cmd, out_path, err_path, cwd, roots, docker="docker"):
    """The record is written through THIS process's handle. The subject's stdout is a pipe, so
    `ftruncate(1, 0)` fails with EINVAL (measured 2026-09-09; the file form lost the whole record
    that way), and the digest is over the bytes as they flowed — a file edited by name during the
    run disagrees with it. The subject runs in a new session: its own process group, no
    controlling terminal."""
    h = hashlib.sha256()
    nbytes = 0
    state = {"interrupted": False, "proc": None}

    def on_signal(signum, _frame):
        state["interrupted"] = True
        p = state["proc"]
        if p is not None:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass

    old = [(s, signal.signal(s, on_signal)) for s in (signal.SIGINT, signal.SIGTERM)]
    try:
        # Unbuffered: every chunk reaches the file as it is read, so the file never lags the
        # stream (a buffered writer flushing at the end overwrote a by-name append and made the
        # file agree with the digest by accident — the first version of the selftest found it).
        with open(out_path, "wb", buffering=0) as out, open(err_path, "wb") as err, open(os.devnull, "rb") as devnull:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=err, stdin=devnull,
                                    cwd=cwd, start_new_session=True, close_fds=True)
            state["proc"] = proc
            fd = proc.stdout.fileno()

            def take(chunk):
                nonlocal nbytes
                h.update(chunk)
                nbytes += len(chunk)
                view = memoryview(chunk)
                while view:
                    n = out.write(view)
                    view = view[n:]

            # Read until EOF — or until the subject has exited and the pipe has been quiet for a
            # second. A process the subject left behind with its stdout inherited holds the write
            # end open, and waiting for EOF would wait for that process (a `sleep 30 &` held the
            # first selftest for thirty seconds). What it writes after the kill below is drained
            # into the record too, because it was written into the record's pipe.
            quiet = 0.0
            while True:
                ready, _, _ = select.select([fd], [], [], 0.5)
                if ready:
                    try:
                        chunk = os.read(fd, CHUNK)
                    except InterruptedError:
                        continue
                    if not chunk:
                        break
                    take(chunk)
                    quiet = 0.0
                elif proc.poll() is not None:
                    quiet += 0.5
                    if quiet >= 1.0:
                        break
            rc = proc.wait()
            pgid = proc.pid
            leftover = group_members(pgid)
            if leftover:
                try:
                    os.killpg(pgid, signal.SIGKILL)
                except OSError:
                    pass
            # The writers are dead now (or there were none); take what is left in the pipe.
            while True:
                ready, _, _ = select.select([fd], [], [], 0.5)
                if not ready:
                    break
                chunk = os.read(fd, CHUNK)
                if not chunk:
                    break
                take(chunk)
    finally:
        for s, handler in old:
            signal.signal(s, handler)
    containers = containers_mounting(roots, docker) if roots else []
    if containers:
        subprocess.run([docker, "stop", "-t", "2"] + [c["id"] for c in containers],
                       capture_output=True, text=True, check=False)
    return {"sha256": h.hexdigest(), "bytes": nbytes, "rc": rc, "pgid": pgid,
            "leftover_pids": leftover, "leftover_containers": containers,
            "interrupted": state["interrupted"]}


def cmd_run(args):
    result = run_recorded(args.cmd, args.out, args.err, args.cwd, args.roots or [], args.docker)
    print(json.dumps(result, sort_keys=True))
    return 0


# ---------------------------------------------------------------- the judged run

class Ctx:
    def __init__(self, root, repo, variant="cli", allow_mcp="", judge=None, docker="docker"):
        self.root = os.path.abspath(root)
        self.repo = os.path.abspath(repo)
        self.stage = os.path.join(self.root, "stage")
        self.seal = os.path.join(self.root, "seal")
        # The same derivation judge.sh and the launchers use.
        self.results = os.path.join(self.repo, "spike", "runs", os.path.basename(self.root))
        self.variant = variant
        self.allow_mcp = allow_mcp
        here = os.path.dirname(os.path.abspath(__file__))
        self.judge = os.path.abspath(judge) if judge else os.path.join(here, "judge.sh")
        self.here = here
        self.docker = docker
        self.inputs_path = os.path.join(self.root, "inputs.json")
        self.transcript = os.path.join(self.results, "transcript.jsonl")

    def res(self, name):
        return os.path.join(self.results, name)

    # The code the judge runs as: verified by this process before every call, never by judge.sh
    # itself — a doctored judge skips its own checks.
    def code_paths(self):
        return [self.judge, os.path.join(self.repo, "spike", "replay_gate.py"),
                os.path.join(self.repo, "spike", "suite_summary.py"),
                os.path.join(self.repo, "spike", "container_seals.py")]

    def has_secondary_controls(self):
        return os.path.isfile(self.res("neg-secondary.json")) and os.path.isfile(self.res("pos-secondary.json"))


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def pre_run_inputs(ctx, prompt):
    """Everything that exists before the agent and that a verdict later rests on."""
    if os.path.exists(ctx.transcript):
        raise Refusal("a transcript already exists at %s; one run per stage" % ctx.transcript)
    manifest = os.path.join(ctx.seal, "manifest.sha256")
    protocol = os.path.join(ctx.seal, "protocol.json")
    for p in (manifest, protocol):
        if not os.path.isfile(p):
            raise Refusal("no seal at %s — run stage.sh first" % p)
    try:
        proto = json.load(open(protocol))
    except ValueError as e:
        raise Refusal("protocol.json is not JSON: %s" % e)
    if not proto.get("image_id"):
        raise Refusal("protocol.json names no image_id — stage again with the current stage.sh, "
                      "which records the image the judge must run (#592)")
    # The two control verdicts, and the streams they were read from (#597): a control's verdict is
    # a pre-run input, so the ground it stood on is one too.
    data = [manifest, protocol, ctx.res("neg-verdict.json"), ctx.res("pos-verdict.json"),
            ctx.res("neg-container.log"), ctx.res("pos-container.log"),
            ctx.res("neg-container.err"), ctx.res("pos-container.err")]
    for opt in ("neg-secondary.json", "pos-secondary.json"):
        if os.path.isfile(ctx.res(opt)):
            data.append(ctx.res(opt))
    if ctx.variant == "mcp":
        data += [ctx.res("mcp-contrast.json"), os.path.join(ctx.root, "mcp.json"),
                 os.path.join(ctx.here, "seal-settings.json")]
    if prompt:
        data.append(prompt)
    files = digest_files(data + ctx.code_paths())
    return {"version": 1, "taken_at": now(), "root": ctx.root, "repo": ctx.repo,
            "variant": ctx.variant, "allow_mcp": ctx.allow_mcp, "image_id": proto["image_id"],
            "prompt": os.path.abspath(prompt) if prompt else None,
            "files": files, "record": None, "repo_tree": None, "git_dir": None,
            "leftovers": None, "steps": {}}


def write_inputs(ctx, inputs):
    tmp = ctx.inputs_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(inputs, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, ctx.inputs_path)


def load_inputs(ctx):
    if not os.path.isfile(ctx.inputs_path):
        raise Refusal("no %s — `judge` writes it after the agent; nothing to resume from" % ctx.inputs_path)
    try:
        return json.load(open(ctx.inputs_path))
    except ValueError as e:
        raise Refusal("%s is not JSON: %s" % (ctx.inputs_path, e))


def verify_files(inputs, paths, what):
    """Every path must be in the record and hash to what was recorded. Both failures are named
    per file; the message says which kind, because they are different findings."""
    files = inputs.get("files") or {}
    unattested, changed, missing = [], [], []
    for p in paths:
        p = os.path.abspath(p)
        want = files.get(p)
        if want is None:
            unattested.append(p)
            continue
        if not os.path.isfile(p):
            missing.append(p)
            continue
        if sha256_file(p) != want:
            changed.append(p)
    problems = []
    if unattested:
        problems.append("not attested (no entry in inputs.json): %s" % ", ".join(unattested))
    if missing:
        problems.append("recorded but gone: %s" % ", ".join(missing))
    if changed:
        problems.append("changed since the launcher recorded it: %s" % ", ".join(changed))
    if problems:
        raise Refusal("before %s — %s" % (what, "; ".join(problems)))


def verify_tree(inputs, ctx, what):
    rec = inputs.get("repo_tree")
    if not rec:
        raise Refusal("before %s — inputs.json holds no snapshot of repo/" % what)
    cur = tree_snapshot(os.path.join(ctx.stage, "repo"))
    if cur["sha256"] != rec["sha256"]:
        diff = tree_diff(rec.get("entries") or {}, cur["entries"])
        raise Refusal("before %s — repo/ changed after the run ended: %s%s"
                      % (what, ", ".join(diff[:20]), " ..." if len(diff) > 20 else ""))
    git = inputs.get("git_dir")
    if git:
        gd = os.path.join(ctx.stage, "repo", ".git")
        cur_git = tree_snapshot(gd, skip_top=())["sha256"] if os.path.isdir(gd) else None
        if cur_git != git.get("sha256"):
            # Recorded, not refused: one `git status` rewrites the index, and nothing the judge
            # builds reads .git/ (pos mode's `git apply` is a control's, before the agent).
            git["changed_before"] = git.get("changed_before") or []
            git["changed_before"].append(what)


def record_output(ctx, inputs, step):
    name = STEP_OUTPUT[step]
    p = ctx.res(name)
    if not os.path.isfile(p):
        raise Refusal("%s wrote no %s" % (step, p))
    inputs["files"][os.path.abspath(p)] = sha256_file(p)
    inputs["steps"][step]["output"] = os.path.abspath(p)
    extras = []
    for name in STEP_EXTRA_REQUIRED.get(step, []):
        q = ctx.res(name)
        if not os.path.isfile(q):
            raise Refusal("%s left no %s, which its verdict was read from" % (step, q))
        inputs["files"][os.path.abspath(q)] = sha256_file(q)
        extras.append(os.path.abspath(q))
    for name in STEP_EXTRA.get(step, []):
        q = ctx.res(name)
        if os.path.isfile(q):
            inputs["files"][os.path.abspath(q)] = sha256_file(q)
            extras.append(os.path.abspath(q))
    if extras:
        inputs["steps"][step]["extra"] = extras
    write_inputs(ctx, inputs)


def run_judge(ctx, inputs, sub_args, what):
    """Verify the judge's bytes, then run THOSE bytes: `sh -s` reads the script from stdin, so
    the file on disk is not consulted again. `$0` is `sh` inside, which judge.sh only uses to
    derive SIDEEYE_REPO (given here in the environment) and to print its usage."""
    # The two modules are verified on disk; judge.sh is verified on the bytes that are about to
    # run, read once — a check on the file and then a second read would leave a gap between them.
    verify_files(inputs, [p for p in ctx.code_paths() if p != ctx.judge], what)
    with open(ctx.judge, "rb") as f:
        judge_bytes = f.read()
    if sha256_bytes(judge_bytes) != inputs["files"].get(ctx.judge):
        raise Refusal("before %s — changed since the launcher recorded it: %s" % (what, ctx.judge))
    env = dict(os.environ)
    env["SIDEEYE_REPO"] = ctx.repo
    sys.stdout.flush()
    proc = subprocess.run(["sh", "-s", "--"] + list(sub_args), input=judge_bytes, env=env,
                          cwd=ctx.repo, check=False)
    return proc.returncode


def step_audit(ctx, inputs):
    rec = inputs.get("record")
    if not rec or not rec.get("sha256"):
        raise Refusal("before audit — inputs.json holds no record digest")
    args = ["audit", "--root", ctx.root, "--transcript", ctx.transcript, "--record-sha", rec["sha256"]]
    if ctx.allow_mcp:
        args += ["--allow-mcp", ctx.allow_mcp]
    return run_judge(ctx, inputs, args, "audit")


def step_eval(ctx, inputs):
    verify_files(inputs, [os.path.join(ctx.seal, "manifest.sha256"), os.path.join(ctx.seal, "protocol.json")], "eval")
    verify_tree(inputs, ctx, "eval")
    return run_judge(ctx, inputs, ["eval", "--root", ctx.root, "--mode", "run"], "eval")


def step_secondary(ctx, inputs):
    verify_files(inputs, [os.path.join(ctx.seal, "manifest.sha256"), os.path.join(ctx.seal, "protocol.json"),
                          ctx.res("neg-secondary.json"), ctx.res("pos-secondary.json")], "secondary")
    verify_tree(inputs, ctx, "secondary")
    return run_judge(ctx, inputs, ["secondary", "--root", ctx.root, "--mode", "run"], "secondary")


def finalize_reads(ctx):
    paths = [os.path.join(ctx.seal, "protocol.json"), ctx.res("neg-verdict.json"), ctx.res("pos-verdict.json"),
             ctx.res("run-verdict.json"), ctx.res("audit.json"), ctx.res("agent-meta.json")]
    if os.path.isfile(ctx.res("run-secondary.json")):
        paths.append(ctx.res("run-secondary.json"))
    if os.path.isfile(ctx.res("run-stage-diffs.jsonl")):
        paths.append(ctx.res("run-stage-diffs.jsonl"))
    if os.path.isfile(os.path.join(ctx.root, "mcp.json")):
        paths.append(ctx.res("mcp-contrast.json"))
    return paths


def step_finalize(ctx, inputs):
    verify_files(inputs, finalize_reads(ctx), "finalize")
    rec = inputs.get("record") or {}
    if rec.get("path") and (not os.path.isfile(rec["path"]) or sha256_file(rec["path"]) != rec.get("sha256")):
        raise Refusal("before finalize — the record at %s is not the record that was made" % rec.get("path"))
    return run_judge(ctx, inputs, ["finalize", "--root", ctx.root], "finalize")


STEP_FN = {"audit": step_audit, "eval": step_eval, "secondary": step_secondary, "finalize": step_finalize}


def post_run(ctx, inputs, start):
    """audit -> eval -> [secondary] -> finalize from `start`, each verified before and hashed
    after. A step's nonzero exit that still leaves its output (a void audit) is a verdict and
    the run continues to a manifest; a step that leaves no output is a refusal."""
    started = STEPS.index(start)
    for step in STEPS[started:]:
        if step == "secondary" and not ctx.has_secondary_controls():
            print("measure: secondary skipped — neg/pos-secondary.json are not both present (evidence, not a gate)")
            inputs["steps"]["secondary"] = {"skipped": True, "at": now()}
            write_inputs(ctx, inputs)
            continue
        print("=== measure: %s ===" % step)
        sys.stdout.flush()
        # Every output an earlier step left is checked before the next step runs, not only
        # when it is read: a tampered audit.json is worth finding before eval spends minutes on
        # a container, and the check is a few small files.
        done = [s["output"] for s in inputs["steps"].values() if isinstance(s, dict) and s.get("output")]
        if done:
            verify_files(inputs, done, step)
        inputs["steps"][step] = {"started": now()}
        write_inputs(ctx, inputs)
        rc = STEP_FN[step](ctx, inputs)
        inputs["steps"][step]["rc"] = rc
        inputs["steps"][step]["finished"] = now()
        record_output(ctx, inputs, step)
    manifest = ctx.res("manifest.json")
    try:
        closed = json.load(open(manifest)).get("loop_closed")
    except (OSError, ValueError):
        closed = None
    print("measure: done — loop_closed=%s (manifest: %s, digests: %s)" % (closed, manifest, ctx.inputs_path))
    return 0


def parse_meta(pairs):
    meta = {}
    for kv in pairs or []:
        if "=" not in kv:
            raise Refusal("--meta wants key=value, got %r" % kv)
        k, v = kv.split("=", 1)
        if v in ("true", "false"):
            v = (v == "true")
        meta[k] = v
    return meta


def agent_meta_from_transcript(path):
    model, model_usage, result = None, None, {}
    with open(path, "rb") as f:
        for line in f:
            try:
                ev = json.loads(line.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                continue
            if not isinstance(ev, dict):
                continue
            if model is None and ev.get("model"):
                model = ev["model"]
            if isinstance(ev.get("modelUsage"), dict):
                model_usage = sorted(ev["modelUsage"])
            if ev.get("type") == "result":
                result = ev
    return model, model_usage, result


def cmd_judge(args):
    ctx = Ctx(args.root, args.repo, args.variant, args.allow_mcp or "", args.judge, args.docker)
    os.makedirs(ctx.results, exist_ok=True)
    inputs = pre_run_inputs(ctx, args.prompt)
    meta = parse_meta(args.meta)
    print("measure: %d inputs recorded before the agent (%s)" % (len(inputs["files"]), ctx.inputs_path))
    sys.stdout.flush()

    print("=== the run: one agent, the sealed stage, the record written through this process ===")
    sys.stdout.flush()
    # Containers are matched against the root and the results, not the repository: a container
    # over the checkout could touch the judge's scripts, which the digests refuse on, and this
    # machine runs other containers over the same checkout that the measurement must not stop.
    rec = run_recorded(args.cmd, ctx.transcript, ctx.res("agent-stderr.log"), ctx.stage,
                       [ctx.root, ctx.results], ctx.docker)
    print("agent exited: %s%s" % (rec["rc"], " (interrupted)" if rec["interrupted"] else ""))
    if rec["leftover_pids"]:
        print("measure: %d process(es) were still in the agent's group and were killed: %s"
              % (len(rec["leftover_pids"]), rec["leftover_pids"]))
    if rec["leftover_containers"]:
        print("measure: %d container(s) still mounted the root or the results and were stopped: %s"
              % (len(rec["leftover_containers"]), [c["id"] for c in rec["leftover_containers"]]))
    elif rec["leftover_containers"] is None:
        print("measure: containers not observed (docker not available)")

    model, model_usage, result = agent_meta_from_transcript(ctx.transcript)
    agent_meta = {
        "variant": ctx.variant, "model": model, "models_billed": model_usage,
        "cli_version": meta.get("cli_version"), "allowed_tools": meta.get("allowed_tools"),
        "disallowed_tools": meta.get("disallowed_tools"),
        "prompt_sha256": inputs["files"].get(inputs["prompt"]) if inputs["prompt"] else None,
        "agent_rc": rec["rc"], "safe_mode": meta.get("safe_mode"),
        "num_turns": result.get("num_turns"), "duration_ms": result.get("duration_ms"),
        "total_cost_usd": result.get("total_cost_usd"),
        # #515's other half, recorded where finalize reads it: how the record was taken, and
        # what the run left behind. `leftover_containers` is null when docker was not there to ask.
        "record_sha256": rec["sha256"], "record_bytes": rec["bytes"],
        "leftover_pids": rec["leftover_pids"], "leftover_containers": rec["leftover_containers"],
        "interrupted": rec["interrupted"], "recorded_by": "measure.py",
    }
    if "seal" in meta:
        agent_meta["seal"] = meta["seal"]
    with open(ctx.res("agent-meta.json"), "w") as f:
        json.dump(agent_meta, f, indent=1)
    print("agent-meta: model=%s cli=%s" % (model, meta.get("cli_version")))

    inputs["record"] = {"path": ctx.transcript, "sha256": rec["sha256"], "bytes": rec["bytes"]}
    inputs["files"][ctx.res("agent-meta.json")] = sha256_file(ctx.res("agent-meta.json"))
    inputs["leftovers"] = {"pids": rec["leftover_pids"], "containers": rec["leftover_containers"]}
    t0 = time.time()
    inputs["repo_tree"] = tree_snapshot(os.path.join(ctx.stage, "repo"))
    gd = os.path.join(ctx.stage, "repo", ".git")
    inputs["git_dir"] = {"sha256": tree_snapshot(gd, skip_top=())["sha256"]} if os.path.isdir(gd) else None
    print("measure: repo/ snapshot — %d entries in %.1fs (.git/ recorded separately)"
          % (len(inputs["repo_tree"]["entries"]), time.time() - t0))
    write_inputs(ctx, inputs)
    if rec["interrupted"]:
        # The record and the digests are kept; the judging is not started on a run the operator
        # stopped — eval alone would spend minutes in a container on it. `resume` judges it if
        # that is wanted (found in review).
        raise Refusal("the run was interrupted; recorded and not judged — `measure.py resume` judges it if you want that")
    if not model:
        # The old launcher stopped here too: the manifest needs a model id and there is none to
        # invent. The run is recorded and stays unfinalized; there is no path that supplies one.
        raise Refusal("no model id found in the transcript — the run is recorded and cannot be finalized")
    return post_run(ctx, inputs, "audit")


def cmd_resume(args):
    ctx = Ctx(args.root, args.repo, "cli", args.allow_mcp or "", args.judge, args.docker)
    inputs = load_inputs(ctx)
    # The run's own settings come from the record, not from the resume's command line: an
    # audit redone without `--allow-mcp` would void the mcp variant's every server call.
    ctx.variant = inputs.get("variant", "cli")
    ctx.allow_mcp = inputs.get("allow_mcp") or ctx.allow_mcp
    if inputs.get("root") != ctx.root or inputs.get("repo") != ctx.repo:
        raise Refusal("inputs.json was written for root=%s repo=%s, not for this call"
                      % (inputs.get("root"), inputs.get("repo")))
    start = args.start
    if not start:
        for step in STEPS:
            s = inputs.get("steps", {}).get(step) or {}
            if "output" not in s and not s.get("skipped"):
                start = step
                break
        else:
            print("measure: every step has an output on record; nothing to resume (pass --from to redo one)")
            return 0
    print("measure: resuming from %s with the digests taken %s" % (start, inputs.get("taken_at")))
    # Redone steps are the launcher's own outputs again: their old entries go, the new ones land
    # as they are written. Nothing recorded before the agent's death is touched.
    for step in STEPS[STEPS.index(start):]:
        s = inputs.get("steps", {}).pop(step, None) or {}
        for p in [s.get("output")] + list(s.get("extra") or []):
            if p:
                inputs["files"].pop(p, None)
    write_inputs(ctx, inputs)
    return post_run(ctx, inputs, start)


# ---------------------------------------------------------------- selftest

STUB_JUDGE = r'''#!/bin/sh
# A stand-in for judge.sh in measure.py's selftest: records that it was called, writes the
# output the real subcommand would leave. Read from stdin by `sh -s`, like the real one.
set -eu
sub=$1; shift
root=""
while [ $# -gt 0 ]; do
    case "$1" in --root) root=$2; shift 2 ;; *) shift ;; esac
done
RESULTS="$SIDEEYE_REPO/spike/runs/$(basename "$root")"
echo "$sub" >> "$RESULTS/judge-calls"
case "$sub" in
    audit) printf '{"verdict": "clean", "record_sha": "verified"}\n' > "$RESULTS/audit.json" ;;
    eval) printf '{"replay": {"gate": "pass"}, "func": {"gate": "pass"}}\n' > "$RESULTS/run-verdict.json"
          printf '{"restored": [], "removed": []}\n' >> "$RESULTS/run-stage-diffs.jsonl"
          # The container's stream and the host's capture of docker's own stderr: the real eval
          # always leaves both, and record_output requires them (#597).
          printf 'judge: replay-rc=0;\n' > "$RESULTS/run-container.log"
          : > "$RESULTS/run-container.err" ;;
    secondary) printf '{"full_explore": {"gate": "pass"}}\n' > "$RESULTS/run-secondary.json" ;;
    finalize) printf '{"loop_closed": true}\n' > "$RESULTS/manifest.json"; echo "loop_closed: True" ;;
esac
'''

STUB_AGENT = r'''
import json, sys
print(json.dumps({"type": "system", "subtype": "init", "model": "stub-model", "tools": ["Bash"]}))
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": "ls"}}]}}))
print(json.dumps({"type": "result", "num_turns": 1, "duration_ms": 5, "total_cost_usd": 0.0, "modelUsage": {"stub-model": {}}}))
'''

STUB_DOCKER = r'''#!/usr/bin/env python3
# A stand-in docker for the selftest: one container mounting the stage, one mounting /elsewhere.
import json, sys
a = sys.argv[1:]
if a[:2] == ["ps", "-q"]:
    print("aaaaaaaaaaaa"); print("bbbbbbbbbbbb"); print("cccccccccccc"); sys.exit(0)
if a[:1] == ["inspect"]:
    stage = open(__file__ + ".stage").read().strip()
    # c: a tmpfs mount, whose Source docker reports as "" — it must match no root.
    print(json.dumps([
        {"Id": "a" * 64, "Config": {"Image": "x"}, "Mounts": [{"Source": stage}]},
        {"Id": "b" * 64, "Config": {"Image": "y"}, "Mounts": [{"Source": "/elsewhere/notours"}]},
        {"Id": "c" * 64, "Config": {"Image": "z"}, "Mounts": [{"Type": "tmpfs", "Source": ""}]},
    ])); sys.exit(0)
if a[:1] == ["stop"]:
    open(__file__ + ".stopped", "a").write(" ".join(a[1:]) + "\n"); sys.exit(0)
sys.exit(2)
'''


def _write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if mode is not None:
        os.chmod(path, mode)


def selftest():
    work = tempfile.mkdtemp(prefix="measure-selftest-")
    passes, fails, skipped = 0, 0, []
    py = sys.executable

    def ok(name, what):
        nonlocal passes
        passes += 1
        print("ok   measure.py: %s — %s" % (name, what))

    def fail(name, what):
        nonlocal fails
        fails += 1
        print("FAIL measure.py: %s — %s" % (name, what))

    def check(name, cond, what_ok, what_fail):
        if cond:
            ok(name, what_ok)
        else:
            fail(name, what_fail)

    stub_agent = os.path.join(work, "stub-agent.py")
    _write(stub_agent, STUB_AGENT)

    # --- record-stream: the digest is over the bytes as they flowed, not over the file after.
    # The subject writes three lines, tries to truncate its stdout, then appends a fourth line to
    # the record BY NAME. Under `run` the file has four lines and the printed digest is the
    # digest of three — which a recorder that hashes the file afterwards cannot produce.
    stub = os.path.join(work, "stub-truncate.py")
    _write(stub, "import os, sys\n"
                 "sys.stdout.write('one\\ntwo\\nthree\\n'); sys.stdout.flush()\n"
                 "try:\n    os.ftruncate(1, 0); print('truncated', file=sys.stderr)\n"
                 "except OSError as e:\n    print('ftruncate refused: %s' % e, file=sys.stderr)\n"
                 "open(sys.argv[1], 'a').write('four-by-name\\n')\n")
    out = os.path.join(work, "rec.jsonl")
    r = run_recorded([py, stub, out], out, os.path.join(work, "rec.err"), work, [], "docker-absent")
    body = open(out, "rb").read()
    three = sha256_bytes(b"one\ntwo\nthree\n")
    check("record-stream",
          r["sha256"] == three and body.count(b"\n") == 4 and sha256_file(out) != three and r["rc"] == 0,
          "the printed digest is the stream's (three lines), the file holds four, and the two differ",
          "sha %s file-lines %d file-sha-equals-stream %s rc %s" % (r["sha256"][:8], body.count(b"\n"), sha256_file(out) == three, r["rc"]))
    # The contrast: the same subject under the shape the launchers used until this change.
    out2 = os.path.join(work, "rec-oldshape.jsonl")
    with open(out2, "wb") as f:
        subprocess.run([py, stub, out2], stdout=f, stderr=subprocess.DEVNULL, check=False)
    body2 = open(out2, "rb").read()
    check("record-oldshape-contrast", body2 == b"four-by-name\n",
          "under `> file` the truncate went through and only the by-name line is left (the 2026-09-09 red, again)",
          "old shape left %r" % body2[:60])

    # --- rc propagates
    stub7 = os.path.join(work, "stub-rc7.py")
    _write(stub7, "import sys; print('x'); sys.exit(7)\n")
    r = run_recorded([py, stub7], os.path.join(work, "rc7.out"), os.path.join(work, "rc7.err"), work, [], "docker-absent")
    check("rc-propagates", r["rc"] == 7, "the subject's exit code 7 comes back as rc 7", "rc %r" % r["rc"])

    # --- leftover process in the group: recorded, and dead afterwards
    # The sleep inherits the record's pipe, the shape a `nohup x &` from the agent has: waiting
    # for EOF would wait thirty seconds, so the return time is part of the assertion.
    stubbg = os.path.join(work, "stub-bg.sh")
    _write(stubbg, "#!/bin/sh\nsleep 30 &\necho started\n")
    t0 = time.time()
    r = run_recorded(["sh", stubbg], os.path.join(work, "bg.out"), os.path.join(work, "bg.err"), work, [], "docker-absent")
    took = time.time() - t0
    if r["leftover_pids"] is None:
        skipped.append("leftover-pid (no way to list processes here)")
        print("skip measure.py: leftover-pid — process listing unavailable on this platform")
    else:
        alive = []
        deadline = time.time() + 2
        while time.time() < deadline:
            alive = []
            for pid in r["leftover_pids"]:
                try:
                    os.kill(pid, 0)
                    # A zombie answers kill -0; ask the platform whether it is really gone.
                    alive.append(pid)
                except ProcessLookupError:
                    pass
            if not alive:
                break
            time.sleep(0.1)
        still = group_members(r["pgid"]) or []
        check("leftover-pid", bool(r["leftover_pids"]) and not still and took < 10,
              "the background sleep was listed (%s), killed, and the recorder returned in %.1fs rather than waiting for it" % (r["leftover_pids"], took),
              "listed %r, still in group %r, took %.1fs" % (r["leftover_pids"], still, took))

    # --- leftover container, through a stand-in docker: the match is on the mount's SOURCE
    stub_docker = os.path.join(work, "bin", "docker")
    _write(stub_docker, STUB_DOCKER, 0o755)
    _write(stub_docker + ".stage", os.path.join(work, "root-x", "stage") + "\n")
    hits = containers_mounting([os.path.join(work, "root-x")], stub_docker)
    check("leftover-container-stub",
          hits is not None and [h["id"] for h in hits] == ["a" * 12] and hits[0]["mounts"] == [os.path.join(work, "root-x", "stage")],
          "the container mounting the stage is listed by its mount source; the one elsewhere and the tmpfs one (empty Source) are not",
          "hits %r" % hits)
    check("leftover-container-absent", containers_mounting([work], os.path.join(work, "no-such-docker")) is None,
          "with no docker to ask the answer is null, not an empty list", "got %r" % containers_mounting([work], os.path.join(work, "no-such-docker")))

    # --- leftover container, live, when docker and a small image are at hand
    live_image = None
    if shutil.which("docker"):
        for img in ("busybox", "alpine", "debian", "ubuntu", "python:3"):
            if subprocess.run(["docker", "image", "inspect", img], capture_output=True, check=False).returncode == 0:
                live_image = img
                break
    if live_image:
        mnt = os.path.join(work, "live-root", "stage")
        os.makedirs(mnt, exist_ok=True)
        cid = subprocess.run(["docker", "run", "-d", "--rm", "-v", "%s:%s" % (mnt, mnt), live_image, "sleep", "30"],
                             capture_output=True, text=True, check=False).stdout.strip()
        hits = containers_mounting([os.path.join(work, "live-root")], "docker") or []
        found = any(cid.startswith(h["id"]) for h in hits)
        subprocess.run(["docker", "stop", "-t", "1", cid], capture_output=True, check=False)
        check("leftover-container-live", found,
              "a real container mounting the stage is listed by `docker inspect`'s mount source (%s)" % live_image,
              "container %s not among %r" % (cid[:12], hits))
    else:
        skipped.append("leftover-container-live (docker or a local image not available)")
        print("skip measure.py: leftover-container-live — docker or a small local image is not available")

    # --- a judged root, end to end with stubs, then each channel on a fresh copy of it
    def make_root(tag):
        root = os.path.join(work, "root-" + tag)
        repo = os.path.join(work, "repo-" + tag)
        stage, seal = os.path.join(root, "stage"), os.path.join(root, "seal")
        results = os.path.join(repo, "spike", "runs", "root-" + tag)
        os.makedirs(os.path.join(stage, "repo", ".git"), exist_ok=True)
        os.makedirs(seal, exist_ok=True)
        os.makedirs(results, exist_ok=True)
        _write(os.path.join(stage, "repo", "src.c"), "int main(void) { return 0; }\n")
        _write(os.path.join(stage, "repo", ".git", "index"), "index-v1\n")
        _write(os.path.join(stage, "define", "check.sh"), "exit 0\n")
        _write(os.path.join(seal, "manifest.sha256"), "%s  ./define/check.sh\n" % sha256_file(os.path.join(stage, "define", "check.sh")))
        _write(os.path.join(seal, "protocol.json"), json.dumps({"pin": "0" * 40, "image": "x", "image_id": "sha256:" + "0" * 64}))
        _write(os.path.join(results, "neg-verdict.json"), '{"expectation_met": true}\n')
        _write(os.path.join(results, "pos-verdict.json"), '{"expectation_met": true}\n')
        _write(os.path.join(results, "neg-container.log"), "judge: replay-rc=1;\n")
        _write(os.path.join(results, "pos-container.log"), "judge: replay-rc=0;\n")
        # The host's own capture of docker's stderr: written on every eval, empty when docker had
        # nothing to say, and required rather than optional -- it is the only place a failure to
        # start the container leaves its reason (found in review).
        _write(os.path.join(results, "neg-container.err"), "")
        _write(os.path.join(results, "pos-container.err"), "")
        _write(os.path.join(repo, "spike", "replay_gate.py"), "# gate\n")
        _write(os.path.join(repo, "spike", "suite_summary.py"), "# summary\n")
        _write(os.path.join(repo, "spike", "container_seals.py"), "# seals\n")
        judge = os.path.join(repo, "spike", "loop-closure-timew", "judge.sh")
        _write(judge, STUB_JUDGE, 0o755)
        prompt = os.path.join(repo, "prompt.md")
        _write(prompt, "fix it\n")
        return root, repo, judge, prompt, results

    def judged_root(tag):
        root, repo, judge, prompt, results = make_root(tag)
        ns = argparse.Namespace(root=root, repo=repo, variant="cli", allow_mcp="", judge=judge, prompt=prompt,
                                meta=["cli_version=stub", "safe_mode=true"], cmd=[py, stub_agent], docker="docker-absent")
        rc = cmd_judge(ns)
        return root, repo, judge, results, rc

    def calls(results):
        p = os.path.join(results, "judge-calls")
        return open(p).read().split() if os.path.exists(p) else []

    def resume_refuses(tag, start, mutate, want_in_message):
        root, repo, judge, results, rc = judged_root(tag)
        before = calls(results)
        mutate(root, repo, judge, results)
        ctx = Ctx(root, repo, judge=judge)
        stage_before = tree_snapshot(os.path.join(root, "stage"), skip_top=())["sha256"]
        ns = argparse.Namespace(root=root, repo=repo, allow_mcp="", judge=judge, start=start, docker="docker-absent")
        try:
            cmd_resume(ns)
            return False, "resume ran to the end", before, calls(results), stage_before, tree_snapshot(os.path.join(root, "stage"), skip_top=())["sha256"]
        except Refusal as e:
            return want_in_message in str(e), str(e), before, calls(results), stage_before, tree_snapshot(os.path.join(root, "stage"), skip_top=())["sha256"]

    # happy path
    root, repo, judge, results, rc = judged_root("happy")
    inputs = json.load(open(os.path.join(root, "inputs.json")))
    meta = json.load(open(os.path.join(results, "agent-meta.json")))
    want_calls = ["audit", "eval", "finalize"]  # no secondary controls on this root
    check("judge-happy",
          rc == 0 and calls(results) == want_calls
          and all(os.path.join(results, STEP_OUTPUT[s]) in inputs["files"] for s in want_calls)
          and os.path.join(results, "run-stage-diffs.jsonl") in inputs["files"]
          and inputs["record"]["sha256"] == sha256_file(os.path.join(results, "transcript.jsonl"))
          and meta.get("leftover_pids") == [] and meta.get("record_sha256") == inputs["record"]["sha256"]
          and inputs["steps"].get("secondary", {}).get("skipped") is True,
          "audit, eval and finalize ran in order, each output and the rebuild history are in inputs.json, the record digest is the file's, agent-meta carries the leftovers",
          "rc %s calls %r" % (rc, calls(results)))

    # one run per stage
    try:
        cmd_judge(argparse.Namespace(root=root, repo=repo, variant="cli", allow_mcp="", judge=judge,
                                     prompt=os.path.join(repo, "prompt.md"), meta=[], cmd=[py, stub_agent], docker="docker-absent"))
        fail("one-run-per-stage", "a second judge on the same root ran")
    except Refusal as e:
        check("one-run-per-stage", "already exists" in str(e), "a second agent on a stage with a transcript is refused before anything runs", str(e))

    # pre-run data changed: the seal's manifest (the #592 shape), eval never called, stage untouched
    def doctor_manifest(root, repo, judge, results):
        p = os.path.join(root, "seal", "manifest.sha256")
        open(p, "a").write("%s  ./define/evil.sh\n" % ("f" * 64))
    got, msg, before, after, sb, sa = resume_refuses("manifest", "eval", doctor_manifest, "manifest.sha256")
    check("pre-run-changed", got and after == before and sb == sa,
          "a doctored seal manifest is named, eval was not called again, and the stage is byte-identical",
          "named %s / calls before %r after %r / stage same %s / %s" % (got, before, after, sb == sa, msg))

    # code changed: the judge's bytes
    def doctor_judge(root, repo, judge, results):
        open(judge, "a").write("# doctored\n")
    got, msg, before, after, _, _ = resume_refuses("judge", "eval", doctor_judge, "judge.sh")
    check("code-changed", got and after == before,
          "a changed judge.sh is named before it is run, and it is not run", "named %s calls %r->%r / %s" % (got, before, after, msg))

    # repo/ working tree changed after the run
    def doctor_repo(root, repo, judge, results):
        open(os.path.join(root, "stage", "repo", "src.c"), "a").write("// later\n")
    got, msg, before, after, _, _ = resume_refuses("repo", "eval", doctor_repo, "src.c")
    check("repo-changed", got and after == before,
          "a file of repo/ that changed after the run ended is named, and eval is not called", "named %s calls %r->%r / %s" % (got, before, after, msg))

    # .git/ changed: recorded, not refused
    root, repo, judge, results, rc = judged_root("gitdir")
    open(os.path.join(root, "stage", "repo", ".git", "index"), "w").write("index-v2\n")
    before = calls(results)
    ns = argparse.Namespace(root=root, repo=repo, allow_mcp="", judge=judge, start="eval", docker="docker-absent")
    try:
        cmd_resume(ns)
        inputs = json.load(open(os.path.join(root, "inputs.json")))
        check("gitdir-recorded", calls(results) == before + ["eval", "finalize"] and inputs["git_dir"].get("changed_before"),
              "a rewritten .git/index does not stop the judge, and inputs.json records that it changed",
              "calls %r git_dir %r" % (calls(results), inputs.get("git_dir")))
    except Refusal as e:
        fail("gitdir-recorded", "refused on a .git/ change: %s" % e)

    # a judge output changed between steps
    def doctor_audit(root, repo, judge, results):
        open(os.path.join(results, "audit.json"), "w").write('{"verdict": "clean", "record_sha": "verified", "doctored": 1}\n')
    got, msg, before, after, _, _ = resume_refuses("audit-out", "eval", doctor_audit, "audit.json")
    check("output-changed", got and after == before,
          "an audit.json rewritten after the audit is named before eval, and eval is not called", "named %s / %s" % (got, msg))

    # an entry missing from inputs.json: not attested
    def drop_entry(root, repo, judge, results):
        p = os.path.join(root, "inputs.json")
        d = json.load(open(p))
        d["files"].pop(os.path.join(results, "pos-verdict.json"))
        json.dump(d, open(p, "w"))
    got, msg, before, after, _, _ = resume_refuses("entry", "finalize", drop_entry, "not attested")
    check("entry-missing", got and "pos-verdict.json" in msg and after == before,
          "a file finalize reads with no entry in inputs.json is refused as not attested, by name", "named %s / %s" % (got, msg))

    # the record itself changed after the run
    def doctor_record(root, repo, judge, results):
        open(os.path.join(results, "transcript.jsonl"), "a").write("{}\n")
    got, msg, before, after, _, _ = resume_refuses("record", "finalize", doctor_record, "not the record that was made")
    check("record-changed", got and after == before,
          "a transcript that grew after the run is refused before finalize", "named %s / %s" % (got, msg))

    # resume redoes a step and re-records its output
    root, repo, judge, results, rc = judged_root("redo")
    old_inputs = json.load(open(os.path.join(root, "inputs.json")))
    ns = argparse.Namespace(root=root, repo=repo, allow_mcp="", judge=judge, start="eval", docker="docker-absent")
    try:
        cmd_resume(ns)
        new_inputs = json.load(open(os.path.join(root, "inputs.json")))
        check("resume-redo",
              calls(results) == ["audit", "eval", "finalize", "eval", "finalize"]
              and new_inputs["steps"]["eval"]["started"] >= old_inputs["steps"]["eval"]["started"]
              and new_inputs["files"][os.path.join(results, "run-verdict.json")] == sha256_file(os.path.join(results, "run-verdict.json"))
              and new_inputs["record"] == old_inputs["record"] and new_inputs["repo_tree"]["sha256"] == old_inputs["repo_tree"]["sha256"],
              "eval and finalize ran again from the recorded digests, the redone output is re-recorded, the record and the snapshot are untouched",
              "calls %r" % calls(results))
    except Refusal as e:
        fail("resume-redo", str(e))

    # interrupted: the operator's Ctrl-C is forwarded to the agent's group, the run is recorded
    # and not judged, and `resume` with no --from begins at the first step without an output.
    import threading
    root, repo, judge, prompt, results = make_root("interrupt")
    stub_sleep = os.path.join(work, "stub-sleep.py")
    _write(stub_sleep, "import json, sys, time\n"
                       "print(json.dumps({'type': 'system', 'subtype': 'init', 'model': 'stub-model'})); sys.stdout.flush()\n"
                       "time.sleep(20)\n")
    threading.Timer(0.7, os.kill, [os.getpid(), signal.SIGINT]).start()
    t0 = time.time()
    try:
        cmd_judge(argparse.Namespace(root=root, repo=repo, variant="cli", allow_mcp="", judge=judge, prompt=prompt,
                                     meta=[], cmd=[py, stub_sleep], docker="docker-absent"))
        fail("interrupted-not-judged", "judge ran to the end after SIGINT")
    except Refusal as e:
        took = time.time() - t0
        try:
            inputs = json.load(open(os.path.join(root, "inputs.json")))
            meta = json.load(open(os.path.join(results, "agent-meta.json")))
        except (OSError, ValueError):
            inputs, meta = {}, {}
        check("interrupted-not-judged",
              "interrupted" in str(e) and took < 10 and meta.get("interrupted") is True
              and bool(inputs.get("record")) and calls(results) == [],
              "SIGINT ended the agent's group in %.1fs; the run is recorded (inputs.json, agent-meta.interrupted) and no judge step ran" % took,
              "%s / took %.1f / calls %r / interrupted %r" % (e, took, calls(results), meta.get("interrupted")))
    try:
        cmd_resume(argparse.Namespace(root=root, repo=repo, allow_mcp="", judge=judge, start=None, docker="docker-absent"))
        check("resume-auto-start", calls(results) == ["audit", "eval", "finalize"],
              "resume with no --from began at audit, the first step with no output on record, and reached finalize",
              "calls %r" % calls(results))
    except Refusal as e:
        fail("resume-auto-start", str(e))

    shutil.rmtree(work, ignore_errors=True)
    total = passes + fails
    # The count is the assertion, as in judge.sh's selftest: a deleted case must not leave the
    # closing line green with the same wording. One more when the live container case ran.
    want = 18 + (1 if live_image else 0)
    if fails:
        print("measure.py selftest: %d of %d case(s) FAILED" % (fails, total))
        return 1
    if passes != want:
        print("measure.py selftest: ran %d case(s), expected %d — the case list changed" % (passes, want))
        return 1
    print("measure.py selftest: %d cases hold%s" % (passes, ("; skipped: " + "; ".join(skipped)) if skipped else ""))
    return 0


# ---------------------------------------------------------------- main

def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(prog="measure.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("run")
    p.add_argument("--out", required=True)
    p.add_argument("--err", required=True)
    p.add_argument("--cwd", required=True)
    p.add_argument("--roots", nargs="*", default=[])
    p.add_argument("--docker", default="docker")
    p.add_argument("cmd", nargs=argparse.REMAINDER)

    p = sub.add_parser("judge")
    p.add_argument("--root", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--variant", choices=("cli", "mcp"), default="cli")
    p.add_argument("--prompt", required=True)
    p.add_argument("--allow-mcp", default="")
    p.add_argument("--meta", action="append", default=[])
    p.add_argument("--judge", default=None)
    p.add_argument("--docker", default="docker")
    p.add_argument("cmd", nargs=argparse.REMAINDER)

    p = sub.add_parser("resume")
    p.add_argument("--root", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--from", dest="start", choices=STEPS, default=None)
    p.add_argument("--allow-mcp", default="")
    p.add_argument("--judge", default=None)
    p.add_argument("--docker", default="docker")

    args = ap.parse_args(argv)
    which = argv[0]
    if which in ("run", "judge"):
        # REMAINDER keeps the `--` that separates our options from the subject's command.
        if args.cmd[:1] == ["--"]:
            args.cmd = args.cmd[1:]
        if not args.cmd:
            ap.error("%s needs a command after --" % which)
    try:
        if which == "run":
            return cmd_run(args)
        if which == "judge":
            return cmd_judge(args)
        return cmd_resume(args)
    except Refusal as e:
        # 3, apart from a subject's or a judge step's exit: "the launcher would not proceed".
        print("measure: refused — %s" % e, file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
