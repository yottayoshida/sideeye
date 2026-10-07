# Results — 2026-10-07 user-data-3

Eighteen targets in four waves (`SELECTION.md`: the owner asked for five in each of four, the screen ran
out first, and the owner ruled to close at eighteen with the rules unchanged), each explored by
`apparatus/run.sh` in a box of its own with **the released v1.9.0** (`apparatus/explore.sh`; engine lines
in `transcripts/explore/<t>/engine.txt`). Default mode first; where the refusal's next step named
`--observe supervised` or `--observe syscalls`, it was followed once. Every FAIL was replayed twice (both
FAIL) and its evidence bundle written. No checkers: the built-in atomicity rule judges.
`transcripts/verdicts.txt` is `apparatus/verdicts.py`'s reading of the engine's own JSON.

**11 FAIL, 5 PASS, 2 UNKNOWN on the page's path** (roswell: FAIL with `--observe supervised` named).
Nine of the FAILs are one shape — the rewritten file opened truncating and the kill before its write: the
file at 0 bytes, the old bytes nowhere. ezdxf rotates through a `.bak` (killed between its two renames, the
file is gone and its old bytes whole beside it); libsndfile edits the WAV in place in two writes (killed
between, a stale RIFF size over intact samples). Four of the five PASSes write a temporary file created
`O_EXCL` and rename it; broot writes new files and appends one line.

**Nothing was filed upstream.** The bar is 2026-09-07's: a report goes out only for data the user cannot
get back, from the tool's own documented command. No FAIL here meets it. Most lose a setting or a key the
user re-issues (2026-10-05's precedent for `config set`-shaped writes); ezdxf and libsndfile lose nothing
a rename or any reader does not restore; ferium's mod lists come back with `ferium scan`; duplicacy's
storage holds every backup. The one FAIL that loses what a user cannot re-type — TiddlyWiki's whole wiki —
comes from rendering over the loaded file, a forum recipe rather than tiddlywiki.com's (its examples
render to another file), and the same forum thread already warns of the empty file and gives the
workaround (`talk.tiddlywiki.org/t/3482`, 2022). Five more FAILs were already known to their trackers
(rule 14) and left the slate.

## Wave 1

| target | verdict | where | report |
|---|---|---|---|
| LXD 6.9 client `lxc alias remove` | **FAIL** 1/3, crash point 2 of 2 (supervised) | the client's `config.yml` truncated: 118 → 0 bytes. Opened empty, `lxc` shows its default remotes and no aliases, exit 0 (`lab-10.txt`) | not filed: remotes and aliases a user adds again |
| duplicacy 3.2.5 `set -no-backup` | **FAIL** 1/3, crash point 2 of 2 (supervised) | `.duplicacy/preferences` truncated: 360 → 0. Every later command refuses: `Failed to parse the preference file`, exit 100 | not filed: `init` against the same storage restores it; the backups are in the storage |
| ferium 4.7.1 `profile configure` | **FAIL** 1/4, crash point 3 of 3 (supervised) | `config.json` truncated: 475 → 0. ferium refuses on the parse error and writes nothing over it | not filed: `ferium scan` rebuilds a profile's mod list from its directory |
| easy-rsa 3.2.7 `revoke` | **UNKNOWN** — `child_touched_state_dir` by default; `--observe syscalls` (the next step) `recording_run_failed` with the clock pinned, `baseline_violates_invariant` without | openssl, sed and mv write the PKI. Pinned, libfaketime's preload met the syscall trap and the children died of `SIGSYS`; unpinned, each run stamps its own times | — |
| TiddlyWiki 5.4.1 `--load wiki.html … --render $:/core/save/all wiki.html` | **FAIL** 1/3, crash point 2 of 2 | the single-file wiki truncated: 2,552,578 → 0 bytes. Loading the empty file builds an empty wiki, exit 0 | not filed: above. v1.9.0 warned on the define (below) |

## Wave 2

| target | verdict | where | report |
|---|---|---|---|
| broot 1.61.0 `--install` | **PASS** 23/23 | its launcher files written new (absent before, not judged); `.bashrc` opened `O_APPEND` for one line | — |
| ziptool (libzip 1.11.4) `delete` | **PASS** 6/6 (`--observe syscalls`, the next step) | `a.zip.<n>.part` created `O_EXCL`, renamed over `a.zip` | — |
| xbps 0.60.7 `xbps-pkgdb -m hold` | **PASS** 6/6 | `.plist<n>` created `O_EXCL`, renamed over `pkgdb-0.38.plist` | — |
| mcpm 2.15.0 `edit` | **FAIL** 4/33, crash point 29 of 32 | `servers.json` truncated: 272 → 0. Opened empty, each command prints the decode error and exits 0; the next `new` writes a file holding only its own server | not filed: server definitions and keys a user re-issues |
| libsndfile 1.2.2 `sndfile-metadata-set --str-comment` | **FAIL** 1/4, crash point 3 of 3 | the `LIST` chunk appended, then the kill before the RIFF size is rewritten: neither old nor new | not filed: killed at each crash point by the report's own reproduce line, the samples are intact and `sndfile-info` and `sndfile-convert` read all 16,000 frames (`lab-12.txt`) |

## Wave 3

