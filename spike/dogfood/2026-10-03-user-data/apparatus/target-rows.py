#!/usr/bin/env python3
"""Insert this run's rows into docs/target-classes.md: verdicts at the end of the measured table,
walls at the end of the refusals table, DwarFS in the before-the-engine table. Run once from the
repository root; refuses if the run's path is already in the file."""
from pathlib import Path

R = "`spike/dogfood/2026-10-03-user-data/RESULTS.md`"
T = "truncating `open`"

def fail(cls, tool, worlds, cp, path, extra=""):
    return (f"| {cls} | {tool} | **FAIL** {worlds} explored worlds, crash point {cp} — the {T} "
            f"of `{path}` and the kill before its `write`: **0 bytes**, the old bytes nowhere. "
            f"Replayed twice.{(' ' + extra) if extra else ''} | {R} |")

verdicts = [
    fail("Notes CLI rewriting the notes that link to a moved note (static Go, `--observe supervised`)",
         "notesmd-cli 0.3.7 `move`", "2/6", "3 of 5", "daily/2026-10-01.md",
         "The emptied note is not the one moved. `ulimit -f 0` leaves the same 0 bytes (51 before). The gate refused `multiple_threads_detected` in 2 of 5 runs. "
         "Reported upstream as Yakitrak/notesmd-cli#137 <!-- upstream-report: Yakitrak/notesmd-cli#137 -->"),
    fail("GIS tool writing a shapefile over its input", "mapshaper 0.7.72 `-o force`", "5/11", "2 of 10", "a.shp",
         "`.shx` and `.dbf` stay old, so the layer no longer imports. `ulimit -f 0` gives the same (184 → 0). "
         "Reported upstream as mbloch/mapshaper#706 <!-- upstream-report: mbloch/mapshaper#706 -->"),
    fail("Cluster client rewriting its client-key config (static Go, `--observe supervised`)", "talosctl 1.14.2 `config context`",
         "1/3", "2 of 2", "config",
         "Every context's client key goes with it (3,086 → 0 under `ulimit -f 0`, then `error reading config: EOF`). Not filed: the tracker's bug template refuses AI-generated explanations"),
    fail("Shell saving structured data over a file", "nushell 0.116.0 `save -f`", "1/4", "3 of 3", "a.json",
         "Not put forward: nushell's `AGENTS.md` forbids an agent to create issues"),
    fail("Personal log appending an entry", "doing 2.1.124 `now`", "1/3", "2 of 2", "doing.md",
         "Not lost: doing copies the file to its backup directory before truncating it, so `doing undo` restores it"),
    fail("Editor writing buffers in filter mode", "kakoune 2026.05.21 `-f`", "2/5", "2 of 4", "a.txt",
         "`writemethod` defaults to `overwrite` and documents `replace` (a temporary and a rename) as the alternative"),
    fail("Cloud CLI switching context (static Go, `--observe supervised`)", "hcloud 1.69.0 `context use`", "1/3", "2 of 2", "cli.toml",
         "Not filed: tokens the user re-issues"),
    fail("kubeconfig context switcher (static Go, `--observe supervised`)", "kubectx 0.11.0", "6/9", "3 of 8", "config",
         "Here a `truncate` then the `write`. Not filed, for kubectl's reason (2026-09-28)"),
    fail("kubeconfig manager deleting a context (static Go, `--observe supervised`)", "kubecm 0.35.1 `delete`", "1/3", "2 of 2", "config",
         "Not filed, as kubectx"),
    fail("Package manager writing its config", "luarocks 3.13.0 `config`", "1/5", "4 of 4", "config-5.4.lua"),
    fail("Local-cluster CLI writing its config (static Go, `--observe supervised`)", "minikube 1.39.0 `config set`", "1/3", "2 of 2", "config.json",
         "The state root is `.minikube/config`: `logs/audit.json` gains a timestamped line per command"),
    fail("Kubernetes manifest editor (static Go, `--observe supervised`)", "kustomize 5.8.2 `edit set image`", "1/3", "2 of 2", "kustomization.yaml"),
    f"| Sequencing-file header rewritten in place | samtools 1.24 `reheader -i` | **PASS** 4/4 (3 crash points + the baseline): the header is one 302-byte `write` in an `O_RDWR` file, then `fdatasync` — nothing a process kill can split. A torn write is what it cannot survive, and was not measured | {R} |",
    f"| Translation catalogue updater | Babel 2.18.0 `pybabel update` | **PASS** 7/7: each `messages.po` written as `tmpmessages.po` and renamed | {R} |",
    f"| Torrent editor | transmission-edit 4.1.0~beta2 (Debian) `-a` | **PASS** 4/4: `.torrent.tmp.XXXXXX` created `O_EXCL`, renamed over the torrent | {R} |",
    f"| Perl in-place editing | perl 5.40.1 (Debian) `-i -pe` | **PASS** 7/7: each file written to a random name in its directory and renamed | {R} |",
    f"| Directory-jump database (Lua, clock pinned through `[define] apparatus`) | z.lua 1.8.26 `--add` | **PASS** 6/6: `zlua.db.<n>` written and renamed. Unpinned, `--twice` differs on `zlua.db` | {R} |",
    f"| Container CLI switching its default connection (`--observe syscalls`) | podman 5.4.2 (Debian) `system connection default` | **PASS** 7/7: a lock file, then `.tmp-podman-connections.json<n>` created `O_EXCL` and renamed. The default mode refused `oracle_missed_operation` | {R} |",
    f"| Compressor removing its input | bzip3 1.5.4 `-e --rm` | **PASS** 5/5: `a.log.bz3` written and `fsync`ed before `a.log` is unlinked | {R} |",
]

