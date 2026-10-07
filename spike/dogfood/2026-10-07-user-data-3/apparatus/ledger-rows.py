#!/usr/bin/env python3
"""Append this run's rows to the funnel, its campaign line and the B2 exclusions with their aliases.
2026-10-05's script rewritten for this run. No line goes to spike/upstream-reports.tsv: this run filed
nothing (RESULTS.md says why for each FAIL).

The Debian package names are not from memory: each was looked up in trixie's archive by package name
and by the file that ships the command (transcripts/debian-packages.txt). Three names a lookup matched
are other programs and are not excluded: trixie's `pi` (digits of pi), `cap` (capistrano) and `minizip`
(zlib's contrib, not minizip-ng).

Run once from the repository root; it refuses if the campaign already has rows, so a second run
cannot double them.
"""
import sys
from pathlib import Path

C = "dogfood/2026-10-07-user-data-3"
D = "spike/dogfood/2026-10-07-user-data-3"
E = f"{D}/transcripts/explore"
G = f"{D}/transcripts/entry-out/entry"
DAY = "2026-10-07"
NW = "not_worth"
NC = "no_content_lost"

rows = [
    # target, stage, verdict, stop, report, evidence, as_of, note
    # The slate: four waves, eighteen targets (SELECTION.md).
    ("lxc", "judged", "fail", NW, "-", f"{E}/lxc/supervised.json", "-", "FAIL 1/3 under supervised (static Go, the next step for no_shim_marker): lxc alias remove truncates the client's config.yml before its write (118 -> 0 bytes); the remotes and aliases a user adds again. Opened empty, lxc carries on with its defaults and exits 0"),
    ("duplicacy", "judged", "fail", NW, "-", f"{E}/duplicacy/supervised.json", "-", "FAIL 1/3 under supervised (static Go, the next step for no_shim_marker): set -no-backup truncates .duplicacy/preferences (360 -> 0); every later command refuses on the parse error until init is run again against the storage, which holds every backup"),
    ("ferium", "judged", "fail", NW, "-", f"{E}/ferium/supervised.json", "-", "FAIL 1/4 under supervised (static Rust, the next step for no_shim_marker): profile configure truncates config.json (475 -> 0); ferium refuses on the parse error, and ferium scan rebuilds a profile's mod list from its directory"),
    ("easyrsa", "attempted", "unknown", "wall", "-", f"{E}/easyrsa/syscalls.json", "-", "child_touched_state_dir by default (openssl, sed and mv write the PKI); --observe syscalls, the next step, ended recording_run_failed with the clock pinned (libfaketime's preload and the syscall trap: the children died of SIGSYS), and without the pin baseline_violates_invariant (each run stamps its own times). Not judged in this box"),
    ("tiddlywiki", "judged", "fail", "known", "-", f"{E}/tiddlywiki/explore.json", "-", "FAIL 1/3: --load wiki.html --render $:/core/save/all wiki.html, the in-place update a forum recipe gives, truncates the single-file wiki before its write (2,552,578 -> 0 bytes), and loading the empty file builds an empty wiki with exit 0. Not filed: tiddlywiki.com's examples render to another file, and talk.tiddlywiki.org thread 3482 (2022) already warns that rendering over the source can leave an empty file, with the render-elsewhere-then-rename workaround"),
    ("broot", "judged", "pass", "-", "-", f"{E}/broot/explore.json", "-", "PASS 23/23: --install writes its launcher files new (absent before, not judged) and opens .bashrc O_APPEND for one line"),
    ("ziptool", "judged", "pass", "-", "-", f"{E}/ziptool/syscalls.json", "-", "PASS 6/6 under --observe syscalls (the next step for oracle_missed_operation): ziptool delete writes a.zip.<n>.part created O_EXCL and renames it over a.zip (1.11.4, built from the release tarball)"),
    ("xbps", "judged", "pass", "-", "-", f"{E}/xbps/explore.json", "-", "PASS 6/6: xbps-pkgdb -m hold writes .plist<n> created O_EXCL and renames it over pkgdb-0.38.plist (0.60.7, built at its tag)"),
    ("mcpm", "judged", "fail", NW, "-", f"{E}/mcpm/explore.json", "-", "FAIL 4/33: edit truncates servers.json (272 -> 0); the MCP server definitions and their environment, keys a user re-issues. Opened empty, every later command prints the decode error and exits 0, and the next new writes a file holding only its own server"),
    ("sndfile", "judged", "fail", NC, "-", f"{E}/sndfile/explore.json", "-", "FAIL 1/4: sndfile-metadata-set appends the LIST chunk, then rewrites the RIFF size; killed between, the RIFF size is stale (32036 for 32072 bytes) and the 16000 frames intact, read whole by sndfile-info and sndfile-convert (lab-12.txt)"),
    ("ezdxf", "judged", "fail", NC, "-", f"{E}/ezdxf/explore.json", "-", "FAIL 1/11: strip writes drawing.ezdxf.tmp, renames drawing.dxf to drawing.bak, then the tmp over drawing.dxf; killed between the renames, drawing.dxf is absent with its old bytes whole in drawing.bak and the new in drawing.ezdxf.tmp"),
    ("pi", "judged", "fail", NW, "-", f"{E}/pi/explore.json", "-", "FAIL 1/9 (Node 22): pi install truncates agent/settings.json (52 -> 0) and leaves settings.json.lock behind, after which every pi command fails 'Lock file is already being held' until the directory is removed; settings. Its CONTRIBUTING.md bars LLM-written issues"),
    ("doit", "judged", "fail", NW, "-", f"{E}/doit/explore.json", "-", "FAIL 1/3: forget truncates the JSON dependency file (414 -> 0); every later command raises the decode error; a cache the next run rebuilds"),
    ("kitty", "judged", "pass", "-", "-", f"{E}/kitten/supervised.json", "-", "PASS 11/11 under supervised (static Go, the next step for no_shim_marker): kitten themes writes current-theme.conf and kitty.conf each through <name>.atomic-write-<n> created O_EXCL, fsynced and renamed; kitty.conf.bak is written new"),
    ("alacritty", "judged", "pass", "-", "-", f"{E}/alacritty/syscalls.json", "-", "PASS 9/9 under --observe syscalls (the next step for oracle_missed_operation): migrate writes .tmp<n> created O_EXCL and renames it over each file (0.17.0, built at its tag)"),
    ("gitmoji", "judged", "fail", NW, "-", f"{E}/gitmoji/explore.json", "-", "FAIL 1/3: gitmoji -i truncates .git/hooks/prepare-commit-msg (194 -> 0); its completed run replaces a hand-written hook as well, so the crash loses nothing the run would not"),
    ("astro", "judged", "fail", NW, "-", f"{E}/astro/explore.json", "-", "FAIL 1/4 (Node 22): preferences disable --global truncates settings.json (41 -> 0); a setting, read back as none set"),
    ("roswell", "judged", "fail", NW, "-", f"{E}/roswell/probe-supervised.json", "-", "FAIL 1/3 under --observe supervised asked for by name: ros config set truncates config (64 -> 0); a setting. The page's path ended at unresolvable_path, whose next step says the target is refused by design: the static ros starts a dynamic SBCL, the shape of #685 under another refusal"),
    # Explored, then out of the slate on rule 14.
    ("zshz", "judged", "fail", "known", "-", f"{E}/zshz/syscalls.json", "-", "FAIL 1/7 under --observe syscalls (the next step for oracle_missed_operation): zshz --add writes .z.<pid> whole, then truncates .z and copies it in; killed between, .z is empty and the new list whole in .z.<pid>. Rule 14: agkozak/zsh-z#19 asked that .z not be replaced through a symlink, which is why it is copied in place"),
    ("openssl", "judged", "fail", "known", "-", f"{E}/openssl/explore.json", "-", "FAIL 2/9 with the clock pinned: ca -revoke rotates index.txt by two renames; killed between, index.txt is absent with its old bytes in index.txt.old. Rule 14: openssl/openssl#2867 (CA file rotation is not atomic)"),
    ("sfntedit", "judged", "fail", "known", "-", f"{E}/sfntedit/explore.json", "-", "FAIL 1/3: sfntedit -a copies its temporary file back over f.ttf, truncating it first (632 -> 0). Rule 14: adobe-type-tools/afdko#594 (open) names sfntedit's temporary-file path"),
    ("acmesh", "judged", "fail", "known", "-", f"{E}/acmesh/syscalls.json", "-", "FAIL 3/5 under --observe syscalls (the next step for oracle_missed_operation): --set-default-ca truncates account.conf (201 -> 0). Rule 14: acmesh-official/acme.sh#7247 (open), the same _setopt writer emptying a domain's conf on a full disk"),
    ("minizip", "judged", "fail", "known", "-", f"{E}/minizip/explore.json", "-", "FAIL 1/3: minizip -e renames a.zip to a.zip.bak, then the new archive from TMPDIR over a.zip; killed between, a.zip is absent with its old bytes in a.zip.bak. Rule 14: zlib-ng/minizip-ng#985 placed that temporary file"),
    # Cleared the gate, out before an explore.
    ("git-lfs", "attempted", "-", "-", "-", f"{G}/gitlfs.preflight.txt", "-", "Cleared the gate under supervised; out before its explore: every write of git lfs install is a git config child, so the explore would measure git"),
    ("keyring", "attempted", "-", "-", "-", f"{G}/keyring.preflight.txt", "-", "Cleared the gate; out before its explore: the file it writes is keyrings.alt's (29 stars), the backend that holds the bytes, not keyring's"),
    # Walls at the gate.
    ("rustic", "attempted", "unknown", "wall", "-", f"{G}/rustic.preflight.txt", "-", "rustic 0.11.4 forget --prune: multiple_threads_detected at the gate"),
    ("prek", "attempted", "unknown", "wall", "-", f"{G}/prek.preflight.txt", "-", "prek 0.5.5 install: multiple_threads_detected at the gate"),
    ("cspell", "attempted", "unknown", "wall", "-", f"{G}/cspell.preflight.txt", "-", "cspell 10.3.6 link add (Node 22): multiple_threads_detected at the gate"),
    ("capacitor", "attempted", "unknown", "wall", "-", f"{G}/capacitor.preflight.txt", "-", "capacitor 8.5.2 telemetry off (Node 22): multiple_threads_detected at the gate"),
    ("espsecure", "attempted", "unknown", "wall", "-", f"{G}/espsecure.preflight.txt", "-", "espsecure (esptool 5.4.0) sign-data: --twice differs at the gate, a fresh ECDSA nonce in every signature"),
    ("plakar", "attempted", "unknown", "wall", "-", f"{G}/plakar.preflight.txt", "-", "plakar rm -apply: --twice differs at the gate, the repository's encryption"),
    ("goaccess", "attempted", "unknown", "wall", "-", f"{G}/goaccess.preflight.txt", "-", "goaccess 1.12 --persist --restore: unsupported_syscall_observed at the gate, a write through mmap(PROT_WRITE|MAP_SHARED) (#689)"),
    ("ostree", "attempted", "unknown", "wall", "-", f"{G}/ostree.preflight.txt", "-", "libostree 2026.4 remote add: unresolvable_path at the gate"),
]

