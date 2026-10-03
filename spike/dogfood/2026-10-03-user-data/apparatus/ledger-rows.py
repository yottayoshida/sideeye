#!/usr/bin/env python3
"""Append this run's rows to the funnel, its campaign line, and the upstream ledger.

Run once from the repository root; it refuses if the campaign already has rows, so a second run
cannot double them.
"""
import sys
from pathlib import Path

C = "dogfood/2026-10-03-user-data"
D = "spike/dogfood/2026-10-03-user-data"
E = f"{D}/transcripts/explore"
G = f"{D}/transcripts/entry-out/entry"
DAY = "2026-10-03"

rows = [
    # target, stage, verdict, stop, report, evidence, as_of, note
    ("samtools", "judged", "pass", "-", "-", f"{E}/samtools/explore.json", "-", "PASS 4/4: reheader -i is one 302-byte write over the header in an O_RDWR file, then fdatasync; a torn write was not measured"),
    ("doing", "judged", "fail", "no_content_lost", "-", f"{E}/doing/explore.json", "-", "FAIL 1/3: doing.md truncated before its write; doing copies it to its backup directory first, so `doing undo` restores it"),
    ("mapshaper", "filed", "fail", "awaiting", "mbloch/mapshaper#706", f"{E}/mapshaper/explore.json", DAY, "FAIL 5/11: -o force truncates a.shp before its write, leaving .shx/.dbf old and the layer unreadable; ulimit -f 0 reproduces it"),
    ("hcloud", "judged", "fail", "not_worth", "-", f"{E}/hcloud/supervised.json", "-", "FAIL 1/3 under supervised: cli.toml truncated; API tokens the user re-issues - 2026-09-28's kubectl reason"),
    ("talosctl", "report_worthy", "fail", "-", "-", f"{E}/talosctl/supervised.json", "-", "FAIL 1/3 under supervised: the talosconfig (client keys for every context) emptied, 3086 -> 0 bytes under ulimit -f 0. Not filed: the tracker's bug template refuses AI-generated explanations, and the owner chose not to file rather than write it themselves"),
    ("kakoune", "judged", "fail", "not_worth", "-", f"{E}/kakoune/explore.json", "-", "FAIL 2/5: writemethod defaults to overwrite and documents replace as the alternative; files usually under version control"),
    ("nushell", "judged", "fail", "-", "-", f"{E}/nushell/explore.json", "-", "FAIL 1/4: save -f truncates before its write (53 -> 0 under ulimit -f 0). Not put forward: nushell's AGENTS.md forbids an agent to create issues"),
    ("babel", "judged", "pass", "-", "-", f"{E}/babel/explore.json", "-", "PASS 7/7: each catalogue written to tmpmessages.po and renamed"),
    ("notesmd-cli", "filed", "fail", "awaiting", "Yakitrak/notesmd-cli#137", f"{E}/notesmd/supervised.json", DAY, "FAIL 2/6 under supervised: move rewrites every linking note with os.WriteFile; a linking note left at 0 bytes. Gate refused multiple_threads_detected in 2 of 5 runs"),
    ("kubectx", "judged", "fail", "not_worth", "-", f"{E}/kubectx/supervised.json", "-", "FAIL 6/9 under supervised: truncate(kubeconfig) then write; 2026-09-28's kubectl reason. Its novelty pre-scan finished after the explore"),
    ("transmission-edit", "judged", "pass", "-", "-", f"{E}/transmission/explore.json", "-", "PASS 4/4: a .tmp.XXXXXX file created O_EXCL and renamed over the torrent (Debian 4.1.0~beta2)"),
    ("perl", "judged", "pass", "-", "-", f"{E}/perl/explore.json", "-", "PASS 7/7: perl -i writes a random name in the same directory and renames it (Debian 5.40.1)"),
    ("z.lua", "judged", "pass", "-", "-", f"{E}/zlua/explore.json", "-", "PASS 6/6 with the clock pinned: zlua.db.<n> written and renamed"),
    ("kubecm", "judged", "fail", "not_worth", "-", f"{E}/kubecm/supervised.json", "-", "FAIL 1/3 under supervised: the kubeconfig truncated before its write; as kubectx"),
    ("podman", "judged", "pass", "-", "-", f"{E}/podman/syscalls.json", "-", "PASS 7/7 under --observe syscalls: a lock file, then .tmp-podman-connections.json<n> O_EXCL and a rename (Debian 5.4.2). Its novelty pre-scan finished after the explore"),
    ("bzip3", "judged", "pass", "-", "-", f"{E}/bzip3/explore.json", "-", "PASS 5/5: a.log.bz3 written and fsynced, then a.log unlinked"),
    ("dotter", "explored", "unknown", "wall", "-", f"{E}/dotter/supervised.json", "-", "kill_did_not_land under supervised: the call sequence varied between worlds"),
    ("luarocks", "judged", "fail", "not_worth", "-", f"{E}/luarocks/explore.json", "-", "FAIL 1/5: config-5.4.lua truncated before its write; a settings file"),
    ("minikube", "judged", "fail", "not_worth", "-", f"{E}/minikube/supervised.json", "-", "FAIL 1/3 under supervised: config.json truncated before its write; a settings file"),
    ("kustomize", "judged", "fail", "not_worth", "-", f"{E}/kustomize/supervised.json", "-", "FAIL 1/3 under supervised: kustomization.yaml truncated; under version control"),
    ("hexapdf", "attempted", "unknown", "wall", "-", f"{G}/hexapdf.preflight.txt", "-", "--twice: a.pdf differs, with the clock pinned too"),
    ("mu", "attempted", "unknown", "wall", "-", f"{G}/mu.preflight.txt", "-", "--twice: the Xapian index differs; kept outside the state root the second recorded run failed instead"),
    ("dotdrop", "attempted", "unknown", "wall", "-", f"{G}/dotdrop.preflight.txt", "-", "unsupported_syscall_observed (listxattr)"),
    ("dotenvx", "attempted", "unknown", "wall", "-", f"{G}/dotenvx.preflight.txt", "-", "multiple_threads_detected on .env.keys"),
    ("opentofu", "attempted", "unknown", "wall", "-", f"{G}/tofu.preflight.txt", "-", "multiple_threads_detected under supervised (state rm)"),
    ("electrum", "attempted", "unknown", "wall", "-", f"{G}/electrum.preflight.txt", "-", "multiple_threads_detected (setlabel, --offline)"),
    ("doctl", "attempted", "unknown", "wall", "-", f"{G}/doctl.preflight.txt", "-", "multiple_threads_detected under supervised (auth switch)"),
    ("bibtex-tidy", "attempted", "unknown", "wall", "-", f"{G}/bibtex-tidy.preflight.txt", "-", "multiple_threads_detected (Node)"),
    ("gocryptfs", "attempted", "unknown", "wall", "-", f"{G}/gocryptfs.preflight.txt", "-", "child_process_detected: -passwd reads the new password from stdin, so the operation was a script that execs it"),
    ("flatpak", "attempted", "unknown", "wall", "-", f"{G}/flatpak.preflight.txt", "-", "unresolvable_path (override --user, Debian 1.16.6)"),
    ("upx", "attempted", "unknown", "wall", "-", f"{G}/upx.preflight.txt", "-", "recording_run_failed: restore resets permission bits, and upx refuses the 0644 copy; a Sideeye limit, not the target's"),
    ("argocd", "attempted", "unknown", "wall", "-", f"{G}/argocd.preflight.txt", "-", "recording_run_failed: restore turns the 0600 config 0644 and argocd refuses it; the same Sideeye limit as upx"),
    ("dwarfs", "filed", "-", "awaiting", "mhx/dwarfs#388", f"{D}/transcripts/probe-dwarfs-same-path.txt", DAY, "Not an engine verdict: mkdwarfs --recompress -f onto its own input truncates it before reading, in a plain run"),
]

root = Path(".")
funnel = root / "spike/outcome-funnel.tsv"
text = funnel.read_text()
if f"\n{C}\t" in text:
    sys.exit("rows for this campaign already exist")
for r in rows:
    assert all(f for f in r) and not any("\t" in f for f in r), r
with funnel.open("a") as f:
    for t, *rest in rows:
        f.write("\t".join([C, t, *rest]) + "\n")

camp = root / "spike/outcome-funnel-campaigns.tsv"
with camp.open("a") as f:
    f.write("\t".join([C, DAY, "full", "190", f"{D}/RESULTS.md"]) + "\n")

up = root / "spike/upstream-reports.tsv"
with up.open("a") as f:
    for line in (("Yakitrak/notesmd-cli", "137", "standing", "notesmd-cli 0.3.7 `move`"),
                 ("mbloch/mapshaper", "706", "standing", "mapshaper 0.7.72 `-o force`"),
                 ("mhx/dwarfs", "388", "standing", "DwarFS 0.15.8 `mkdwarfs --recompress`")):
        f.write("\t".join(line) + "\n")
print(len(rows), "funnel rows, 1 campaign, 3 reports")
