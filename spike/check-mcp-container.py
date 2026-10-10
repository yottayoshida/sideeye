#!/usr/bin/env python3
"""Run docs/mcp.md's container section as written (#721, ADR 0114).

Usage: check-mcp-container.py <repo-root> <workdir>
       check-mcp-container.py --selftest

The page tells an operator to copy docs/mcp-container/Dockerfile, add their tool at its end,
and run one block. This does exactly that, with spike/toys/toy.c as the tool, and holds four
things to it:

  pins        the Dockerfile's SIDEEYE_VERSION equals the quickstart's pinned version
              (.github/workflows/quickstart-release.yml), and its two digests are the ones the
              release publishes for the two Linux assets. A version moved without its digests
              is caught here before ADD --checksum is.
  verdicts    the page's first call (the jsonrpc fence of the MCP section) reaches a FAIL on a
              target with a planted bug and a PASS with oracle_verified on a correct one —
              through the page's own `docker run`, flags and all.
  confinement the same flags, checked from inside: no capability in the effective or bounding
              set (--cap-drop=ALL), NoNewPrivs (no-new-privileges), no route (--network=none),
              a root file system that refuses a write (--read-only). A verdict does not move
              when a flag is dropped, so without this the flags would be text nobody runs.
  version     the binary in the image is the version the Dockerfile names.

The container runs as root, as the page's block starts it. Its root file system is root's, so
a write there succeeds unless --read-only refuses it — which is what makes that probe answer
for the flag rather than for file permissions.

--selftest needs no Docker and no network: it proves each predicate above can go red, on the
real page, Dockerfile and workflow and on copies with one thing changed.
"""
import json
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

REPO = "yottayoshida/sideeye"
CONTAINER_HEADING = "## Running it in a container"
MCP_HEADING = "## Driving it from an agent (MCP)"
TOOL_MARKER = "# ---- Your tool goes after this line"
PLACEHOLDER_CONFIG = "/path/to/your/workspace/sideeye.toml"
STAGE_ASSET = {"amd64": "x86_64-linux", "arm64": "aarch64-linux"}
ZERO_CAPS = "0000000000000000"

# What the check adds at the Dockerfile's end, as an operator adds their tool: built on the
# image's own base, which is the point the Dockerfile's comment makes about glibc.
TOOL_LINES = """\
RUN apt-get update \\
 && apt-get install -y --no-install-recommends gcc libc6-dev \\
 && rm -rf /var/lib/apt/lists/*
COPY toy.c /tmp/toy.c
RUN cc -O0 -o /usr/local/bin/sideeye-toy-clean /tmp/toy.c -lpthread \\
 && cc -O0 -DBUGGY=1 -o /usr/local/bin/sideeye-toy-bug /tmp/toy.c -lpthread \\
 && rm /tmp/toy.c
"""

# The README's shape: the state beside the config, so inside the mount. That is what makes the
# server write to /work — which a root with no capability cannot do in a directory the host's
# user owns, the reason the page's block runs the server as that user.
DEFINE = """\
[world]
state = "./state"

[define]
cwd       = "."
setup     = "/usr/local/bin/sideeye-toy-{kind} init"
operation = "/usr/local/bin/sideeye-toy-{kind} rotate"
"""

# /var/tmp is world-writable on the base, so a write there is refused only by --read-only: a
# probe of / would be refused by its permissions alone once the server is not root.
PROBE = """\
echo "uid: $(id -u)"
grep -E '^(CapEff|CapBnd|NoNewPrivs):' /proc/self/status
echo "routes: $(tail -n +2 /proc/net/route | wc -l)"
if msg=$( (: > /var/tmp/sideeye-probe) 2>&1 ); then echo "rootfs: writable"; else echo "rootfs: $msg"; fi
"""


class Fail(Exception):
    pass


def section(text, heading):
    lines = text.split("\n")
    starts = [i for i, l in enumerate(lines) if l.strip() == heading]
    if len(starts) != 1:
        raise Fail("wanted exactly one %r heading, found %d" % (heading, len(starts)))
    s = starts[0]
    e = next((j for j in range(s + 1, len(lines)) if lines[j].startswith("## ")), len(lines))
    return "\n".join(lines[s:e])


def fence(sec, info, heading):
    blocks = re.findall(r"^```%s\n(.*?)^```$" % re.escape(info), sec, re.M | re.S)
    if len(blocks) != 1:
        raise Fail("wanted exactly one ```%s fence under %r, found %d" % (info, heading, len(blocks)))
    return blocks[0]