| target | verdict | where | report |
|---|---|---|---|
| ezdxf 1.4.4 `strip` | **FAIL** 1/11, crash point 9 of 10 | `drawing.ezdxf.tmp` written, `drawing.dxf` renamed to `drawing.bak`, the kill before the second rename: `drawing.dxf` gone, old bytes whole in `drawing.bak`, new in `drawing.ezdxf.tmp` | not filed: a rename restores it |
| pi 1.0.4 `install` (Node 22) | **FAIL** 1/9, crash point 7 of 8 | `agent/settings.json` truncated: 52 → 0, and `settings.json.lock` left behind: every later `pi` command fails `Lock file is already being held` until the directory is removed | not filed: settings; pi's `CONTRIBUTING.md` also bars LLM-written issue text |
| doit 0.37.0 `forget` (JSON backend) | **FAIL** 1/3, crash point 2 of 2 | the dependency file truncated: 414 → 0. Every later command raises the JSON decode error, exit 3 | not filed: a cache the next run rebuilds |
| kitty 0.49.2 `kitten themes` | **PASS** 11/11 (supervised) | `current-theme.conf` and `kitty.conf` each through `<name>.atomic-write-<n>` created `O_EXCL`, `fsync`ed, renamed | — |
| alacritty 0.17.0 `migrate` | **PASS** 9/9 (`--observe syscalls`, the next step) | `.tmp<n>` created `O_EXCL`, renamed over each file | — |

## Wave 4

| target | verdict | where | report |
|---|---|---|---|
| gitmoji-cli 9.7.0 `-i` | **FAIL** 1/3, crash point 2 of 2 | `.git/hooks/prepare-commit-msg` truncated: 194 → 0 | not filed: a completed run replaces a hand-written hook as well (`lab-9.txt`), so the crash loses nothing the run would not |
| astro 7.3.6 `preferences disable --global` (Node 22) | **FAIL** 1/4, crash point 3 of 3 | `settings.json` truncated: 41 → 0, read back as no preferences set | not filed: a setting |
| roswell 26.02.116 `ros config set` | **UNKNOWN** `unresolvable_path` on the page's path, whose next step says the target is refused by design; **FAIL** 1/3, crash point 2 of 2 with `--observe supervised` named (`transcripts/explore/roswell/probe-supervised.txt`) | `config` truncated: 64 → 0 | not filed: a setting |

## Explored, then out of the slate (rule 14)

| target | verdict | the tracker's text |
|---|---|---|
| zsh-z 2.0.1 `zshz --add` | **FAIL** 1/7, crash point 5 of 6 (`--observe syscalls`) — `.z.<pid>` written whole, `.z` truncated, the kill before the copy: `.z` empty, the new list whole in `.z.<pid>` | `#19`: `.z` is copied in place so a symlink survives |
| OpenSSL 4.0.3 `openssl ca -revoke` (clock pinned) | **FAIL** 2/9, crash point 6 of 8 — `index.txt` renamed to `.old`, the kill before `index.txt.new` is renamed in | `#2867` CA file rotation is not atomic |
| afdko 5.0.1 `sfntedit -a` | **FAIL** 1/3, crash point 2 of 2 — `f.ttf` truncated: 632 → 0 | `#594` (open) names sfntedit's temporary-file write |
| acme.sh 3.1.6 `--set-default-ca` | **FAIL** 3/5, crash point 2 of 4 (`--observe syscalls`) — `account.conf` truncated: 201 → 0 | `#7247` (open), the same writer on a full disk |
| minizip-ng 4.2.2 `minizip -e` | **FAIL** 1/3, crash point 2 of 2 — `a.zip` renamed to `.bak`, the kill before the new archive is renamed in | `#985` placed that temporary file |

## Walls at the gate

`multiple_threads_detected`: rustic 0.11.4, prek 0.5.5, cspell 10.3.6, capacitor 8.5.2. `--twice` differs:
espsecure (an ECDSA nonce in every signature), plakar 1.1.7 (its encryption). `unsupported_syscall_observed`:
goaccess 1.12 (a write through `mmap(PROT_WRITE|MAP_SHARED)`, #689). `unresolvable_path`: libostree 2026.4.
Cleared the gate and left before an explore: git-lfs (every write a `git config` child) and keyring (the
bytes are keyrings.alt's, 29 stars).

## What the run says about Sideeye v1.9.0

- **A static parent with a dynamic child is turned away under a second refusal.** roswell's `ros` is static
  and starts a dynamic SBCL. On the page's path it ends at `unresolvable_path`, whose next step says the
  target is refused by design — yet `--observe supervised`, named by hand, judges it. #685 (open) records
  the same shape under `oracle_missed_operation` (aliyun-cli, 2026-10-05). A fix keyed on that one refusal
  would still send roswell away.
- **#706's warning met a word a shell does not expand.** TiddlyWiki's `$:/core/save/all` was warned as "a
  word beginning `$` … nothing expands it". The sentence is true and changes no verdict, but a shell passes
  `$:` as written too: the word-initial `$` counts whatever follows it, where the mid-word `$` counts only
  before a name character, `{` or `(` (ADR 0095).
- **A target's unterminated line glues onto the verdict.** goaccess's progress line ends without a newline,
  so preflight's `UNKNOWN` began mid-line and `apparatus/entry.sh`'s `^UNKNOWN` read the gate row's reason
  as blank. The verdict itself was right.
- **The release installer and every next step that was followed worked as printed**: v1.9.0 installed from
  the CI quickstart's `install-sideeye.sh` with its digest checked; four static images reached a verdict
  through the supervised next step, and four dynamic ones through the syscalls next step (two of them out of
  the slate).

## Screening, and what it cost

Five scouts, about 1,100 names by their own counts, about 790 of them already met in an earlier ledger; the run's own
transcripts (`fresh-screen-1.txt`, `word-recheck-*.txt`) carry the names it re-checked itself, which is the
number the campaign line records. 33 defines reached the gate (openssl twice, before and after the clock was
pinned). The box was built thirteen times
(`transcripts/build-*.txt`); Node 22 went in for four targets that refuse trixie's Node 20.