walls = [
    f"| Targets that check a permission bit in the state root | upx 5.2.1, argocd 3.5.3 | `recording_run_failed` at preflight: **restore does not reproduce permission bits**, so the second recorded run meets `0644` where the first met `0755` (upx: `file not executable`) or `0600` (argocd: `incorrect permission flags`). A probe with no target reproduces it (`apparatus/probes/modebit/`). The next step says \"Change the define\", which cannot fix it | {R} |",
    f"| Dotfile deployer with a varying call sequence (static Rust, `--observe supervised`) | dotter 0.13.5 `deploy -f` | `kill_did_not_land`, ccache's wall (8 worlds of 10 crash points) | {R} |",
    f"| Unordered writer threads | dotenvx 2.32.4, Electrum 4.8.2, bibtex-tidy 1.15.1, OpenTofu 1.13.1 and doctl 1.177.0 (both static, under supervised) | `multiple_threads_detected` at the gate | {R} |",
    f"| Bytes that differ between two runs | hexapdf 1.11.0 (clock pinned), mu 1.12.9 (its Xapian index) | `--twice` differs at the gate | {R} |",
    f"| Other walls at the gate | dotdrop 1.17.0, gocryptfs 2.6.1, flatpak 1.16.6 | `unsupported_syscall_observed` (`listxattr`); `child_process_detected` (`-passwd` takes the new password on stdin, so the operation was a script); `unresolvable_path` | {R} |",
]

before_engine = [
    f"| Image tool recompressing onto its own input | DwarFS 0.15.8 `mkdwarfs --recompress` | Not a crash: `mkdwarfs --recompress -f -i X -o X` truncates `X` (`open_output_binary`) before opening it as the input, and the image is gone in a plain run. Without `-f` it refuses. With another output it only writes a new file, which the built-in rule leaves unjudged. Reported upstream as mhx/dwarfs#388 <!-- upstream-report: mhx/dwarfs#388 --> | {R} |",
]

doc = Path("docs/target-classes.md")
lines = doc.read_text().split("\n")
assert not any("2026-10-03-user-data" in l for l in lines), "already inserted"

def table_end(after_heading):
    i = next(n for n, l in enumerate(lines) if l.startswith(after_heading))
    j = i + 1
    while not lines[j].startswith("|"):
        j += 1
    while j < len(lines) and lines[j].startswith("|"):
        j += 1
    return j

for heading, new in (("## Walls found before the engine ran", before_engine),
                     ("## Refusals that are the correct answer", walls),
                     ("## Measured, with verdicts", verdicts)):
    j = table_end(heading)
    lines[j:j] = new
doc.write_text("\n".join(lines))
print(len(verdicts), "verdict rows,", len(walls), "wall rows,", len(before_engine), "before-engine row")
