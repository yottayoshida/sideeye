#!/usr/bin/env python3
"""Append this run's rows to the funnel, its campaign line and the B2 exclusions with their aliases.
2026-10-07's script rewritten for this run. Whether a line goes to spike/upstream-reports.tsv is the
owner's call on the two drafts (RESULTS.md); seconv and MCA Selector stand at `report_worthy` until it
is made, as talosctl and gltfpack did.

The Debian package names are from trixie's archive by name (transcripts/debian-packages.txt; the
by-file lookup returned nothing for every name, and is not relied on). Five names a lookup matched are
not the tool measured: trixie's atac is a genome-assembly tool, its trash-cli is andreafrancia's, and
mcaselector and ckan matched only the .debs this run installed into the box; root-system has no
candidate in trixie.

Run once from the repository root; it refuses if the campaign already has rows.
After this script ran, the owner approved both drafts' full text and they were filed as
SubtitleEdit/subtitleedit#15829 and Querz/mcaselector#613; the two funnel rows were then moved to
`filed`/`awaiting` by hand, beside two lines in spike/upstream-reports.tsv, the markers in
docs/target-classes.md and two aliases. The shim defect is #753.
"""
import sys
from pathlib import Path

C = "dogfood/2026-10-09-user-data-4"
D = "spike/dogfood/2026-10-09-user-data-4"
E = f"{D}/transcripts/explore"
G = f"{D}/transcripts/entry-out/entry"
DAY = "2026-10-09"
NW = "not_worth"
NC = "no_content_lost"
SUP = "under supervised (static {}, the next step for no_shim_marker)"

