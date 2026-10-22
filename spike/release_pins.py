#!/usr/bin/env python3
"""Write, and check, every place in this repository that names a release's version.

Usage: release_pins.py bump X.Y.Z
       release_pins.py pin vX.Y.Z [--tap <homebrew-tap checkout>]
       release_pins.py check [--selftest]

bump   writes the places that move before a release: build.zig.zon, src/contract.zig, and the
       install lines of README.md and docs/cli.md.
pin    writes the places that move after it, because they download the published asset:
       the CI quickstart, its workflow, and the MCP container's Dockerfile with its two Linux
       digests. Each digest is the sha256 of the asset downloaded here, and it must equal the
       digest the release API publishes. --tap also writes yottayoshida/homebrew-tap's
       Formula/sideeye.rb (three URLs, three sha256, and the Zig the tag's build.zig.zon
       names); the pull request there is yours to open.
check  needs no network. Every place before a release names build.zig.zon's version; every
       place after it names one version, which is build.zig.zon's or the release CHANGELOG.md
       lists right below it — the state between a release and its pin commit. A pin that is
       never written goes red on the next bump.
"""
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from collections import namedtuple
from pathlib import Path

REPO = "yottayoshida/sideeye"
SEMVER = re.compile(r"(?<![\d.])\d+\.\d+\.\d+(?![\d.])")
HEX64 = re.compile(r"(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])")


class Fail(Exception):
    pass


Site = namedtuple("Site", "path needle offset kind")

BEFORE = [
    Site("build.zig.zon", '    .version = "', 0, "version"),
    Site("src/contract.zig", 'pub const sideeye_version = "', 0, "version"),
    Site("README.md", "$ tar xzf sideeye-v", 0, "version"),
    Site("docs/cli.md", "$ tar xzf sideeye-v", 0, "version"),
    Site("docs/cli.md", "$ gh api repos/yottayoshida/sideeye/releases/tags/v", 0, "version"),
    Site("docs/cli.md", "$ shasum -a 256 sideeye-v", 0, "version"),
]
AFTER = [
    Site("docs/ci-quickstart.md", "bin=$(sh install-sideeye.sh v", 0, "version"),
    Site(".github/workflows/quickstart-release.yml", "  SIDEEYE_VERSION: v", 0, "version"),
    Site("docs/mcp-container/Dockerfile", "ARG SIDEEYE_VERSION=v", 0, "version"),
    Site("docs/mcp-container/Dockerfile", "sideeye-${SIDEEYE_VERSION}-x86_64-linux.tar.gz", -1, "digest:x86_64-linux"),
    Site("docs/mcp-container/Dockerfile", "sideeye-${SIDEEYE_VERSION}-aarch64-linux.tar.gz", -1, "digest:aarch64-linux"),
]
TAP = [
    Site("Formula/sideeye.rb", "# pins Zig ", 0, "zig"),
] + [
    row
    for asset in ("aarch64-macos", "x86_64-linux", "aarch64-linux")
    for row in (
        Site("Formula/sideeye.rb", '-%s.tar.gz"' % asset, 0, "version"),
        Site("Formula/sideeye.rb", '-%s.tar.gz"' % asset, 1, "digest:%s" % asset),
    )
]


def locate(texts, site):
    path, needle, offset = site.path, site.needle, site.offset
    lines = texts[path].split("\n")
    hits = [i for i, line in enumerate(lines) if needle in line]
    if len(hits) != 1:
        raise Fail("%s: wanted the line holding %r exactly once, found %d" % (path, needle, len(hits)))
    i = hits[0] + offset
    if not 0 <= i < len(lines):
        raise Fail("%s: the line %+d from %r is outside the file" % (path, offset, needle))
    return lines, i


def pattern_of(site):
    return HEX64 if site.kind.startswith("digest:") else SEMVER


def read_site(texts, site):
    lines, i = locate(texts, site)
    pattern = pattern_of(site)
    found = pattern.findall(lines[i])
    if not found or (pattern is HEX64 and len(found) != 1) or len(set(found)) != 1:
        raise Fail("%s:%d: wanted one %s, read %s in %r" % (site.path, i + 1, "sha256" if pattern is HEX64 else "version", found or "none", lines[i].strip()))
    return found[0]


