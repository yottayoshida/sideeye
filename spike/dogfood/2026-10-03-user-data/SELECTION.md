# Selection — 2026-10-03 user-data

The owner's question for this run: **continue dogfooding in four rounds of five, the targets
chosen by the rules, none at a project this repository has already reported to, and anything
headed upstream only if it is critical, discussed first.** This file is the selection for all
four rounds; they share one screen, one box and one apparatus, so they are one run directory
with one `RESULTS.md` split by round, and one `RUNS.md` row.

The rules are `spike/cohort4/SCOUT-BRIEF.md`'s 1–17 plus this directory's ordering rule and entry
gate (`../README.md`). The owner's instruction was to choose by the rules, which this file reads
as the sign-off of `PREP.md` §9 step 5 given in advance; the slate below was not shown again before
the explores.

## What "critical" changed in the choice

Every report this project has had declined or called low-value rewrote data git can give back
(pyupgrade, poetry, fonttools — `feedback`: "the target, not the form, decided it"). So rule 5
("stores primary data locally that users do not want to lose") was read strictly: the screen went
after tools whose state is a wallet, a spreadsheet, notes, a mail folder, a sequencing file, a
shapefile, a torrent, a credentials file, and **not formatters**. Formatters are the class every
earlier run found most FAILs in, and the class whose FAILs were least worth filing.

## The exclusion set, declared before the candidates

- `apparatus/fresh.sh` — 2026-09-28's copy with `mine` pointed at this run's prefix, and a selftest
  case added: 2026-09-28's own target (`kubectl`) must now read **seen**. Green before the screen.
- Every `owner/repo` in `spike/upstream-reports.tsv` (28) and Artifex (mutool, drafted on
  2026-10-02 for its Bugzilla): not a target, so not a place a second report could go.

## The screen

| pass | names | fresh | seen | transcript |
|---|---|---|---|---|
| 1 — personal data stores, media, sync, dedupe | 52 | 17 | 35 | `transcripts/fresh-screen-1.txt` |
| 2 — the same classes, wider | 48 | 38 | 10 | `transcripts/fresh-screen-2.txt` |
| 3 — spreadsheets, wallets, genomics, editors | 33 | 22 | 11 | `transcripts/fresh-screen-3.txt` |
| 4 — GIS, notebooks, secrets files, parity | 19 | 13 | 6 | `transcripts/fresh-screen-4.txt` |
| 5 — archives, encrypted folders | 9 | 7 | 2 | `transcripts/fresh-screen-5.txt` |
| 6 — infrastructure state and credentials | 14 | 14 | 0 | `transcripts/fresh-screen-6.txt` |
| 7 — credential configs, torrents, translations | 17 | 15 | 2 | `transcripts/fresh-screen-7.txt` |

190 names as written — 189 ignoring case, and a few pairs (talos/talosctl, tofu/opentofu,
dwarfs/mkdwarfs) are one tool under two names. The match is `fresh.sh`'s, deliberately loose (a short name such as `nb`, `f2`
or `sd` reads seen from any ledger line that contains it), and a false seen costs a candidate.

Rules 1 and 2 (≥1,000 stars, a push since 2026-04-03), by `gh api repos/<r>`
(`transcripts/stars.txt`), and rule 11 by `apparatus/rule11.sh` (`transcripts/receipts/rule11-*.txt`).

### Rule 11, read twice — the correction

The first reading took rule 11 as "a project reply within seven days to most of the last ten bug
reports" and rejected on it. That is stricter than this repository's precedent: 2026-09-28 admitted
sqruff at 3 of 10 and phpcbf at 4 of 9. Midway through the screen the bar was moved to the
precedent — **at least three of the last ten bug reports answered by the project within seven days**
— and everything rejected under the first reading was re-read under the second. Admitted by the
change: Electrum (3/10), transmission (4/10), hcloud (3/10), doctl (3/10), argocd (4/10), Babel
(4/10), luarocks (4/10), bibtex-tidy (4/10). Still out: organize 1, czkawka 0, image_optim 0 of 1,
imgp 1, patchelf 0, brotli 0 of 2, hstr 2, util-linux 2 of 6, nbconvert 2, nimble 2, ejson 1,
step 1, skaffold 1, terraform-docs 1, conda 2, nvm 2, cheat 0, pulumi 0.

### Out before the box, each with its reason

| name | rule | measurement |
|---|---|---|
| AtomicParsley, brename, rnr, rsgain, tageditor, osync (997), pubs, harsh, totp-cli, caesium, lrzip, ambr, bartib, squashfs-tools (931), loudgain, mp3gain, puddletag, cpdf-source, scaleway-cli (999), mail-deduplicate, tuckr, trashy | 1 | stars below 1,000 |
| phockup, elodie, rcm, rip, jpeg-archive, scour, passage, csvq, taskbook, trentm/json, duperemove | 2 | last push before 2026-04-03 |
| klog | 11 | issues disabled |
| jdupes | — | moved off GitHub (404) |
| dnote | 7 | SQLite is the store |
| obsidian-export | 15 | writes a new tree; nothing that exists before the operation changes |
| rdfind | 14 | `pauldreik/rdfind#104` (open): "make atomic the links replacement" — the `-makehardlinks` shape |
| visidata | 14 | `saulpw/visidata#1009` "save: atomic file save", closed not planned |
| comby, fastmod | 2 | releases 2022 and 2023; recent pushes are maintenance — and both rewrite source |
| electrum, organize, imgp (first box) | 11 | out under the first reading; Electrum came back under the second |

