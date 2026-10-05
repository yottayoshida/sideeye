#!/usr/bin/env python3
"""Append this run's rows to the funnel, its campaign line, the upstream ledger, and the B2 exclusions
with their aliases. 2026-10-03's script rewritten for this run; the B2 half is new here (2026-10-03
added those lines by hand).

The Debian package names are not from memory: each was looked up in trixie's archive by package name
and by the file that ships the command (transcripts/debian-packages.txt).

Run once from the repository root; it refuses if the campaign already has rows, so a second run
cannot double them.
"""
import sys
from pathlib import Path

C = "dogfood/2026-10-05-user-data-2"
D = "spike/dogfood/2026-10-05-user-data-2"
E = f"{D}/transcripts/explore"
G = f"{D}/transcripts/entry-out/entry"
P = f"{D}/transcripts/receipts"
DAY = "2026-10-05"
NW = "not_worth"

rows = [
    # target, stage, verdict, stop, report, evidence, as_of, note
    ("solvespace", "filed", "fail", "awaiting", "solvespace/solvespace#1783", f"{E}/solvespace/syscalls.json", DAY, "FAIL 15/17 under --observe syscalls (the next step): solvespace-cli regenerate truncates part.slvs before its first write; with writes failing it prints Written and exits 0, and in the GUI that success deletes the autosave (read in the source)"),
    ("wp-cli", "filed", "fail", "awaiting", "wp-cli/config-command#233", f"{E}/wp-cli/explore.json", DAY, "FAIL 1/4: wp config set opens wp-config.php, ftruncates it and is killed before the write (file_put_contents with LOCK_EX in wp-config-transformer): 369 -> 0 bytes, the site's database credentials and salts gone"),
    ("rasterio", "judged", "fail", "-", "-", f"{E}/rasterio/explore.json", "-", "FAIL 3/6: rio edit-info rewrites the GeoTIFF in place in several writes; killed between two it is neither old nor new. Not put forward: whether a reader still opens it was not measured"),
    ("goi18n", "judged", "fail", NW, "-", f"{E}/goi18n/supervised.json", "-", "FAIL 2/5 under supervised: merge truncates active.ja.toml before its write; translation files live under version control"),
    ("juju", "judged", "pass", "-", "-", f"{E}/juju/supervised.json", "-", "PASS 5/5 under supervised: credentials.yaml<n> created O_EXCL, fsynced and renamed"),
    ("pymol", "filed", "fail", "awaiting", "schrodinger/pymol-open-source#520", f"{E}/pymol/explore.json", DAY, "FAIL 1/3: save truncates the existing .pse before its one write; with writes failing it prints the OSError and exits 0 (Debian 3.1.0, upstream's latest tag)"),
    ("i18n-tasks", "judged", "fail", NW, "-", f"{E}/i18n-tasks/explore.json", "-", "FAIL 2/5: add-missing truncates en.yml before its write; under version control"),
    ("dynaconf", "judged", "fail", NW, "-", f"{E}/dynaconf/explore.json", "-", "FAIL 1/3: write toml -s truncates .secrets.toml before its write; secrets the user re-issues"),
    ("stripe-cli", "judged", "fail", NW, "-", f"{E}/stripe/supervised.json", "-", "FAIL 1/6 under supervised: config --set truncates config.toml (API keys per profile); keys the user re-issues"),
    ("tenv", "judged", "fail", NW, "-", f"{E}/tenv/supervised.json", "-", "FAIL 1/3 under supervised: tf constraint truncates Terraform/constraint; a setting"),
    ("gltfpack", "report_worthy", "fail", "-", "-", f"{E}/gltfpack/explore.json", "-", "FAIL 1/3: -i x -o x truncates terrain.glb before its write (3788 -> 0). Not filed: meshoptimizer's CONTRIBUTING.md closes AI-generated issues and may ban repeat submitters"),
    ("wrangler", "judged", "fail", NW, "-", f"{E}/wrangler/explore.json", "-", "FAIL 1/4 with the clock pinned: telemetry disable truncates metrics.json; a setting"),
    ("kaggle", "judged", "fail", NW, "-", f"{E}/kaggle/explore.json", "-", "FAIL 1/3: config set truncates kaggle.json (username and API key); a key the user re-issues"),
    ("velero", "judged", "fail", NW, "-", f"{E}/velero/supervised.json", "-", "FAIL 1/3 under supervised: client config set truncates config.json; a setting"),
    ("crictl", "judged", "fail", NW, "-", f"{E}/crictl/supervised.json", "-", "FAIL 1/3 under supervised: config --set truncates crictl.yaml; a setting"),
    ("toybox", "judged", "pass", "-", "-", f"{E}/toybox/explore.json", "-", "PASS 10/10: sed -i writes each file to a random name in its directory and renames it"),
    ("go", "judged", "fail", NW, "-", f"{E}/go/supervised.json", "-", "FAIL 1/3 under supervised (v1.8.0's next step for a static image named bare): go env -w truncates the GOENV file before its write (112 -> 0); a setting. go1.27.1 from go.dev, telemetry off in the seed. In uv's place"),
    ("gita", "judged", "fail", NW, "-", f"{E}/gita/explore.json", "-", "FAIL 2/7: rename truncates repos.csv before its write; a registry gita add rebuilds"),
    ("k8sgpt", "judged", "fail", NW, "-", f"{E}/k8sgpt/supervised.json", "-", "FAIL 1/4 under supervised: auth remove truncates k8sgpt.yaml (every AI backend's key); keys the user re-issues"),
    ("kubeadm", "judged", "fail", NW, "-", f"{E}/kubeadm/supervised.json", "-", "FAIL 1/3 under supervised: config migrate onto its input truncates kubeadm.yaml; kept beside the cluster, usually under version control"),
    ("sheldon", "judged", "fail", NW, "-", f"{E}/sheldon/supervised.json", "-", "FAIL 1/3 under supervised: add truncates plugins.toml (config.to_path -> fs::write); a dotfile"),
    ("yt-dlp", "judged", "pass", "-", "-", f"{E}/yt-dlp/explore.json", "-", "PASS 3/3: the download archive opened O_APPEND and one line written"),
    ("conan", "judged", "pass", "-", "-", f"{E}/conan/explore.json", "-", "PASS 5/5: remotes.json.tmp written and renamed"),
    ("skopeo", "judged", "pass", "-", "-", f"{E}/skopeo/syscalls.json", "-", "PASS 5/5 under --observe syscalls (the next step): .tmp-auth.json<n> created O_EXCL, fdatasynced and renamed (Debian 1.18.0)"),
    ("regctl", "judged", "pass", "-", "-", f"{E}/regctl/supervised.json", "-", "PASS 6/6 under supervised: config.json<n> created O_EXCL and renamed"),
    ("turbo", "judged", "fail", NW, "-", f"{E}/turbo/supervised.json", "-", "FAIL 1/3 under supervised: telemetry disable truncates telemetry.json; a setting. Its tracker's scan finished after the explore and found no veto"),
    ("wandb", "judged", "fail", NW, "-", f"{E}/wandb/explore.json", "-", "FAIL 1/5: offline truncates the settings file; a setting"),
    ("platformio", "judged", "fail", NW, "-", f"{E}/platformio/explore.json", "-", "FAIL 1/5 with the clock pinned: settings set truncates appstate.json; a setting"),
    ("nerdctl", "judged", "pass", "-", "-", f"{E}/nerdctl/supervised.json", "-", "PASS 4/4 under supervised: config.json<n> created O_EXCL and renamed (docker/cli's configfile)"),
    ("oras", "judged", "pass", "-", "-", f"{E}/oras/supervised.json", "-", "PASS 4/4 under supervised: oras_credstore_temp_<n> created O_EXCL and renamed"),
    # Explored, then out of the slate.
    ("ffsubsync", "filed", "fail", "awaiting", "smacke/ffsubsync#240", f"{E}/ffsubsync/explore.json", DAY, "FAIL 1/3: --overwrite-input truncates the subtitle before its write; with writes failing, an OSError and exit 0. Out of the slate: a cohort-4 candidate already (CANDIDATES-REJECTED.md, rule 5); filed on the owner's choice made before that was found"),
    ("uv", "judged", "fail", NW, "-", f"{E}/uv/explore.json", "-", "FAIL 1/6: auth logout truncates credentials.toml; credentials the user re-issues. Out of the slate: the 2026-09-05 selection had met uv, and this run screened it as uv-cli"),
    ("huggingface_hub", "judged", "fail", "known", "-", f"{E}/hf/explore.json", "-", "FAIL 1/8: hf auth logout truncates stored_tokens. Rule 14: huggingface/huggingface_hub#5013 reported this write; its fix (#5021) changed the encoding only"),
    ("ntfs-3g", "judged", "fail", "known", "-", f"{E}/ntfslabel/syscalls.json", "-", "FAIL 1/5 under --observe syscalls (the next step): ntfslabel writes the volume in place; killed between two writes it is neither old nor new. Rule 14: tuxera/ntfs-3g#104"),
    ("opam", "judged", "pass", "-", "-", f"{E}/opam/supervised.json", "-", "PASS 6/6 under supervised: opam-atomic<n>.tmp created O_EXCL and renamed over config. Out of the slate on rule 14: ocaml/opam#4157, fixed by #5489"),
    ("juliaup", "judged", "pass", "-", "-", f"{E}/juliaup/supervised.json", "-", "PASS 59/59 under supervised: .tmp<n> created O_EXCL and renamed over juliaup.json. Out of the slate on rule 14: JuliaLang/juliaup#1221, fixed by #1295"),
    ("python-dotenv", "judged", "pass", "-", "-", f"{E}/dotenv/explore.json", "-", "PASS 4/4: .tmp_<n> created O_EXCL and renamed over .env. Out of the slate on rule 14: theskumar/python-dotenv#713 (no fsync before the rename)"),
    ("azure-cli", "judged", "fail", "known", "-", f"{E}/azure-cli/explore.json", "-", "FAIL 3/25 with the clock pinned: config set truncates config. Rule 14: Azure/azure-cli#34060 (open) rewrites _session.py's 'w' writes"),
    ("ggshield", "judged", "pass", "-", "-", f"{E}/ggshield/explore.json", "-", "PASS 6/6 of the wrong file: the judged path was the seeded .gitguardian.yaml; config set wrote auth_config.yaml, absent before, with a truncating open, and a new path is not judged. A define error. Out of the slate on rule 14: GitGuardian/ggshield#1243 (open)"),
    ("aliyun-cli", "judged", "pass", "-", "-", f"{E}/aliyun/supervised.json", "-", "PASS 7/7 under --observe supervised asked for by name: .config.json.tmp-<n> created O_EXCL, fsynced, renamed. The page's path ended at oracle_missed_operation, then syscalls refused with no mode named: the static parent runs uname, a dynamic child that leaves the shim's marker. Out of the slate on rule 14: aliyun/aliyun-cli#1387"),
    # Vetoed on rule 14 before their explores.
    ("dokuwiki", "attempted", "-", "known", "-", f"{P}/dokuwiki_dokuwiki.prescan.txt", "-", "Cleared the gate; vetoed before its explore: #677 pages saved empty on a full disk, #1303 users.auth.php replaced by a zero-byte file, fixed by write-new-then-rename"),
    ("lighthouse", "attempted", "-", "known", "-", f"{P}/sigp_lighthouse.prescan.txt", "-", "Cleared the gate; vetoed before its explore: #2338 (closing #2159) writes validator_definitions.yml through a temporary file and a rename"),
    ("jump", "attempted", "-", "known", "-", f"{P}/gsamokovarov_jump.prescan.txt", "-", "Cleared the gate; vetoed before its explore: #9 scores.json malformed on a full disk, #10 atomic writes to fix it"),
    # Walls at the gate.
    ("basic-memory", "attempted", "unknown", "wall", "-", f"{G}/basic-memory.preflight.txt", "-", "multiple_threads_detected at the gate"),
    ("codex", "attempted", "unknown", "wall", "-", f"{G}/codex.preflight.txt", "-", "multiple_threads_detected at the gate, under supervised (static Rust)"),
    ("gemini", "attempted", "unknown", "wall", "-", f"{G}/gemini.preflight.txt", "-", "gemini-cli 0.62.0: multiple_threads_detected at the gate"),
    ("gltf-transform", "attempted", "unknown", "wall", "-", f"{G}/gltf-transform.preflight.txt", "-", "multiple_threads_detected at the gate"),
    ("lingui", "attempted", "unknown", "wall", "-", f"{G}/lingui.preflight.txt", "-", "multiple_threads_detected at the gate"),
    ("steamguard", "attempted", "unknown", "wall", "-", f"{G}/steamguard.preflight.txt", "-", "steamguard-cli 0.18.4: multiple_threads_detected at the gate"),
    ("vercel", "attempted", "unknown", "wall", "-", f"{G}/vercel.preflight.txt", "-", "multiple_threads_detected at the gate"),
    ("monero", "attempted", "unknown", "wall", "-", f"{G}/monero.preflight.txt", "-", "monero-wallet-cli: --twice differs on the wallet file w, with the clock pinned"),
    ("infracost", "attempted", "unknown", "wall", "-", f"{G}/infracost.preflight.txt", "-", "--twice differs on .state.json, under supervised (static Go)"),
    ("xmake", "attempted", "unknown", "wall", "-", f"{G}/xmake.preflight.txt", "-", "--twice differs on xmake.conf: its tables are written in a varying order"),
    ("firewalld", "attempted", "unknown", "wall", "-", f"{G}/firewalld.preflight.txt", "-", "unsupported_syscall_observed (listxattr), firewall-offline-cmd from Debian 2.3.1"),
    ("fitscheck", "attempted", "unknown", "wall", "-", f"{G}/fitscheck.preflight.txt", "-", "astropy 8.0.1: unsupported_syscall_observed (mmap with PROT_WRITE and MAP_SHARED)"),
    ("homeassistant", "attempted", "unknown", "wall", "-", f"{G}/homeassistant.preflight.txt", "-", "unresolvable_path: an operation whose path the trace closed"),
    ("firebase", "attempted", "unknown", "wall", "-", f"{G}/firebase.preflight.txt", "-", "firebase-tools 15.32.1: child_touched_state_dir, a child makes configstore's directory"),
]

