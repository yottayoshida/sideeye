#!/usr/bin/env python3
"""Insert this run's rows into docs/target-classes.md: verdicts at the end of the measured table, walls
at the end of the refusals table. Run once from the repository root; refuses if the run's path is
already in the file. 2026-10-07's script, rewritten for this run's twenty-two. Every number is the
engine's (apparatus/verdicts.py, transcripts/verdicts.txt, the evidence bundles' consequence tables).

No backticked word holds a `/`: acceptance check 11 reads such a word as a path in this repository.
After this script ran, the owner approved both drafts' full text and they were filed as
SubtitleEdit/subtitleedit#15829 and Querz/mcaselector#613; the two funnel rows were then moved to
`filed`/`awaiting` by hand, beside two lines in spike/upstream-reports.tsv, the markers in
docs/target-classes.md and two aliases. The shim defect is #753.
"""
from pathlib import Path

R = "`spike/dogfood/2026-10-09-user-data-4/RESULTS.md`"
T = "truncating `open`"
SG = "static Go, `--observe supervised`"
SH = "static Haskell, `--observe supervised`"


def fail(cls, tool, worlds, cp, path, before, extra=""):
    return (f"| {cls} | {tool} | **FAIL** {worlds} explored worlds, crash point {cp} — the {T} "
            f"of `{path}` and the kill before its `write`: **0 bytes** ({before} before), the old bytes "
            f"nowhere. Replayed twice.{(' ' + extra) if extra else ''} | {R} |")


def ok(cls, tool, text):
    return f"| {cls} | {tool} | **PASS** {text} | {R} |"


verdicts = [
    fail(f"Cloud CLI writing its profile ({SG})", "scw 2.65.1 `config set default-region=fr-par`", "1/3", "2 of 2",
         "config.yaml", "140", "The file where a profile's access and secret keys live. Not filed: settings and keys a user re-issues"),
    (f"| Batch renamer (static Go, `--observe supervised`, a checker: the batch whole, each photo's bytes under one "
     f"name) | f2 2.2.2 `-f IMG_ -r trip_ -x` | **FAIL** 2/4 explored worlds, crash point 2 of 3 — killed between the "
     f"first rename and the second: `trip_1.jpg` beside `IMG_2.jpg` and `IMG_3.jpg`, a half-renamed batch, and no "
     f"undo record (it is written after the renames). Replayed twice. Not filed: every photo's bytes survive | {R} |"),
    fail("Subtitle converter writing over its input (.NET)", "Subtitle Edit's SeConv 5.2.0 `subs.srt subrip --offset:-2000 --overwrite`",
         "1/4", "3 of 3", "subs.srt", "175",
         "Reproduced without Sideeye by strace's `inject` on its `pwrite64`; upstream `main` writes with `File.WriteAllText` too. "
         "Drafted for upstream, filing the owner's call"),
    fail("Editorial timeline written back to its input (Python)", "OpenTimelineIO 0.18.1 `otiotool -i cut.otio --redact -o cut.otio`",
         "1/3", "2 of 2", "cut.otio", "5,208",
         "Not filed: in place only when `-o` names the input, which the tutorial does not do"),
    ok(f"Recipe manager's pantry (static Rust, `--observe supervised`)", "cookcli 0.38.0 `pantry add dairy eggs --quantity 6`",
       "6/6: `.pantry.conf.<pid>.tmp` written, `fsync`ed and renamed over `pantry.conf`"),
    (f"| Minecraft world editor deleting chunks (Java) | MCA Selector 2.9 `--mode delete --query \"InhabitedTime < 1000\"` | "
     f"**FAIL** 1/3 explored worlds, crash point 2 of 2 — the new region written in the system temp directory, the region "
     f"file unlinked (the JDK's `Files.move` with `REPLACE_EXISTING`), and the kill before the rename: the region file "
     f"absent (32,768 bytes before), its replacement only in the temp directory. Replayed twice; reproduced without "
     f"Sideeye by strace's `inject`. The README asks for a backup of the world first. Drafted for upstream, filing the "
     f"owner's call | {R} |"),
    fail(f"Mesh-VPN client writing its contexts ({SG})", "netmaker's nmctl 1.7.0 `context set c1 …`", "1/3", "2 of 2",
         "config.yml", "75", "Every context with its master key. Not filed: endpoints and keys a user re-issues"),
    ok("gzip replacing its input (C, a checker: the text in either file)", "libdeflate 1.26 `libdeflate-gzip notes.txt`",
       "4/4: `notes.txt.gz` created `O_EXCL`, written and closed, then the input unlinked; no `fsync`. Without the "
       "checker, `nothing_could_fail`: no path exists before and after"),
    fail(f"Haskell build tool's user config ({SH}, the SQLite caches scratch)", "stack 3.11.1 `config set install-ghc false --global`",
         "1/117", "116 of 116", "config.yaml", "255", "Not filed: settings"),
    (f"| Haskell build tool's user config ({SH}) | cabal-install 3.18.2.0 `user-config update -a 'jobs: 4'` | "
     f"**FAIL** 2/4 explored worlds, crash point 2 of 3 — `config` renamed to `config.backup`, and the kill before the "
     f"new file is renamed in from TMPDIR: `config` absent, its old bytes whole in `config.backup`. Replayed twice. "
     f"Not filed: a rename restores it | {R} |"),
    fail(f"Shell-completion styles ({SG})", "carapace-bin 1.8.0 `--style carapace.Error=red`", "1/3", "2 of 2",
         "styles.json", "77", "Not filed: styles"),
    (f"| Disc-image metadata added in place (C++) | MAME 0.276's chdman (Debian) `addmeta -i d.chd -t NOTE -vt hello` | "
     f"**FAIL** 2/5 explored worlds, crash point 3 of 4 — the metadata entry appended, and the kill before the header's "
     f"pointer is rewritten: `d.chd` neither old nor new. Replayed twice. Not filed: the same state still opens in "
     f"`chdman info`, and `chdman extractraw` returns the raw data byte for byte | {R} |"),
    ok("Spell checker's personal dictionary (C++, through `sh -c`)", "hunspell 1.7.5 `-a -d en_US -p my.dic`",
       "3/3: `my.dic` opened `O_APPEND`, judged by the history form (an appended tail)"),
    ok(f"Container builder's instances ({SG}, the remote driver)", "buildx 0.38.0 `create --append --name b1 --node b1x …`",
       "14/14: the instance file through `.tmp-b1<n>` created `O_EXCL`, `fsync`ed and renamed"),
    fail(f"Zig version manager's settings ({SG})", "zvm 0.9.1 `vmu zls …`", "2/5", "2 of 4", "settings.json", "331",
         "Not filed: settings"),
    (f"| Image metadata written in place (C++, `--observe supervised` asked for by name) | OpenImageIO 2.5.18 (Debian) "
     f"`iconvert --inplace --caption hello --keyword k photo.jpg` | **FAIL** 1/7 explored worlds, crash point 6 of 6 — "
     f"`photo.jpg.tmp.jpg` written, `photo.jpg` removed, and the kill before the rename: `photo.jpg` absent, the new "
     f"image whole beside it; upstream `main` removes and renames in the same order. The page's path ended "
     f"`recording_run_failed` (refusals table). Not filed: a rename restores the image the run was writing | {R} |"),
    ok("Building model patched over its input (Python and C++, the clock pinned)", "IfcOpenShell's ifcpatch 0.9.0 `-i model.ifc -r Optimise`",
       "48/48: `model.ifc.<n>.tmp` written and renamed over `model.ifc`; no `fsync`"),
    fail(f"CI client's targets ({SG})", "Concourse's fly 8.3.1 `-t ci edit-target --team-name t2`", "1/3", "2 of 2",
         ".flyrc", "185", "Every target and its token. Not filed: tokens a user logs in again for"),
    ok(f"Terminal API client's collection (static Rust, `--observe supervised`)", "ATAC 0.23.1 `request new demo/pong …`",
       "8/8: `demo.json_` written and renamed over `demo.json`, twice; no `fsync`"),
    fail("Mod manager's compatible game versions (Mono)", "CKAN 1.36.4 `compat add 1.7`", "1/3", "2 of 2",
         "compatible_ksp_versions.json", "81", "In the game's `CKAN` directory. Not filed: versions a user lists again"),
    ok(f"Streaming platform CLI's profiles ({SG})", "Redpanda's rpk 26.2.2 `profile use a`",
       "4/4: a temporary name written and renamed over `rpk.yaml`; no `fsync`"),
    fail(f"Kafka CLI's current context ({SG})", "kafkactl 5.20.0 `config use-context b`", "1/4", "2 of 3",
         "current-context.yml", "19", "Not filed: a setting"),
]