rows = [
    # target, stage, verdict, stop, report, evidence, as_of, note
    # Wave 1
    ("scw", "judged", "fail", NW, "-", f"{E}/scw/supervised.json", "-", "FAIL 1/3 " + SUP.format("Go") + ": scw config set truncates config.yaml before its write (140 -> 0 bytes), the file where a profile's access and secret keys live; settings and keys a user re-issues"),
    ("f2", "judged", "fail", NC, "-", f"{E}/f2/supervised.json", "-", "FAIL 2/4 " + SUP.format("Go") + " with a checker (the batch whole, each photo's bytes under one name): killed between two renames, a half-renamed batch; the undo record is written after the renames, so none is left. Every photo's bytes survive"),
    ("seconv", "report_worthy", "fail", "-", "-", f"{E}/seconv/explore.json", "-", "FAIL 1/4 (.NET, DOTNET_EnableDiagnostics=0): seconv --overwrite truncates the input subtitle before its write (175 -> 0 bytes), the old text nowhere; reproduced with strace's inject, and main writes the same way. Drafted (report-seconv.md); filing is the owner's call"),
    ("otiotool", "judged", "fail", NW, "-", f"{E}/otiotool/explore.json", "-", "FAIL 1/3: otiotool -i cut.otio --redact -o cut.otio truncates the timeline before its write (5208 -> 0); in place only when -o names the input, which the tutorial does not do"),
    ("cook", "judged", "pass", "-", "-", f"{E}/cook/supervised.json", "-", "PASS 6/6 " + SUP.format("Rust") + ": cook pantry add writes .pantry.conf.<pid>.tmp, fsyncs it and renames it over pantry.conf"),
    # Wave 2
    ("mcaselector", "report_worthy", "fail", "-", "-", f"{E}/mcaselector/explore.json", "-", "FAIL 1/3: --mode delete writes the new region to /tmp, unlinks region/r.0.0.mca and renames the temp in (the JDK's Files.move REPLACE_EXISTING); killed between, the region file is absent and its replacement only in /tmp. The README asks for a backup of the world first. Drafted (report-mcaselector.md); filing is the owner's call"),
    ("nmctl", "judged", "fail", NW, "-", f"{E}/nmctl/supervised.json", "-", "FAIL 1/3 " + SUP.format("Go") + ": nmctl context set truncates config.yml before its write (75 -> 0), every context with its master key; endpoints and keys a user re-issues"),
    ("libdeflate", "judged", "pass", "-", "-", f"{E}/libdeflate/explore.json", "-", "PASS 4/4 with a checker (the text in notes.txt or inside notes.txt.gz): libdeflate-gzip creates notes.txt.gz O_EXCL, writes it, closes, then unlinks the input; no fsync. Without the checker, nothing_could_fail (explore/libdeflate-nocheck)"),
    ("stack", "judged", "fail", NW, "-", f"{E}/stack/supervised.json", "-", "FAIL 1/117 " + SUP.format("Haskell") + ", the SQLite caches scratch: config set truncates config.yaml before its write (255 -> 0); settings"),
    ("cabal", "judged", "fail", NC, "-", f"{E}/cabal/supervised.json", "-", "FAIL 2/4 " + SUP.format("Haskell") + ": user-config update renames config to config.backup, then a new file in from TMPDIR; killed between, config is absent with its old bytes whole in config.backup"),
    # Wave 3
    ("carapace", "judged", "fail", NW, "-", f"{E}/carapace/supervised.json", "-", "FAIL 1/3 " + SUP.format("Go") + ": carapace --style truncates styles.json before its write (77 -> 0); styles"),
    ("chdman", "judged", "fail", NC, "-", f"{E}/chdman/explore.json", "-", "FAIL 2/5: chdman addmeta appends the metadata entry, then rewrites the header's pointer; killed between, d.chd is neither old nor new, and the same state still opens in chdman info and chdman extractraw returns the raw data byte for byte (lab-22.txt). MAME 0.276 from Debian"),
    ("hunspell", "judged", "pass", "-", "-", f"{E}/hunspell/explore.json", "-", "PASS 3/3: the personal dictionary opened O_APPEND, judged by the history form (an appended tail); hunspell 1.7.5 built from its release tarball, through sh -c with its commands in a file"),
    ("buildx", "judged", "pass", "-", "-", f"{E}/buildx/supervised.json", "-", "PASS 14/14 " + SUP.format("Go") + ", activity scratch: buildx create --append writes instances/b1 through .tmp-b1<n> created O_EXCL, fsynced and renamed"),
    ("zvm", "judged", "fail", NW, "-", f"{E}/zvm/supervised.json", "-", "FAIL 2/5 " + SUP.format("Go") + ": zvm vmu truncates settings.json before its write (331 -> 0); settings"),
    # Wave 4
    ("iconvert", "judged", "fail", NW, "-", f"{E}/iconvert/probe-supervised.json", "-", "FAIL 1/7 under --observe supervised asked for by name: iconvert --inplace writes photo.jpg.tmp.jpg, removes photo.jpg and renames; killed between, photo.jpg is absent with the new image whole beside it (upstream main the same order). The page's path ended recording_run_failed: with the shim loaded, iconvert and oiiotool abort (std::system_error). OpenImageIO 2.5.18 from Debian"),
    ("ifcpatch", "judged", "pass", "-", "-", f"{E}/ifcpatch/explore.json", "-", "PASS 48/48 with the clock pinned: ifcpatch -i model.ifc -r Optimise (no -o) writes model.ifc.<n>.tmp and renames it over model.ifc; no fsync"),
    ("fly", "judged", "fail", NW, "-", f"{E}/fly/supervised.json", "-", "FAIL 1/3 " + SUP.format("Go") + ": Concourse's fly edit-target truncates .flyrc before its write (185 -> 0), every target and its token; tokens a user logs in again for"),
    ("atac", "judged", "pass", "-", "-", f"{E}/atac/supervised.json", "-", "PASS 8/8 " + SUP.format("Rust") + ", atac.log scratch: request new writes demo.json_ and renames it over demo.json, twice; no fsync"),
    ("ckan", "judged", "fail", NW, "-", f"{E}/ckan/explore.json", "-", "FAIL 1/3 (Mono): ckan compat add truncates the game's CKAN/compatible_ksp_versions.json before its write (81 -> 0); versions a user lists again"),
    ("rpk", "judged", "pass", "-", "-", f"{E}/rpk/supervised.json", "-", "PASS 4/4 " + SUP.format("Go") + ": rpk profile use writes a temporary name and renames it over rpk.yaml; no fsync"),
    ("kafkactl", "judged", "fail", NW, "-", f"{E}/kafkactl/supervised.json", "-", "FAIL 1/4 " + SUP.format("Go") + ": kafkactl config use-context truncates current-context.yml before its write (19 -> 0); a setting"),
    # Walls at the gate
    ("prefscleaner", "attempted", "unknown", "wall", "-", f"{G}/prefscleaner.preflight.txt", "-", "arkenfox prefsCleaner.sh (tag 144.0) refuses root and root-owned files, so the define drops to uid 1000 through setpriv: child_process_detected at the gate (an image replacement whose chain of observation broke); under --observe supervised, --twice ended differently, the restore not rebuilding owners (#678)"),
    ("yarn", "attempted", "unknown", "wall", "-", f"{G}/yarn.preflight.txt", "-", "yarn 4.18.1 config set (Node 20): multiple_threads_detected at the gate"),
    ("trash", "attempted", "unknown", "wall", "-", f"{G}/trash.preflight.txt", "-", "sindresorhus/trash-cli 7.2.0 trash (Node 20): multiple_threads_detected at the gate"),
    ("softhsm", "attempted", "unknown", "wall", "-", f"{G}/softhsm.preflight.txt", "-", "softhsm2-util 2.6.1 --import: --twice differs at the gate, each object and lock named by a random UUID"),
    ("kvantum", "attempted", "unknown", "wall", "-", f"{G}/kvantum.preflight.txt", "-", "kvantummanager 1.1.4 --set: unresolvable_path at the gate, an unlinked-fd write (Qt's save through O_TMPFILE)"),
    ("h2cli", "attempted", "unknown", "wall", "-", f"{G}/h2cli.preflight.txt", "-", "Hydrogen 1.2.2's h2cli -u: unresolvable_path at the gate, an unlinked-fd write (Kvantum's shape)"),
    ("rootrm", "attempted", "unknown", "wall", "-", f"{G}/rootrm.preflight.txt", "-", "ROOT 6.40.04 rootrm: recording_run_failed, SIGABRT at TUUID.cxx:171 (GetCryptoRandom) with the shim loaded, exit 0 by hand (lab-16.txt, not settled); under --observe supervised --twice differs, a random UUID written into the file"),
]