reports = [
    ("solvespace/solvespace", "1783", "standing", "SolveSpace 3.2 `solvespace-cli regenerate`"),
    ("schrodinger/pymol-open-source", "520", "standing", "PyMOL 3.1.0 (Debian) `save` of a `.pse`"),
    ("smacke/ffsubsync", "240", "standing", "ffsubsync 0.5.1 `--overwrite-input`"),
    ("wp-cli/config-command", "233", "standing", "WP-CLI 2.12.0 `config set`"),
]

# Names in the two ledgers above that are not themselves a trixie package, mapped to the packages that
# ship them (`-` where trixie has none, which then needs no B2 line of its own beyond the name).
aliases = [
    ("SolveSpace 3.2 `solvespace-cli regenerate`", "solvespace", "upstream-reports.tsv"),
    ("PyMOL 3.1.0 (Debian) `save` of a `.pse`", "pymol;python3-pymol", "upstream-reports.tsv"),
    ("ffsubsync 0.5.1 `--overwrite-input`", "-", "upstream-reports.tsv"),
    ("WP-CLI 2.12.0 `config set`", "-", "upstream-reports.tsv"),
    ("dynaconf", "python3-dynaconf", "outcome-funnel.tsv"),
    ("python-dotenv", "python3-dotenv", "outcome-funnel.tsv"),
    ("fitscheck", "astropy-utils;python3-astropy", "outcome-funnel.tsv"),
    ("go", "golang-go", "outcome-funnel.tsv (upstream's go1.27.1 measured; trixie ships 1.24)"),
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

screened = len({l.split()[1] for p in sorted((root / D / "transcripts").glob("fresh-screen-*.txt"))
                for l in p.read_text().splitlines() if l.startswith(("fresh ", "SEEN "))})
camp = root / "spike/outcome-funnel-campaigns.tsv"
with camp.open("a") as f:
    f.write("\t".join([C, DAY, "full", str(screened), f"{D}/RESULTS.md"]) + "\n")

up = root / "spike/upstream-reports.tsv"
with up.open("a") as f:
    for line in reports:
        f.write("\t".join(line) + "\n")

# B2: every funnel name that is a package or has no package, and every package an alias names.
why = f"measured ({D})"
b2 = root / "spike/unknown-rate/b2-exclusions.txt"
lines = b2.read_text().split("\n")
head = [l for l in lines if l.startswith("#")]
body = {l.split("\t")[0]: l for l in lines if l and not l.startswith("#")}
want = [t for t, *_ in rows if t not in aliased]
want += [p for _, ps, _ in aliases for p in ps.split(";") if p != "-"]
want += ["python3-rasterio", "python3-azure-cli"]  # libraries beside a package the row's name already is
added = upgraded = 0
for n in want:
    if n not in body:
        body[n] = f"{n}\t{why}"; added += 1
    elif not body[n].split("\t")[1].startswith("measured"):
        body[n] = f"{n}\t{why}"; upgraded += 1   # uv: `read (dogfood selection)` before this run measured it
b2.write_text("\n".join(head + [body[k] for k in sorted(body)]) + "\n")

al = root / "spike/unknown-rate/b2-exclusion-aliases.tsv"
with al.open("a") as f:
    for line in aliases:
        f.write("\t".join(line) + "\n")

print(len(rows), "funnel rows, 1 campaign (", screened, "names screened ),", len(reports), "reports,",
      added, "B2 lines added,", upgraded, "upgraded,", len(aliases), "aliases")