def page_parts(page):
    block = fence(section(page, CONTAINER_HEADING), "sh", CONTAINER_HEADING)
    rpc = fence(section(page, MCP_HEADING), "jsonrpc", MCP_HEADING)
    reqs = [l for l in rpc.split("\n") if l.strip()]
    if len(reqs) != 2:
        raise Fail("wanted 2 request lines in the MCP section's exchange, got %d" % len(reqs))
    if PLACEHOLDER_CONFIG not in reqs[1]:
        raise Fail("the exchange's tools/call no longer names %s; this check cannot point it at its defines" % PLACEHOLDER_CONFIG)
    builds = re.findall(r"^\s*docker build\b(.*)$", block, re.M)
    if len(builds) != 1:
        raise Fail("wanted exactly one `docker build` in the container block, found %d" % len(builds))
    args = shlex.split(builds[0])
    if args and args[-1] == "&&":
        args = args[:-1]
    if "-t" not in args or args.index("-t") + 1 >= len(args):
        raise Fail("the container block's `docker build` names no image with -t")
    image, context = args[args.index("-t") + 1], args[-1]
    mounts = re.findall(r'-v\s+"\$PWD/([^":]+):/work"', block)
    if len(mounts) != 1:
        raise Fail("wanted exactly one `-v \"$PWD/<dir>:/work\"` in the container block, found %d" % len(mounts))
    if not re.fullmatch(r"[A-Za-z0-9._-]+", context) or context in (".", "..", mounts[0]):
        raise Fail("the container block builds from %r; this check wants a directory of its own beside the mount" % context)
    return block, reqs, image, context


def probe_block(block):
    """The block with its server command swapped for a shell that reads the probe on stdin."""
    lines = block.rstrip("\n").split("\n")
    last = next((i for i in range(len(lines) - 1, -1, -1)
                 if lines[i].strip() and not lines[i].lstrip().startswith("#")), None)
    if last is None or not re.search(r"\ssideeye mcp\s*$", lines[last]):
        raise Fail("the container block's last command does not end with `sideeye mcp`")
    lines[last] = re.sub(r"\ssideeye mcp\s*$", " sh -s", lines[last])
    return "\n".join(lines) + "\n"


def dockerfile_pins(text):
    versions = re.findall(r"^ARG SIDEEYE_VERSION=(\S+)\s*$", text, re.M)
    if len(versions) != 1:
        raise Fail("wanted exactly one `ARG SIDEEYE_VERSION=` default in the Dockerfile, found %d" % len(versions))
    version = versions[0]
    digests, stage = {}, None
    # Continuation lines are joined first so a digest and the URL it checks are read together.
    for line in re.sub(r"\\\n", " ", text).split("\n"):
        m = re.match(r"^FROM\s+\S+\s+AS\s+fetch-(\S+)\s*$", line)
        if m:
            stage = m.group(1)
            continue
        if line.startswith("FROM "):
            stage = None
        m = re.match(r"^ADD\s+--checksum=sha256:([0-9a-f]{64})\s+(\S+)", line)
        if m:
            if stage not in STAGE_ASSET:
                raise Fail("an ADD --checksum outside a fetch-amd64 / fetch-arm64 stage: %r" % line[:80])
            want = "sideeye-${SIDEEYE_VERSION}-%s.tar.gz" % STAGE_ASSET[stage]
            if not m.group(2).endswith("/" + want):
                raise Fail("stage fetch-%s fetches %s, not %s" % (stage, m.group(2), want))
            if STAGE_ASSET[stage] in digests:
                raise Fail("two ADD --checksum lines in stage fetch-%s" % stage)
            digests[STAGE_ASSET[stage]] = m.group(1)
    if sorted(digests) != sorted(STAGE_ASSET.values()):
        raise Fail("wanted one pinned digest per Linux asset, found %s" % sorted(digests))
    if text.count(TOOL_MARKER) != 1:
        raise Fail("wanted the line %r exactly once in the Dockerfile" % TOOL_MARKER)
    return version, digests


def quickstart_version(text):
    found = re.findall(r"^\s*SIDEEYE_VERSION:\s*(\S+)\s*$", text, re.M)
    if len(found) != 1:
        raise Fail("wanted exactly one SIDEEYE_VERSION in quickstart-release.yml, found %d" % len(found))
    return found[0]