# Names in the funnel above that are not themselves the trixie package, mapped to the packages that ship
# them (`-` where trixie has none, or only another program under the name).
aliases = [
    ("scw", "-", "outcome-funnel.tsv (scaleway-cli; trixie has none)"),
    ("seconv", "-", "outcome-funnel.tsv (Subtitle Edit's command-line converter; trixie has none)"),
    ("otiotool", "-", "outcome-funnel.tsv (OpenTimelineIO; trixie has none)"),
    ("cook", "-", "outcome-funnel.tsv (cooklang/cookcli; trixie has none)"),
    ("mcaselector", "-", "outcome-funnel.tsv (trixie has none; the box's .deb matched by name)"),
    ("nmctl", "-", "outcome-funnel.tsv (netmaker's CLI; trixie has none)"),
    ("libdeflate", "libdeflate-tools", "outcome-funnel.tsv"),
    ("stack", "haskell-stack", "outcome-funnel.tsv"),
    ("cabal", "cabal-install", "outcome-funnel.tsv"),
    ("carapace", "-", "outcome-funnel.tsv (carapace-bin; trixie has none)"),
    ("chdman", "mame-tools", "outcome-funnel.tsv"),
    ("buildx", "docker-buildx", "outcome-funnel.tsv"),
    ("iconvert", "openimageio-tools", "outcome-funnel.tsv"),
    ("ifcpatch", "-", "outcome-funnel.tsv (IfcOpenShell; trixie has none)"),
    ("prefscleaner", "-", "outcome-funnel.tsv (arkenfox user.js; trixie has none)"),
    ("yarn", "yarnpkg", "outcome-funnel.tsv (trixie's yarnpkg is Yarn 4)"),
    ("trash", "-", "outcome-funnel.tsv (sindresorhus/trash-cli; trixie's trash-cli is andreafrancia's, another program)"),
    ("softhsm", "softhsm2", "outcome-funnel.tsv"),
    ("kvantum", "qt6-style-kvantum", "outcome-funnel.tsv"),
    ("h2cli", "hydrogen", "outcome-funnel.tsv"),
    ("rootrm", "-", "outcome-funnel.tsv (ROOT; trixie has no root-system)"),
    ("f2", "-", "outcome-funnel.tsv (ayoisaiah/f2; trixie has none)"),
    ("zvm", "-", "outcome-funnel.tsv (tristanisham/zvm; trixie has none)"),
    ("fly", "-", "outcome-funnel.tsv (Concourse's fly; trixie has none)"),
    ("atac", "-", "outcome-funnel.tsv (Julien-cpsn/ATAC; trixie's atac is a genome-assembly tool)"),
    ("ckan", "-", "outcome-funnel.tsv (KSP-CKAN; trixie has none, the box's .deb matched by name)"),
    ("rpk", "-", "outcome-funnel.tsv (Redpanda's rpk; trixie has none)"),
    ("kafkactl", "-", "outcome-funnel.tsv (deviceinsight/kafkactl; trixie has none)"),
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