def write_sites(texts, sites, values):
    out = dict(texts)
    for site in sites:
        read_site(out, site)
        lines, i = locate(out, site)
        lines[i] = pattern_of(site).sub(values[site.kind], lines[i])
        out[site.path] = "\n".join(lines)
    return out


def changelog_releases(text):
    return re.findall(r"^## \[(\d+\.\d+\.\d+)\]", text, re.M)


def check(texts):
    zon = read_site(texts, BEFORE[0])
    for site in BEFORE[1:]:
        got = read_site(texts, site)
        if got != zon:
            raise Fail("%s names %s where build.zig.zon names %s; `release_pins.py bump %s` writes them all" % (site.path, got, zon, zon))
    pinned = {read_site(texts, s) for s in AFTER if s.kind == "version"}
    if len(pinned) != 1:
        raise Fail("the places a release pins after it name %s, not one version; `release_pins.py pin vX.Y.Z` writes them together" % sorted(pinned))
    pinned = pinned.pop()
    releases = changelog_releases(texts["CHANGELOG.md"])
    if zon not in releases:
        raise Fail("build.zig.zon names %s and CHANGELOG.md has no `## [%s]` heading" % (zon, zon))
    allowed = releases[releases.index(zon):][:2]
    if pinned not in allowed:
        raise Fail("the places a release pins after it name v%s; with build.zig.zon at %s they may name %s — run `release_pins.py pin v%s`" % (pinned, zon, " or ".join("v" + v for v in allowed), allowed[-1]))
    return zon, pinned


def load(root, sites):
    try:
        return {p: (root / p).read_text(encoding="utf-8") for p in {s.path for s in sites}}
    except OSError as e:
        raise Fail("could not read %s" % e)


def save(root, before, after):
    for path, text in after.items():
        if text != before[path]:
            (root / path).write_text(text, encoding="utf-8")
            print("wrote %s" % path)


def sh(argv, cwd=None):
    p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        raise Fail("%s exited %d: %s" % (" ".join(argv[:4]), p.returncode, p.stderr.strip()[:300]))
    return p.stdout


def verified_digests(tag, assets):
    release = json.loads(sh(["gh", "api", "repos/%s/releases/tags/%s" % (REPO, tag)]))
    published = {a.get("name"): a.get("digest") or "" for a in release.get("assets") or []}
    digests = {}
    with tempfile.TemporaryDirectory() as d:
        for asset in assets:
            name = "sideeye-%s-%s.tar.gz" % (tag, asset)
            api = published.get(name, "")
            if not re.fullmatch(r"sha256:[0-9a-f]{64}", api):
                raise Fail("release %s publishes %r as the digest of %s" % (tag, api or "nothing", name))
            sh(["gh", "release", "download", tag, "-R", REPO, "-p", name, "-D", d])
            got = hashlib.sha256((Path(d) / name).read_bytes()).hexdigest()
            if "sha256:" + got != api:
                raise Fail("%s downloads as sha256:%s; the release publishes %s" % (name, got, api))
            digests["digest:" + asset] = got
            print("ok %s  sha256:%s, as the release publishes" % (name, got))
    return digests


def tag_zig(root, tag):
    zon = sh(["git", "-C", str(root), "show", "%s:build.zig.zon" % tag])
    found = re.findall(r'^\s*\.minimum_zig_version = "(\d+\.\d+\.\d+)"', zon, re.M)
    if len(found) != 1:
        raise Fail("%s:build.zig.zon names no one minimum_zig_version" % tag)
    return found[0]


def pin(root, tag, tap):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise Fail("pin takes a tag, vX.Y.Z; got %r" % tag)
    assets = ["x86_64-linux", "aarch64-linux"] + (["aarch64-macos"] if tap else [])
    zig = {"zig": tag_zig(root, tag)} if tap else {}
    texts = load(root, AFTER)
    tap_texts = load(tap, TAP) if tap else None
    values = {"version": tag[1:], **zig, **verified_digests(tag, assets)}
    written = write_sites(texts, AFTER, values)
    if tap:
        tap_written = write_sites(tap_texts, TAP, values)
    save(root, texts, written)
    if tap:
        save(tap, tap_texts, tap_written)