def check_pins_agree(version, quick):
    if version != quick:
        raise Fail("the Dockerfile pins %s and quickstart-release.yml pins %s; move them together" % (version, quick))


def check_release_digests(version, digests, release):
    published = {a.get("name"): (a.get("digest") or "") for a in release.get("assets") or []}
    for asset, digest in sorted(digests.items()):
        name = "sideeye-%s-%s.tar.gz" % (version, asset)
        if name not in published:
            raise Fail("release %s has no asset %s" % (version, name))
        if published[name] != "sha256:" + digest:
            raise Fail("the Dockerfile pins %s for %s; the release publishes %s" % (digest, name, published[name] or "no digest"))


def check_probe(out):
    fields = dict(re.findall(r"^(uid|CapEff|CapBnd|NoNewPrivs|routes|rootfs):\s*(.*)$", out, re.M))
    problems = []
    if fields.get("uid") in (None, "0"):
        problems.append("the server ran as uid %s: --user did not hold" % fields.get("uid"))
    if fields.get("CapEff") != ZERO_CAPS:
        problems.append("CapEff is %s, not zero: --cap-drop=ALL did not hold" % fields.get("CapEff"))
    if fields.get("CapBnd") != ZERO_CAPS:
        problems.append("CapBnd is %s, not zero: --cap-drop=ALL did not hold" % fields.get("CapBnd"))
    if fields.get("NoNewPrivs") != "1":
        problems.append("NoNewPrivs is %s: no-new-privileges did not hold" % fields.get("NoNewPrivs"))
    if fields.get("routes") != "0":
        problems.append("%s route(s) in /proc/net/route: --network=none did not hold" % fields.get("routes"))
    if "Read-only file system" not in fields.get("rootfs", ""):
        problems.append("a write to /var/tmp gave %r: --read-only did not hold" % fields.get("rootfs"))
    if problems:
        raise Fail("; ".join(problems))


def check_version(out, version):
    if not out.startswith("sideeye %s " % version.lstrip("v")):
        raise Fail("the image's binary says %r, the Dockerfile names %s" % (out.strip(), version))


def check_responses(out, want):
    lines = [l for l in out.split("\n") if l.startswith("{")]
    if len(lines) != 2:
        raise Fail("wanted 2 responses from the page's 2 requests, got %d" % len(lines))
    listed, called = (json.loads(l) for l in lines)
    for name, resp in (("tools/list", listed), ("tools/call", called)):
        if "error" in resp:
            raise Fail("%s was refused at the protocol level: %r" % (name, resp["error"]))
    result = called["result"]
    sc = result.get("structuredContent") or {}
    if result.get("isError") is not False:
        text = (result.get("content") or [{}])[0].get("text", "")
        raise Fail("the call did not reach a verdict: %s" % text[:300])
    if sc.get("verdict") != want:
        raise Fail("wanted %s, got %r" % (want, sc.get("verdict")))
    if want == "PASS" and sc.get("oracle_verified") is not True:
        raise Fail("a PASS without oracle_verified: the image's strace did not witness the run")
    return sc