walls = [
    (f"| Library the shim breaks on load (C++) | OpenImageIO 2.5.18 `iconvert`, ROOT 6.40.04 `rootrm` | "
     f"`recording_run_failed`, SIGABRT, where a run by hand exits 0: with only the shim preloaded, iconvert and "
     f"oiiotool end `std::system_error` and abort; conda-forge's ROOT aborts at `TUUID.cxx:171` because its "
     f"random source fails, and no open of the random device reaches the kernel, while the box's own C, C++ and "
     f"Python opens of it work under the shim — not settled. iconvert is judged under `--observe supervised` (measured "
     f"table); rootrm there differs between two runs (a random UUID written into the file) | {R} |"),
    (f"| Qt's save through an unnamed temporary file | Kvantum 1.1.4 `kvantummanager --set`, Hydrogen 1.2.2 `h2cli -u` | "
     f"`unresolvable_path` at the gate: an unlinked-fd write, the `O_TMPFILE` Qt names afterwards | {R} |"),
    (f"| Unordered writer threads (Node 20) | yarn 4.18.1 `config set`, sindresorhus's trash-cli 7.2.0 `trash` | "
     f"`multiple_threads_detected` at the gate | {R} |"),
    (f"| Bytes that differ between two runs | softhsm2-util 2.6.1 `--import` (each object named by a random UUID) | "
     f"`--twice` differs at the gate | {R} |"),
    (f"| A script that refuses root, run through `setpriv` | arkenfox's prefsCleaner.sh 2.1 | `child_process_detected` "
     f"(an image replacement whose chain of observation broke) at the gate and under `--observe syscalls`; under "
     f"`--observe supervised` the second run of `--twice` ends differently, the restore not rebuilding owners (#678) | {R} |"),
]

doc = Path("docs/target-classes.md")
lines = doc.read_text().split("\n")
assert not any("2026-10-09-user-data-4" in l for l in lines), "already inserted"


def table_end(after_heading):
    i = next(n for n, l in enumerate(lines) if l.startswith(after_heading))
    j = i + 1
    while not lines[j].startswith("|"):
        j += 1
    while j < len(lines) and lines[j].startswith("|"):
        j += 1
    return j


for heading, new in (("## Refusals that are the correct answer", walls),
                     ("## Measured, with verdicts", verdicts)):
    j = table_end(heading)
    lines[j:j] = new
doc.write_text("\n".join(lines))
print(len(verdicts), "verdict rows,", len(walls), "wall rows")