# Names in the funnel above that are not themselves the trixie package, mapped to the packages that ship
# them (`-` where trixie has none, or only another program under the name).
aliases = [
    ("lxc", "lxd;lxd-client", "outcome-funnel.tsv (the LXD client: upstream's 6.9 measured, trixie ships 5.0; trixie's lxc package is LXC, another project)"),
    ("sndfile", "sndfile-programs", "outcome-funnel.tsv (libsndfile)"),
    ("ezdxf", "python3-ezdxf", "outcome-funnel.tsv"),
    ("doit", "python3-doit", "outcome-funnel.tsv"),
    ("sfntedit", "afdko;python3-afdko", "outcome-funnel.tsv"),
    ("easyrsa", "easy-rsa", "outcome-funnel.tsv"),
    ("acmesh", "acme.sh", "outcome-funnel.tsv"),
    ("zshz", "-", "outcome-funnel.tsv (zsh-z; trixie has none)"),
    ("espsecure", "esptool", "outcome-funnel.tsv"),
    ("keyring", "python3-keyring", "outcome-funnel.tsv"),
    ("pi", "-", "outcome-funnel.tsv (earendil-works/pi; trixie's pi is another program)"),
    ("capacitor", "-", "outcome-funnel.tsv (trixie's cap is capistrano)"),
    ("minizip", "-", "outcome-funnel.tsv (minizip-ng; trixie's minizip is zlib's contrib)"),
]
aliased = {a for a, _, _ in aliases}

