#!/usr/bin/env python3
"""Insert this run's rows into docs/target-classes.md: verdicts at the end of the measured table, walls
and roswell's page's-path refusal at the end of the refusals table. Run once from the repository root;
refuses if the run's path is already in the file. 2026-10-05's script, rewritten for this run's eighteen
and the five explored and then taken out of the slate. Every number is the engine's
(apparatus/verdicts.py, transcripts/verdicts.txt, the evidence bundles' consequence tables)."""
from pathlib import Path

R = "`spike/dogfood/2026-10-07-user-data-3/RESULTS.md`"
T = "truncating `open`"
SG = "static Go, `--observe supervised`"


def fail(cls, tool, worlds, cp, path, before, extra=""):
    return (f"| {cls} | {tool} | **FAIL** {worlds} explored worlds, crash point {cp} — the {T} "
            f"of `{path}` and the kill before its `write`: **0 bytes** ({before} before), the old bytes "
            f"nowhere. Replayed twice.{(' ' + extra) if extra else ''} | {R} |")


def ok(cls, tool, text):
    return f"| {cls} | {tool} | **PASS** {text} | {R} |"


OUT = "Out of this run's slate"
verdicts = [
    fail(f"Container client writing its remotes and aliases ({SG})", "LXD 6.9 client `lxc alias remove`",
         "1/3", "2 of 2", "config.yml", "118",
         "Opened empty, `lxc` carries on with its defaults and exits 0. Not filed: remotes and aliases a user adds again"),
    fail(f"Backup client writing its repository preferences ({SG})", "duplicacy 3.2.5 `set -no-backup`",
         "1/3", "2 of 2", "preferences", "360",
         "In its `.duplicacy` directory. Every later command refuses on the parse error. Not filed: `init` against the same storage, which holds every backup, restores it"),
    fail("Game-mod manager writing its profiles (static Rust, `--observe supervised`)",
         "ferium 4.7.1 `profile configure`", "1/4", "3 of 3", "config.json", "475",
         "ferium refuses on the parse error. Not filed: `ferium scan` rebuilds a profile's mod list from its directory"),
    fail("Single-file wiki updated over itself (Node)",
         "TiddlyWiki 5.4.1 `--load wiki.html … --render $:/core/save/all wiki.html`", "1/3", "2 of 2",
         "wiki.html", "2,552,578",
         "Loading the empty file builds an empty wiki, exit 0. Not filed: rendering over the loaded file is a "
         "forum recipe, not tiddlywiki.com's (its examples render to another file), and the forum already warns "
         "of the empty file with the render-elsewhere-then-rename workaround"),
    fail("MCP server manager editing a server (Python)", "mcpm 2.15.0 `edit`", "4/33", "29 of 32",
         "servers.json", "272",
         "The server definitions and their environment. Opened empty, each command prints the decode error and "
         "exits 0, and the next `new` writes a file holding only its own server. Not filed: keys a user re-issues"),
    (f"| Audio metadata written in place | libsndfile 1.2.2 (Debian) `sndfile-metadata-set --str-comment` | "
     f"**FAIL** 1/4 explored worlds, crash point 3 of 3 — the `LIST` chunk appended, then the kill before "
     f"the RIFF size is rewritten: `a.wav` holds neither its old nor its new bytes. Replayed twice. Not filed: "
     f"the samples are intact and `sndfile-info` and `sndfile-convert` read all 16,000 frames; only the RIFF "
     f"size is stale (32,036 for 32,072 bytes) | {R} |"),
    (f"| CAD drawing stripped in place (Python) | ezdxf 1.4.4 `strip` | **FAIL** 1/11 explored worlds, crash "
     f"point 9 of 10 — `drawing.ezdxf.tmp` written, `drawing.dxf` renamed to `drawing.bak`, and the kill "
     f"before the second rename: `drawing.dxf` gone, its old bytes whole in `drawing.bak` and the new in "
     f"`drawing.ezdxf.tmp`. Replayed twice. Not filed: nothing is lost that a rename does not restore | {R} |"),
    fail("Coding agent installing an extension (Node 22)", "pi 1.0.4 `install`", "1/9", "7 of 8",
         "settings.json", "52",
         "In pi's `agent` directory, and `settings.json.lock` left behind: every later `pi` command fails `Lock file is already being held` "
         "until the directory is removed. Not filed: settings; its `CONTRIBUTING.md` bars LLM-written issues"),
    fail("Task runner forgetting a task (JSON backend)", "doit 0.37.0 `forget`", "1/3", "2 of 2", "d.json", "414",
         "Every later command raises the decode error. Not filed: a cache the next run rebuilds"),
    fail("Commit-message helper installing its hook (Node)", "gitmoji-cli 9.7.0 `-i`", "1/3", "2 of 2",
         "prepare-commit-msg", "194",
         "The repository's hook. Not filed: a completed run replaces a hand-written hook as well"),
    fail("Site builder writing a global preference (Node 22)", "astro 7.3.6 `preferences disable --global`",
         "1/4", "3 of 3", "settings.json", "41", "Not filed: a setting, read back as none set"),
    fail("Lisp installer writing its config (`--observe supervised` asked for by name)",
         "roswell 26.02.116 `ros config set`", "1/3", "2 of 2", "config", "64",
         "The page's path ended at `unresolvable_path` (refusals table). Not filed: a setting"),
    ok("Terminal file manager installing its launcher (Rust)", "broot 1.61.0 `--install`",
       "23/23: the launcher's files written new (absent before, not judged) and `.bashrc` opened `O_APPEND` for one line"),
    ok("Archive edited by libzip (`--observe syscalls`, the next step)", "ziptool (libzip 1.11.4) `delete`",
       "6/6: `a.zip.<n>.part` created `O_EXCL` and renamed over `a.zip`"),
    ok("Package database marking a package held", "xbps 0.60.7 `xbps-pkgdb -m hold`",
       "6/6: `.plist<n>` created `O_EXCL` and renamed over `pkgdb-0.38.plist`"),
    ok(f"Terminal theme switcher ({SG})", "kitty 0.49.2 `kitten themes`",
       "11/11: `current-theme.conf` and `kitty.conf` each through `<name>.atomic-write-<n>` created `O_EXCL`, `fsync`ed and renamed"),
    ok("Terminal config migrator (`--observe syscalls`, the next step)", "alacritty 0.17.0 `migrate`",
       "9/9: `.tmp<n>` created `O_EXCL` and renamed over each file"),
    # Explored, then out of the slate (RESULTS.md says why for each).
    (f"| Directory-jump history (`--observe syscalls`, the next step) | zsh-z 2.0.1 `zshz --add` | **FAIL** 1/7 "
     f"explored worlds, crash point 5 of 6 — `.z.<pid>` written whole, then `.z` truncated and the kill "
     f"before the copy: `.z` empty, the new list whole in `.z.<pid>`. Replayed twice. {OUT} on rule 14: its "
     f"tracker's `#19` is why it copies in place | {R} |"),
    (f"| Certificate authority revoking a certificate (clock pinned) | OpenSSL 4.0.3 `openssl ca -revoke` | "
     f"**FAIL** 2/9 explored worlds, crash point 6 of 8 — `index.txt` renamed to `index.txt.old`, and the kill "
     f"before `index.txt.new` is renamed in: `index.txt` gone, its old bytes in `index.txt.old`. Replayed "
     f"twice. {OUT} on rule 14: its tracker's `#2867` | {R} |"),
    fail("Font table editor", "afdko 5.0.1 `sfntedit -a`", "1/3", "2 of 2", "f.ttf", "632",
         f"{OUT} on rule 14: its tracker's `#594` (open) names this write"),
    fail("ACME client writing its account settings (`--observe syscalls`, the next step)",
         "acme.sh 3.1.6 `--set-default-ca`", "3/5", "2 of 4", "account.conf", "201",
         f"{OUT} on rule 14: its tracker's `#7247` (open)"),
    (f"| Zip archive edited by minizip-ng | minizip-ng 4.2.2 `minizip -e` | **FAIL** 1/3 explored worlds, "
     f"crash point 2 of 2 — `a.zip` renamed to `a.zip.bak`, and the kill before the new archive is renamed in "
     f"from TMPDIR: `a.zip` gone, its old bytes in `a.zip.bak`. Replayed twice. {OUT} on rule 14: its "
     f"tracker's `#985` | {R} |"),
]