def bump(root, version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise Fail("bump takes a version, X.Y.Z; got %r" % version)
    texts = load(root, BEFORE)
    save(root, texts, write_sites(texts, BEFORE, {"version": version}))


TAP_FIXTURE = """  # Ships the released build. The project
  # pins Zig 0.16.0 and has been broken by Zig releases before, so a
    on_arm do
      url "https://github.com/yottayoshida/sideeye/releases/download/v1.13.0/sideeye-v1.13.0-aarch64-macos.tar.gz"
      sha256 "bec94bf6d1b5beb49cb72ded4efcaa99f4f6e418514f33f9806544ae0f40fcb1"
    end
    on_intel do
      url "https://github.com/yottayoshida/sideeye/releases/download/v1.13.0/sideeye-v1.13.0-x86_64-linux.tar.gz"
      sha256 "e2aaf8b5fcba752edca019a8a9503095bcea6bfeb582b4e7a1a702324e4e798f"
    end
    on_arm do
      url "https://github.com/yottayoshida/sideeye/releases/download/v1.13.0/sideeye-v1.13.0-aarch64-linux.tar.gz"
      sha256 "93046775f9f5e28f6f6716730aaa3cbab8fa1916c1f41ff0afc73b7cc1ed2e06"
    end
  test do
    assert_match "sideeye #{version}", shell_output("#{bin}/sideeye version")
"""


def selftest(root):
    real = load(root, BEFORE + AFTER + [Site("CHANGELOG.md", "", 0, "")])
    fails = []

    def outcome(name, fn, needle=None):
        try:
            fn()
        except Fail as e:
            if needle is None:
                fails.append("%s: unexpectedly red: %s" % (name, e))
            elif needle not in str(e):
                fails.append("%s: red for the wrong reason: %s" % (name, e))
            return
        if needle is not None:
            fails.append("%s: stayed green" % name)

    zon, pinned = check(real)
    releases = changelog_releases(real["CHANGELOG.md"])
    below = releases[releases.index(zon) + 1]
    two_below = releases[releases.index(zon) + 2]

    def with_sites(sites, version, texts=real):
        return write_sites(texts, sites, {"version": version})

    def replace_once(texts, path, old, new):
        assert texts[path].count(old) == 1, (path, old)
        return {**texts, path: texts[path].replace(old, new)}

    outcome("the tree as committed", lambda: check(real))
    for site in BEFORE[1:]:
        outcome("%s moved alone (%r)" % (site.path, site.needle), lambda s=site: check(with_sites([s], "9.9.9")), "where build.zig.zon names")
    outcome("build.zig.zon moved alone", lambda: check(with_sites(BEFORE[:1], "9.9.9")), "where build.zig.zon names")
    outcome("a bump with no CHANGELOG heading", lambda: check(with_sites(BEFORE, "9.9.9")), "no `## [9.9.9]` heading")
    for site in [s for s in AFTER if s.kind == "version"]:
        outcome("%s pinned alone (%r)" % (site.path, site.needle), lambda s=site: check(with_sites([s], "9.9.9")), "not one version")
    after_versions = [s for s in AFTER if s.kind == "version"]
    outcome("the pins on the release below build.zig.zon's", lambda: check(with_sites(after_versions, below)))
    outcome("the pins on build.zig.zon's release", lambda: check(with_sites(after_versions, zon)))
    outcome("the pins two releases behind", lambda: check(with_sites(after_versions, two_below)), "may name")
    outcome("the pins ahead of build.zig.zon", lambda: check(with_sites(after_versions, zon, with_sites(BEFORE, below))), "may name")
    outcome("one line naming two versions", lambda: check(replace_once(real, "README.md", "&& cd sideeye-v%s" % zon, "&& cd sideeye-v%s" % below)), "wanted one version")
    outcome("a locating line repeated", lambda: check({**real, "docs/cli.md": real["docs/cli.md"] + "\n$ shasum -a 256 sideeye-v%s-x.tar.gz\n" % zon}), "found 2")
    outcome("a locating line gone", lambda: check(replace_once(real, "src/contract.zig", 'pub const sideeye_version = "', 'pub const SIDEEYE_VERSION = "')), "found 0")

    bumped = with_sites(BEFORE, "9.9.9")
    pins = {"version": "9.9.9", "digest:x86_64-linux": "a" * 64, "digest:aarch64-linux": "b" * 64}
    pinned_tree = write_sites(real, AFTER, pins)
    for name, tree, sites in (("bump", bumped, BEFORE), ("pin", pinned_tree, AFTER)):
        listed = {}
        for s in sites:
            listed.setdefault(s.path, set()).add(locate(real, s)[1])
        for path, text in real.items():
            old, new = text.split("\n"), tree[path].split("\n")
            changed = {i for i, (a, b) in enumerate(zip(old, new)) if a != b}
            if len(old) != len(new) or changed != listed.get(path, set()):
                fails.append("%s: %s changed lines %s, the list names %s" % (name, path, sorted(changed), sorted(listed.get(path, set()))))
    dockerfile = pinned_tree["docs/mcp-container/Dockerfile"]
    if dockerfile.count("a" * 64) != 1 or dockerfile.count("b" * 64) != 1 or "v9.9.9" not in dockerfile:
        fails.append("pin: the Dockerfile does not carry the version and both digests it was given")

    tap = {"Formula/sideeye.rb": TAP_FIXTURE}
    tap_values = {"version": "9.9.9", "zig": "0.99.0", "digest:aarch64-macos": "c" * 64, "digest:x86_64-linux": "d" * 64, "digest:aarch64-linux": "e" * 64}
    want_tap = (TAP_FIXTURE.replace("0.16.0", "0.99.0").replace("1.13.0", "9.9.9")
                .replace("bec94bf6d1b5beb49cb72ded4efcaa99f4f6e418514f33f9806544ae0f40fcb1", "c" * 64)
                .replace("e2aaf8b5fcba752edca019a8a9503095bcea6bfeb582b4e7a1a702324e4e798f", "d" * 64)
                .replace("93046775f9f5e28f6f6716730aaa3cbab8fa1916c1f41ff0afc73b7cc1ed2e06", "e" * 64))
    if write_sites(tap, TAP, tap_values)["Formula/sideeye.rb"] != want_tap:
        fails.append("pin --tap: the formula does not come out with each asset's URL and sha256 and the Zig version")
    outcome("pin --tap with an asset's sha256 line missing", lambda: write_sites({"Formula/sideeye.rb": TAP_FIXTURE.replace('      sha256 "e2aaf8b5fcba752edca019a8a9503095bcea6bfeb582b4e7a1a702324e4e798f"\n', '')}, TAP, tap_values), "wanted one sha256")

    if fails:
        sys.exit("FAIL release_pins selftest:\n  " + "\n  ".join(fails))
    print("ok release_pins selftest: build.zig.zon %s, pins v%s; every listed place reddens alone, the pins may lag one release and no more, and bump and pin touch only the listed lines" % (zon, pinned))


def main(argv):
    root = Path(__file__).resolve().parent.parent
    try:
        if argv == ["check", "--selftest"]:
            selftest(root)
        elif argv == ["check"]:
            zon, pinned = check(load(root, BEFORE + AFTER + [Site("CHANGELOG.md", "", 0, "")]))
            print("ok release pins: build.zig.zon %s, the places before a release name it, the places after it name v%s" % (zon, pinned))
        elif len(argv) == 2 and argv[0] == "bump":
            bump(root, argv[1])
        elif len(argv) == 2 and argv[0] == "pin":
            pin(root, argv[1], None)
        elif len(argv) == 4 and argv[0] == "pin" and argv[2] == "--tap":
            pin(root, argv[1], Path(argv[3]).resolve())
        else:
            sys.exit(__doc__.split("\n\n")[1])
    except Fail as e:
        sys.exit("FAIL %s" % e)


if __name__ == "__main__":
    main(sys.argv[1:])
