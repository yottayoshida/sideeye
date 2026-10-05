#!/usr/bin/env python3
"""Insert this run's rows into docs/target-classes.md: verdicts at the end of the measured table, walls
and the aliyun-cli refusal at the end of the refusals table. Run once from the repository root; refuses
if the run's path is already in the file. 2026-10-03's script, rewritten for this run's thirty and the
nine explored and then taken out of the slate. Every number is the engine's (apparatus/verdicts.py, the
evidence bundles' consequence tables)."""
from pathlib import Path

R = "`spike/dogfood/2026-10-05-user-data-2/RESULTS.md`"
T = "truncating `open`"
S = "static Go, `--observe supervised`"


def fail(cls, tool, worlds, cp, path, before, extra=""):
    return (f"| {cls} | {tool} | **FAIL** {worlds} explored worlds, crash point {cp} — the {T} "
            f"of `{path}` and the kill before its `write`: **0 bytes** ({before} before), the old bytes "
            f"nowhere. Replayed twice.{(' ' + extra) if extra else ''} | {R} |")


def ok(cls, tool, text):
    return f"| {cls} | {tool} | **PASS** {text} | {R} |"


OUT = "Out of this run's slate"
verdicts = [
    fail("CAD sketch saved by the command-line tool (`--observe syscalls`, the next step)",
         "SolveSpace 3.2 `solvespace-cli regenerate`", "15/17", "2 of 16", "part.slvs", "60,318",
         "With writes failing (`ulimit -f 0`) it prints `Written` and exits 0 on the empty file; in the GUI, "
         "that same success deletes the autosave (read in the source, not run). Reported upstream as "
         "solvespace/solvespace#1783 <!-- upstream-report: solvespace/solvespace#1783 -->"),
    (f"| Site configuration rewritten by its CLI | WP-CLI 2.12.0 `config set` | **FAIL** 1/4 explored worlds, "
     f"crash point 3 of 3 — `wp-config.php` opened without truncating, `ftruncate`d to 0, and the kill "
     f"before its `write` (`file_put_contents(..., LOCK_EX)` in wp-config-transformer): **0 bytes** (369 "
     f"before), the database credentials and salts nowhere. Replayed twice. With writes failing it reports "
     f"the error on the already-empty file. Reported upstream as wp-cli/config-command#233 "
     f"<!-- upstream-report: wp-cli/config-command#233 --> | {R} |"),
    (f"| Raster metadata edited in place | rasterio 1.5.2 `rio edit-info` | **FAIL** 3/6 explored worlds, "
     f"crash point 3 of 5 — the GeoTIFF rewritten in place by several `write`s and the kill between two: "
     f"`a.tif` holds neither its old nor its new bytes (20,260, the old length). Replayed twice. Not put "
     f"forward: whether a reader still opens the half-updated file was not measured | {R} |"),
    fail(f"Translation-file merger ({S})", "goi18n 2.6.1 `merge`", "2/5", "2 of 4", "active.ja.toml", "92",
         "Not filed: translation files live under version control"),
    fail("Molecular-graphics session saved over itself", "PyMOL 3.1.0 (Debian) `save` of a `.pse`", "1/3",
         "2 of 2", "model.pse", "6,078",
         "With writes failing it prints the `OSError` and exits 0. Reported upstream as "
         "schrodinger/pymol-open-source#520 <!-- upstream-report: schrodinger/pymol-open-source#520 -->"),
    fail("Rails translation-key tool", "i18n-tasks 1.1.2 `add-missing`", "2/5", "2 of 4", "en.yml", "44",
         "Not filed: under version control"),
    fail("Settings library writing its secrets file", "dynaconf 3.3.5 `write toml -s`", "1/3", "2 of 2",
         ".secrets.toml", "84", "Not filed: secrets the user re-issues"),
    fail(f"Payments CLI writing its profiles ({S})", "stripe-cli 1.53.0 `config --set`", "1/6", "4 of 5",
         "config.toml", "260",
         "Not filed: API keys the user re-issues. A rule-14 veto on its tracker's `#1109` was taken from the "
         "title and withdrawn from the body"),
    fail(f"Version manager writing its constraint ({S})", "tenv 4.15.1 `tf constraint`", "1/3", "2 of 2",
         "constraint", "7", "In tenv's `Terraform` directory. Not filed: a setting"),
    fail("3D-asset optimiser writing over its input", "gltfpack (meshoptimizer v1.3) `-i x -o x`", "1/3",
         "2 of 2", "terrain.glb", "3,788",
         "With writes failing, `Error saving` and exit 4. Not filed: meshoptimizer's `CONTRIBUTING.md` closes "
         "AI-generated issues and may ban repeat submitters"),
    fail("Edge-platform CLI writing its telemetry choice (Node, clock pinned)", "wrangler 4.147.0 `telemetry disable`",
         "1/4", "3 of 3", "metrics.json", "86", "Not filed: a setting"),
    fail("ML-platform CLI writing its key file", "kaggle 2.2.4 `config set`", "1/3", "2 of 2", "kaggle.json", "62",
         "The username and API key. Not filed: a key the user re-issues"),
    fail(f"Backup client writing its config ({S})", "velero 1.18.4 `client config set`", "1/3", "2 of 2",
         "config.json", "66", "Not filed: a setting"),
    fail(f"Container-runtime client writing its config ({S})", "crictl 1.37.0 `config --set`", "1/3", "2 of 2",
         "crictl.yaml", "136", "Not filed: a setting. Its tracker's `#605` (comments dropped) is not this write"),
    fail("Multi-repository git helper renaming a repository", "gita 0.16.8.2 `rename`", "2/7", "3 of 6",
         "repos.csv", "30", "Not filed: a registry `gita add` rebuilds"),
    fail(f"Kubernetes AI assistant removing a backend ({S})", "k8sgpt 0.4.39 `auth remove`", "1/4", "2 of 3",
         "k8sgpt.yaml", "546", "Every AI backend's key. Not filed: keys the user re-issues"),
    fail(f"Cluster bootstrapper migrating its config onto itself ({S})", "kubeadm 1.37.1 `config migrate`",
         "1/3", "2 of 2", "kubeadm.yaml", "1,179",
         "Not filed: a config kept beside the cluster, usually under version control"),
    fail("Shell plugin manager adding a plugin (static Rust, `--observe supervised`)", "sheldon 0.8.5 `add`",
         "1/3", "2 of 2", "plugins.toml", "69", "`config.to_path` → `fs::write`. Not filed: a dotfile"),
    fail("Monorepo build tool writing its telemetry choice (static Rust, `--observe supervised`)",
         "turbo 2.11.7 `telemetry disable`", "1/3", "2 of 2", "telemetry.json", "224", "Not filed: a setting"),
    fail("ML-tracking CLI switching to offline", "wandb 0.30.0 `offline`", "1/5", "4 of 4", "settings", "64",
         "Not filed: a setting"),
    fail("Embedded-build tool writing its settings (clock pinned)", "PlatformIO 6.2.0 `settings set`", "1/5",
         "3 of 4", "appstate.json", "181", "Not filed: a setting"),
    fail(f"Toolchain writing its environment file ({S})", "go 1.27.1 `env -w`", "1/3", "2 of 2", "env", "112",
         "The `GOENV` file holding GOPROXY, GOPRIVATE and GOFLAGS; telemetry turned off in the seed. Not filed: a "
         "setting rewritten in a line"),
    ok(f"Model-driven deployment client removing a credential ({S})", "juju 3.6.29 `remove-credential --client`",
       "5/5: `credentials.yaml<n>` created `O_EXCL`, `fsync`ed, renamed"),
    ok("Multi-call binary editing in place", "toybox 0.8.14 `sed -i`",
       "10/10 (9 crash points): each file written to a random name in its directory and renamed"),
    ok("Video downloader recording what it fetched", "yt-dlp 2026.8.19 `--download-archive`",
       "3/3: the archive opened `O_APPEND` and one line written"),
    ok("C/C++ package manager disabling a remote", "conan 2.33.0 `remote disable`",
       "5/5: `remotes.json.tmp` written and renamed"),
    ok("Container-image tool logging out (`--observe syscalls`, the next step)", "skopeo 1.18.0 (Debian) `logout`",
       "5/5: `.tmp-auth.json<n>` created `O_EXCL`, `fdatasync`ed, renamed"),
    ok(f"Registry client writing its host settings ({S})", "regctl 0.11.6 `registry set`",
       "6/6: `config.json<n>` created `O_EXCL` and renamed"),
    ok(f"containerd CLI logging out ({S})", "nerdctl 2.4.1 `logout`",
       "4/4: `config.json<n>` created `O_EXCL` and renamed (docker/cli's `configfile`)"),
    ok(f"OCI-artifact client logging out ({S})", "oras 1.3.4 `logout`",
       "4/4: `oras_credstore_temp_<n>` created `O_EXCL` and renamed"),
    # Explored, then out of the slate (RESULTS.md says why for each).
    fail("Subtitle synchroniser writing over its input", "ffsubsync 0.5.1 `--overwrite-input`", "1/3", "2 of 2",
         "movie.srt", "2,500",
         f"With writes failing, an `OSError` and exit 0. {OUT}: a cohort-4 candidate already. Reported upstream "
         "as smacke/ffsubsync#240 <!-- upstream-report: smacke/ffsubsync#240 -->"),
    fail("Python package manager removing a stored credential", "uv 0.12.23 `auth logout`", "1/6", "5 of 5",
         "credentials.toml", "218", f"{OUT}: the 2026-09-05 selection had met uv"),
    fail("Model-hub CLI logging out", "huggingface_hub 2.1.1 `hf auth logout`", "1/8", "7 of 7", "stored_tokens",
         "109", f"{OUT} on rule 14: its tracker's `#5013` is this write"),
    (f"| NTFS volume label rewritten in place (`--observe syscalls`, the next step) | ntfs-3g 2022.10.3 (Debian) "
     f"`ntfslabel` | **FAIL** 1/5 explored worlds, crash point 3 of 4 — the volume image written in place and "
     f"the kill between two `write`s: neither its old nor its new bytes. Replayed twice. {OUT} on rule 14: its "
     f"tracker's `#104` | {R} |"),
    fail("Cloud CLI writing its config (clock pinned)", "azure-cli 2.90.0 `config set`", "3/25", "22 of 24",
         "config", "96", f"{OUT} on rule 14: its tracker's `#34060` (open)"),
    ok("OCaml package manager setting an option (static, `--observe supervised`)", "opam 2.6.0 `option`",
       f"6/6: `opam-atomic<n>.tmp` created `O_EXCL` and renamed over `config`. {OUT} on rule 14: its tracker's `#5489`"),
    ok("Julia version manager writing its config (static Rust, `--observe supervised`)", "juliaup 1.22.7 `config`",
       f"59/59: `.tmp<n>` created `O_EXCL` and renamed over `juliaup.json`. {OUT} on rule 14: its tracker's `#1295`"),
    ok("Environment-file editor", "python-dotenv 1.2.4 `set`",
       f"4/4: `.tmp_<n>` created `O_EXCL` and renamed over `.env`. {OUT} on rule 14: its tracker's `#713` (no `fsync` before the rename)"),
    ok("Secrets scanner writing its config", "ggshield 1.55.0 `config set`",
       f"6/6 — **of a file the operation does not write**: the judged path was the seeded `.gitguardian.yaml`; "
       f"`config set` wrote `auth_config.yaml`, absent before, with a {T}, and a path that did not exist is "
       f"not judged by the built-in rule. A define error, not a verdict on the write. {OUT} on rule 14"),
]