root = Path(".")
funnel = root / "spike/outcome-funnel.tsv"
text = funnel.read_text()
if f"\n{C}\t" in text:
    sys.exit("rows for this campaign already exist")
for r in rows:
    assert len(r) == 8 and all(f for f in r) and not any("\t" in f for f in r), r
assert len({r[0] for r in rows}) == len(rows), "a target twice"
with funnel.open("a") as f:
    for t, *rest in rows:
        f.write("\t".join([C, t, *rest]) + "\n")

screened = len({l.split()[1] for p in sorted((root / D / "transcripts").rglob("*.txt"))
                if p.name.startswith(("fresh-screen-", "word-recheck-"))
                for l in p.read_text().splitlines() if l.startswith(("fresh ", "SEEN "))})
camp = root / "spike/outcome-funnel-campaigns.tsv"
with camp.open("a") as f:
    f.write("\t".join([C, DAY, "full", str(screened), f"{D}/RESULTS.md"]) + "\n")

# B2: every funnel name that is a package or has no package, and every package an alias names.
why = f"measured ({D})"
b2 = root / "spike/unknown-rate/b2-exclusions.txt"
lines = b2.read_text().split("\n")
head = [l for l in lines if l.startswith("#")]
body = {l.split("\t")[0]: l for l in lines if l and not l.startswith("#")}
want = [t for t, *_ in rows if t not in aliased]
want += [p for _, ps, _ in aliases for p in ps.split(";") if p != "-"]
added = upgraded = 0
for n in want:
    if n not in body:
        body[n] = f"{n}\t{why}"; added += 1
    elif not body[n].split("\t")[1].startswith("measured"):
        body[n] = f"{n}\t{why}"; upgraded += 1
b2.write_text("\n".join(head + [body[k] for k in sorted(body)]) + "\n")

al = root / "spike/unknown-rate/b2-exclusion-aliases.tsv"
with al.open("a") as f:
    for line in aliases:
        f.write("\t".join(line) + "\n")

print(len(rows), "funnel rows, 1 campaign (", screened, "names screened ), 0 reports,",
      added, "B2 lines added,", upgraded, "upgraded,", len(aliases), "aliases")