## The box

`apparatus/Dockerfile`, built by `apparatus/build.sh`: Debian trixie, linux/arm64, Sideeye
**v1.7.0 installed by the page's installer** (`install-sideeye.sh v1.7.0`, digest matched). C and
C++ candidates were **built from their latest upstream release** (rdfind 1.8.0, hstr 3.2,
samtools 1.24, bzip3 1.5.4, sc-im 0.8.5, brotli 1.2.0, kakoune 2026.05.21, snapraid 14.10,
luarocks 3.13.0), because trixie lags most of them and a FAIL on a packaged build is void if upstream
has moved. From Debian, named as such: mu 1.12.9 (upstream 1.14.3), util-linux 2.41.5, flatpak
1.16.6 (1.18.4), podman 5.4.2 (6.1.3), transmission-cli 4.1.0~beta2 (4.1.3), perl 5.40.1 (5.44.0).
Everything else from its release asset, PyPI, npm or RubyGems at a pinned version
(`transcripts/build.txt`, `build-add-*.txt`; the tools' own version lines are in the box's
`/versions.txt`, printed there).

Two failed builds are kept: `build-first.txt` (Electrum's `electrum_ecc` wheel failed to compile and
took the whole pip step with it; it later installed with `ELECTRUM_ECC_DONT_COMPILE=1` against
Debian's libsecp256k1) and `build-second.txt` (the version-printing step hung for over an hour: a
probe's grandchild held the pipe to `head`; the step now writes to a file).

## Plain runs, then the entry gate

Each operation ran once plainly from its seed first (`apparatus/plain.sh`,
`transcripts/plain-runs.txt`). The gate is `apparatus/entry.sh`, 2026-10-02's copy unchanged but for
the box name, run through `apparatus/gate-all.sh` so a define's `env.sh` is exported where the engine
starts. Its legs were not re-run: the script is byte-identical to the one whose legs 2026-09-28 saw
red (`../2026-09-28-shipped-v170/transcripts/entry-legs.txt`).

Defines are written by one file, `apparatus/gen-defines.py`. A statically linked image is named by
path (`/opt/bin/<tool>`), the spelling under which v1.7.0's default-mode `no_shim_marker` names
`--observe supervised` and `run.sh` follows it (2026-09-28, RESULTS revision 1). Two defines carry a
clock pin, libfaketime through `/etc/ld.so.preload` with `[define] apparatus` saying so
(`docs/apparatus.md`), each in a box of its own.

| candidate | version | language | gate | why |
|---|---|---|---|---|
| perl `-i -pe` | 5.40.1 (Debian) | Perl | 0 | 6 operations |
| kakoune `-f` | 2026.05.21 | C++ | 0 | 4 |
| samtools `reheader -i` | 1.24 | C | 0 | 3 |
| bzip3 `-e --rm` | 1.5.4 | C | 0 | 4 |
| mapshaper `-o force` | 0.7.72 | JS | 0 | 10 |
| nushell `save -f` | 0.116.0 | Rust | 0 | 3 |
| doing `now` | 2.1.124 | Ruby | 0 | 2 |
| z.lua `--add` (clock pinned) | 1.8.26 | Lua | 0 | 5; unpinned, `--twice` differs on `zlua.db` |
| Babel `pybabel update` | 2.18.0 | Python | 0 | 6 |
| transmission-edit `-a` | 4.1.0~beta2 (Debian) | C++ | 0 | 3 |
| luarocks `config` | 3.13.0 | Lua | 0 | 4 |
| podman `system connection default` | 5.4.2 (Debian) | Go | 0 FOLLOW | `oracle_missed_operation`, the next step names `--observe syscalls` |
| notesmd-cli `move` | 0.3.7 | Go, static | 0 SUPERVISED | 5 operations; **refused `multiple_threads_detected` in 2 of 5 gate runs** (`transcripts/entry-notesmd-repeat.txt`) — tombi's shape on 2026-10-02 |
| kubectx | 0.11.0 | Go, static | 0 SUPERVISED | 8 |
| kustomize `edit set image` | 5.8.2 | Go, static | 0 SUPERVISED | 2 |
| dotter `deploy -f` | 0.13.5 | Rust, static (musl) | 0 SUPERVISED | 10 |
| hcloud `context use` | 1.69.0 | Go, static | 0 SUPERVISED | 2 |
| kubecm `delete` | 0.35.1 | Go, static | 0 SUPERVISED | 2 |
| minikube `config set` | 1.39.0 | Go, static | 0 SUPERVISED | 2, after the state root was narrowed to `.minikube/config` (`logs/audit.json` gains a timestamped line per command) |
| talosctl `config context` | 1.14.2 | Go, static | 0 SUPERVISED | 2 |
| hexapdf `modify` | 1.11.0 | Ruby | **1** | `--twice` differs on `a.pdf` with the clock pinned too; what else varies was not measured |
| mu `move` | 1.12.9 (Debian) | C++ | **1** | the index (Xapian) differs between runs; kept outside the state root, the second recorded run failed instead (the index already said "moved") |
| dotdrop `install -f` | 1.17.0 | Python | **1** | `unsupported_syscall_observed` (`listxattr`) |
| dotenvx `encrypt` | 2.32.4 | JS | **1** | `multiple_threads_detected` on `.env.keys` |
| OpenTofu `state rm` | 1.13.1 | Go, static | **1** | `multiple_threads_detected` under supervised |
| Electrum `setlabel` | 4.8.2 | Python | **1** | `multiple_threads_detected` |
| doctl `auth switch` | 1.177.0 | Go, static | **1** | `multiple_threads_detected` under supervised |
| bibtex-tidy `--modify` | 1.15.1 | JS | **1** | `multiple_threads_detected` |
| gocryptfs `-passwd` | 2.6.1 | Go, static | **1** | `child_process_detected` (new password read from stdin, so the operation is a two-line script that `exec`s it) |
| flatpak `override` | 1.16.6 (Debian) | C | **1** | `unresolvable_path` |
| upx | 5.2.1 | C++, static | **DEFINE, unfixable** | `recording_run_failed`: restore reset `prog` to `0644` and upx refuses a non-executable |
| argocd `context` | 3.5.3 | Go, static | **DEFINE, unfixable** | `recording_run_failed`: restore reset the `0600` config to `0644` and argocd refuses it |

upx and argocd are the same Sideeye limit, shown by a probe with no target in it
(`apparatus/probes/modebit/`, `transcripts/probe-modebit.txt`): a `0755` script inside the state
root is `0644` after the first restore, and the second recorded run cannot exec it. preflight's next
step says "Change the define", and nothing in a define can change it. Filed on this repository's own
tracker (`RESULTS.md`).

Candidates that never reached the gate, for a reason found by running them:

| name | why |
|---|---|
| sc-im 0.8.5 | needs a terminal (`No such device or address`); under `script` it exits 0, and `--output=a.sc a.sc` — the only non-interactive write — **emptied the spreadsheet**: it exports before evaluation. No non-interactive save; rule 8 |
| snapraid 14.10 | refuses data and parity on one device (`-D` is not accepted by `sync`); the box has one filesystem |
| scooter 0.9.1 | `--no-tui` with `-s/-r` replaced nothing in two tries |
| DwarFS 0.15.8 | `mkdwarfs --recompress -i X -o X -f` truncates `X` before reading it and destroys the image in a plain run, no crash involved (`transcripts/probe-dwarfs-same-path.txt`). With another output path the operation only writes a new file, which the built-in rule leaves unjudged. Reported upstream (`RESULTS.md`) |

## The receipts (rules 11 and 14)

Rule 11 per candidate: `transcripts/receipts/rule11-bug-reports.txt` and `rule11-any-label.txt`.

The novelty pre-scan (`spike/cohort4/novelty-prescan.sh`) ran on every tracker of the slate,
controls green in each. **The order did not hold for two targets.** The first 21 trackers ran one at
a time (01:51–03:26Z). The later ones were started as two parallel loops, which exhausted the search
rate limit: six of the slate's transcripts broke (`BROKEN`; the broken ones are kept as
`*.prescan.txt.rate-limited`) and were re-run one at a time, 04:19–04:51Z. doctl's and argocd's scans
were stopped before they started: both had left at the gate by then. kubectx's and podman's explores ran at 04:03Z,
**before** their first clean pre-scan (started 04:41Z and 04:45Z, finished 04:45Z and 04:51Z by the
loop's own log). Neither scan hit the operation's write
shape, so the veto would not have fired; the order is recorded because rule 14 asks for it, not
because it changed an outcome.

Vetoes: rdfind and visidata (above). No other scan holds a report of an interrupted rewrite of the
file these operations write.

## The slate — four rounds of five

Ordered by coverage, not by expected yield (rule 14's last paragraph): the eight Go targets spread
two per round so no round is single-language (rule 13).

| round | targets |
|---|---|
| 1 | samtools (C), doing (Ruby), mapshaper (JS), hcloud (Go), talosctl (Go) |
| 2 | kakoune (C++), nushell (Rust), Babel (Python), notesmd-cli (Go), kubectx (Go) |
| 3 | transmission-edit (C++), perl (Perl), z.lua (Lua), kubecm (Go), podman (Go) |
| 4 | bzip3 (C), dotter (Rust), luarocks (Lua), minikube (Go), kustomize (Go) |

No checkers: the built-in atomicity rule judges, as on 2026-10-02.