walls = [
    (f"| Static image starting a dynamic child (static Go) | aliyun-cli 3.5.1 `configure delete` | On the "
     f"page's path, `oracle_missed_operation`, whose next step names `--observe syscalls`, which refuses with no "
     f"mode named: the static `aliyun` runs `/usr/bin/uname` three times, the dynamic child loads the shim and "
     f"leaves its marker, and the parent's writes are the operations it did not see. With `--observe supervised` "
     f"named, **PASS** 7/7 (`.config.json.tmp-<n>` created `O_EXCL`, `fsync`ed, renamed). lefthook met the same "
     f"shape on v1.7.0 (2026-10-02) | {R} |"),
    (f"| Unordered writer threads | basic-memory 0.23.2, gemini-cli 0.62.0, glTF-Transform 4.5.1, lingui 6.9.0, "
     f"steamguard-cli 0.18.4, vercel 62.2.0 and codex 0.160.0 (static, under supervised) | "
     f"`multiple_threads_detected` at the gate | {R} |"),
    (f"| Bytes that differ between two runs | monero-wallet-cli 0.18.5.1 (clock pinned; the wallet file), "
     f"infracost 0.10.46 (static, under supervised; `.state.json`), xmake 3.1.1 (`xmake.conf`, its table order) "
     f"| `--twice` differs at the gate | {R} |"),
    (f"| Other walls at the gate | firewalld 2.3.1 (Debian) `firewall-offline-cmd`, astropy 8.0.1 `fitscheck -w`, "
     f"Home Assistant 2026.9.4 `--script auth`, firebase-tools 15.32.1 `experiments:disable` | "
     f"`unsupported_syscall_observed` (`listxattr`; `mmap(PROT_WRITE\\|MAP_SHARED)`); `unresolvable_path` (an "
     f"operation whose path the trace closed); `child_touched_state_dir` (a child makes configstore's directory) "
     f"| {R} |"),
]

doc = Path("docs/target-classes.md")
lines = doc.read_text().split("\n")
assert not any("2026-10-05-user-data-2" in l for l in lines), "already inserted"


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