def sh(cmd, cwd, stdin="", timeout=1200):
    # -e: a block whose build fails must not go on to run whatever image was built before.
    p = subprocess.run(["sh", "-e", "-c", cmd], cwd=cwd, input=stdin, capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def release_json(version):
    # gh when it is there — CI hands it a token, a person's shell has its own login — and a
    # plain unauthenticated read otherwise. Either way a failure names itself rather than
    # passing for a digest mismatch.
    path = "repos/%s/releases/tags/%s" % (REPO, version)
    try:
        if shutil.which("gh"):
            p = subprocess.run(["gh", "api", path], capture_output=True, text=True)
            if p.returncode != 0:
                raise Fail("could not read release %s with gh: %s" % (version, p.stderr.strip()[:300]))
            return json.loads(p.stdout)
        with urllib.request.urlopen("https://api.github.com/" + path, timeout=30) as r:
            return json.load(r)
    except (OSError, ValueError) as e:
        raise Fail("could not read release %s: %s" % (version, e))


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def run(root, workdir):
    page = read(root, "docs/mcp.md")
    dockerfile = read(root, "docs/mcp-container/Dockerfile")
    block, reqs, image, context = page_parts(page)
    version, digests = dockerfile_pins(dockerfile)
    check_pins_agree(version, quickstart_version(read(root, ".github/workflows/quickstart-release.yml")))
    check_release_digests(version, digests, release_json(version))
    print("ok pins: %s, digests match the release, and the quickstart pins the same version" % version)

    workdir.mkdir(parents=True, exist_ok=True)
    ctx = Path(tempfile.mkdtemp(prefix="ctx-", dir=workdir))
    (ctx / context).mkdir()
    (ctx / context / "Dockerfile").write_text(dockerfile.rstrip("\n") + "\n" + TOOL_LINES, encoding="utf-8")
    shutil.copy(root / "spike/toys/toy.c", ctx / context / "toy.c")
    for kind in ("bug", "clean"):
        (ctx / "sideeye-work" / kind).mkdir(parents=True)
        (ctx / "sideeye-work" / kind / "sideeye.toml").write_text(DEFINE.format(kind=kind), encoding="utf-8")
    (ctx / "block.sh").write_text(block, encoding="utf-8")

    for kind, want in (("bug", "FAIL"), ("clean", "PASS")):
        stdin = reqs[0] + "\n" + reqs[1].replace(PLACEHOLDER_CONFIG, "/work/%s/sideeye.toml" % kind) + "\n"
        rc, out, err = sh(block, ctx, stdin)
        (ctx / ("%s.out" % kind)).write_text(out, encoding="utf-8")
        (ctx / ("%s.err" % kind)).write_text(err, encoding="utf-8")
        if rc != 0:
            raise Fail("the page's block exited %d on the %s target; its stderr ends: %s" % (rc, kind, err[-800:]))
        check_responses(out, want)
        print("ok verdicts: the %s target, through the page's block, reached %s" % (kind, want))

    rc, out, err = sh(probe_block(block), ctx, PROBE)
    if rc != 0:
        raise Fail("the probe exited %d; stderr ends: %s" % (rc, err[-800:]))
    check_probe(out)
    print("ok confinement: not root, no capabilities, NoNewPrivs, no route, a read-only root — under the page's flags")

    rc, out, err = sh("docker run --rm %s sideeye version" % image, ctx)
    if rc != 0:
        raise Fail("`sideeye version` in the image exited %d: %s" % (rc, err.strip()[:300]))
    check_version(out, version)
    print("ok version: %s" % out.strip())


def selftest(root):
    page = read(root, "docs/mcp.md")
    dockerfile = read(root, "docs/mcp-container/Dockerfile")
    quick = read(root, ".github/workflows/quickstart-release.yml")
    fails = []

    def ok(name, fn):
        try:
            fn()
        except Fail as e:
            fails.append("%s: unexpectedly red: %s" % (name, e))

    def red(name, fn, needle):
        try:
            fn()
        except Fail as e:
            if needle not in str(e):
                fails.append("%s: red for the wrong reason: %s" % (name, e))
            return
        fails.append("%s: stayed green" % name)

    block, reqs, image, context = page_parts(page)
    version, digests = dockerfile_pins(dockerfile)
    ok("the real page, Dockerfile and quickstart agree", lambda: check_pins_agree(version, quickstart_version(quick)))
    ok("the real block's server command can be swapped for the probe", lambda: probe_block(block))

    sec = section(page, CONTAINER_HEADING)
    red("no sh fence in the container section", lambda: page_parts(page.replace(sec, sec.replace("```sh\n", "```text\n"))), "found 0")
    red("two sh fences in the container section", lambda: page_parts(page.replace(sec, sec + "\n```sh\ntrue\n```\n")), "found 2")
    red("the container heading renamed", lambda: page_parts(page.replace(CONTAINER_HEADING, "## Containers")), "found 0")
    red("the exchange stops naming the placeholder", lambda: page_parts(page.replace(PLACEHOLDER_CONFIG, "/work/sideeye.toml")), "no longer names")
    red("the block's server command changed", lambda: probe_block(block.replace("sideeye mcp", "sideeye serve")), "does not end with")
    red("the block builds from the directory it mounts", lambda: page_parts(page.replace("docker build -t %s %s" % (image, context), "docker build -t %s ." % image)), "a directory of its own")
    red("the block builds from the mount itself", lambda: page_parts(page.replace("docker build -t %s %s" % (image, context), "docker build -t %s sideeye-work" % image)), "a directory of its own")
    red("the block's build names no image", lambda: page_parts(page.replace("docker build -t %s" % image, "docker build")), "names no image")

    red("the Dockerfile's version moved alone", lambda: check_pins_agree("v9.9.9", quickstart_version(quick)), "move them together")
    red("no version default", lambda: dockerfile_pins(dockerfile.replace("ARG SIDEEYE_VERSION=", "ARG SIDEEYE_VERSION_X=")), "found 0")
    swapped = dockerfile.replace("-x86_64-linux.tar.gz", "-TMP.tar.gz").replace("-aarch64-linux.tar.gz", "-x86_64-linux.tar.gz").replace("-TMP.tar.gz", "-aarch64-linux.tar.gz")
    red("the two stages fetch each other's asset", lambda: dockerfile_pins(swapped), "not sideeye-")
    red("the tool marker removed", lambda: dockerfile_pins(dockerfile.replace(TOOL_MARKER, "# tool")), "exactly once")

    release = {"assets": [{"name": "sideeye-%s-%s.tar.gz" % (version, a), "digest": "sha256:" + d} for a, d in digests.items()]}
    ok("digests that match a release", lambda: check_release_digests(version, digests, release))
    tampered = json.loads(json.dumps(release))
    tampered["assets"][0]["digest"] = "sha256:" + "0" * 64
    red("a digest the release does not publish", lambda: check_release_digests(version, digests, tampered), "the release publishes")
    red("a release without the asset", lambda: check_release_digests(version, digests, {"assets": []}), "has no asset")

    ok("the binary the Dockerfile names", lambda: check_version("sideeye %s (trace contract v19)\n" % version.lstrip("v"), version))
    red("another binary", lambda: check_version("sideeye 0.0.1 (trace contract v1)\n", version), "the Dockerfile names")

    good = "uid: 1001\nCapEff:\t%s\nCapBnd:\t%s\nNoNewPrivs:\t1\nroutes: 0\nrootfs: sh: 1: cannot create /var/tmp/sideeye-probe: Read-only file system\n" % (ZERO_CAPS, ZERO_CAPS)
    ok("a confined probe", lambda: check_probe(good))
    red("run as root", lambda: check_probe(good.replace("uid: 1001", "uid: 0")), "--user")
    red("capabilities kept", lambda: check_probe(good.replace("CapEff:\t" + ZERO_CAPS, "CapEff:\t00000000a80425fb")), "--cap-drop=ALL")
    red("a bounding set kept", lambda: check_probe(good.replace("CapBnd:\t" + ZERO_CAPS, "CapBnd:\t00000000a80425fb")), "--cap-drop=ALL")
    red("new privileges allowed", lambda: check_probe(good.replace("NoNewPrivs:\t1", "NoNewPrivs:\t0")), "no-new-privileges")
    red("a network", lambda: check_probe(good.replace("routes: 0", "routes: 2")), "--network=none")
    red("a writable root", lambda: check_probe(good.replace(good.splitlines()[-1], "rootfs: writable")), "--read-only")

    def resp(verdict, verified=True, is_error=False):
        listed = json.dumps({"jsonrpc": "2.0", "id": 1, "result": {"tools": []}})
        called = json.dumps({"jsonrpc": "2.0", "id": 2, "result": {"isError": is_error, "content": [{"text": "x"}],
                             "structuredContent": {"verdict": verdict, "oracle_verified": verified}}})
        return "build noise\n%s\n%s\n" % (listed, called)
    ok("a FAIL on the bug target", lambda: check_responses(resp("FAIL", False), "FAIL"))
    ok("a verified PASS on the clean target", lambda: check_responses(resp("PASS"), "PASS"))
    red("an unverified PASS", lambda: check_responses(resp("PASS", False), "PASS"), "without oracle_verified")
    red("a refusal", lambda: check_responses(resp(None, False, True), "PASS"), "did not reach a verdict")
    red("the wrong verdict", lambda: check_responses(resp("PASS"), "FAIL"), "wanted FAIL")
    red("one response", lambda: check_responses(resp("FAIL").rsplit("\n", 2)[0], "FAIL"), "got 1")

    if fails:
        print("selftest: %d case(s) failed" % len(fails))
        for f in fails:
            print("  " + f)
        sys.exit(1)
    print("selftest: every predicate goes red on its own change, and the real files pass")


def main(argv):
    here = Path(__file__).resolve().parent.parent
    if argv == ["--selftest"]:
        selftest(here)
        return
    if len(argv) != 2:
        sys.exit("usage: check-mcp-container.py <repo-root> <workdir>  |  check-mcp-container.py --selftest")
    try:
        run(Path(argv[0]).resolve(), Path(argv[1]).resolve())
    except Fail as e:
        sys.exit("FAIL %s" % e)


if __name__ == "__main__":
    main(sys.argv[1:])