walls = [
    (f"| Static image starting a dynamic child (static C starting SBCL) | roswell 26.02.116 `ros config set` | "
     f"On the page's path, `unresolvable_path` (an operation whose path the trace closed), whose next step says "
     f"the target is refused by design. With `--observe supervised` named, **FAIL** 1/3 (measured table). "
     f"aliyun-cli met the same shape on 2026-10-05 under `oracle_missed_operation` (#685) | {R} |"),
    (f"| Unordered writer threads | rustic 0.11.4, prek 0.5.5, cspell 10.3.6 and capacitor 8.5.2 | "
     f"`multiple_threads_detected` at the gate | {R} |"),
    (f"| Bytes that differ between two runs | espsecure (esptool 5.4.0) `sign-data` (an ECDSA nonce), "
     f"plakar 1.1.7 `rm -apply` (the repository's encryption) | `--twice` differs at the gate | {R} |"),
    (f"| Other walls at the gate | goaccess 1.12 `--persist --restore`, libostree 2026.4 `remote add`, "
     f"easy-rsa 3.2.7 `revoke` | `unsupported_syscall_observed` (`mmap(PROT_WRITE\\|MAP_SHARED)`, #689); "
     f"`unresolvable_path`; `child_touched_state_dir`, then under `--observe syscalls` `recording_run_failed` "
     f"with the clock pinned (libfaketime's preload against the syscall trap) | {R} |"),
]

doc = Path("docs/target-classes.md")
lines = doc.read_text().split("\n")
assert not any("2026-10-07-user-data-3" in l for l in lines), "already inserted"


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
