# Results — 2026-10-09 follow-ups 2

The second "おわり？" of the day. The first recount (`2026-10-09-followups`) had narrowed itself twice: it
read only the upstream reports that had a reply or a close, and it set aside the targets whose two clean
runs differ as "only a checker over a scratch path can judge them" — the thing it had just done for Home
Assistant. This round measured both. Released **v1.10.0**, installed by the page's installer, in one box
(`apparatus/Dockerfile`, built four times: `transcripts/build*.txt`). `PREDICTIONS.md` was committed before
each run (`0330693`, `c1da8af`, `ea9d390`, `1192b2a`).

**Six upstream fix PRs measured, each beside the build its report was measured on: four hold, two do
not.** **Fifteen targets no campaign had judged, each taken one or more next steps further: twelve
reached a verdict (5 PASS, 7 FAIL), three stay behind a wall.** Two of the FAILs were filed upstream
(softhsm/SoftHSMv2#908, ocrmypdf/OCRmyPDF#1762) and one PR comment was posted (Exiv2/exiv2#9504), each
with the owner's approval of the full text.

## Upstream fix PRs

Found by reading every one of the 36 standing reports' timelines (`spike/upstream-report-status.sh` and
the GitHub timeline API), not only the ones with a reply: eight had a PR, six were measured.

| report | control (the build the report measured) | the PR's head | what the PR does |
|---|---|---|---|
| SubtitleEdit/subtitleedit#15829 | SeConv 5.2.0 **FAIL** 1/4 | #15833 `99f440ebf8` (the maintainer's) **PASS** 5/5 | a temporary beside the subtitle, `Flush(true)`, `File.Move(overwrite: true)` |
| aws/aws-cli#10648 | Debian's awscli 2.23.6 **FAIL** 1/3 | #10649 `c7999845b3` **PASS** 4/4 | `mkstemp(dir=…)`, `os.replace` |
| beancount/beancount#1051 | Debian's beancount 3.1.0 **FAIL** 1/3 | #1054 `cc591f7fcf` **PASS** 6/6 | `NamedTemporaryFile(dir=…)`, `fsync`, `os.replace` |
| helm/helm#32709 | helm v4.3.0 **FAIL** 1/5 (supervised) | #32716 `09cda512f9` **PASS** 6/6 (syscalls, the next step) | `fileutil.AtomicWriteFile` |
| Exiv2/exiv2#9482 | Debian's exiv2 0.28.5 **FAIL** 3/7, the picture truncated | #9504 `8e2fc85ae2` **FAIL** 3/16, crash point 4 of 15: `pic1.jpg` unlinked and the kill before the temporary is renamed in — the picture absent, its new bytes whole in `pic1.jpg.exv-tmp-<pid>-<n>` | on everything but Windows, `fs::remove(pf)` then `fs::rename(newPath, pf)`. Reproduced without Sideeye (`lab-2.txt`); **commented on the PR** with the reproduction and the direction (drop the remove: POSIX `rename(2)` replaces in one step) |
| solvespace/solvespace#1783 | v3.2 **FAIL** 15/17 (syscalls) | #1784 `a3b470a591` (Copilot's) **FAIL** 15/17, the same window | it reports a failed `fclose`; the file is still opened truncating first |

Not measured, with the reason: terraform #39303 (its last code commit is the build 2026-10-02 measured;
the commit after it moves a changelog file), andreafrancia/trash-cli #428 (the listing side only — "trash-put
is not touched", its own words) and #416 (closed unmerged).

## The fifteen

Eleven had been refused because two clean runs leave different bytes. `sideeye preflight --twice` (the
refusal's next step; with `--oracle` where a child process needs it) named where (`transcripts/twice.txt`,
`twice-oracle.txt`), and each define now declares those paths scratch and judges them with a checker that
reads the data through the tool itself. Four had other refusals, each followed a step further.

| target | what the define does now | result |
|---|---|---|
| mu 1.12.9 `move` | `home` (the Xapian index) scratch; checker: message 1001 in exactly one folder, whole | **PASS** 24/24 |
| monero-wallet-cli 0.18.5.1 `set_description` | `w` (the cache, encrypted afresh) scratch; checker opens the wallet | **PASS** 6/6 |
| git 2.47.3 `commit` | `-c gc.auto=0 -c maintenance.auto=false` (the detached gc child was the refusal); `.git/index` and `.git/COMMIT_EDITMSG` scratch; dates pinned; checker `git fsck`, HEAD, the work tree | **PASS** 39/39. The form without `COMMIT_EDITMSG` FAILed on that file alone, which `docs/cli.md` names among the paths nobody depends on |
| firebase-tools 15.32.1 `experiments:disable` | `NO_UPDATE_NOTIFIER=1` (the notifier was the child) | **PASS** 11/11 — not the threads wall predicted |
| gocryptfs 2.6.1 `-passwd` (through `sh`) | `--observe supervised` named; `cipher/gocryptfs.conf` scratch (a fresh scrypt salt); checker: the old or new passphrase unwraps the same master key (`gocryptfs-xray`) | **PASS** 5/5 |
| **SoftHSM 2.6.1 `softhsm2-util --import`** | state one level up and `tokens` scratch (every name a fresh UUID); checker `pkcs11-tool --list-objects` | **FAIL** 106/283, earliest crash point 6 of 282 — `token.object` truncated and the kill before its write: the token gone from its slot and the key already in it unreachable. Reproduced without Sideeye (`lab-4.txt`, `lab-6.txt`); **filed: softhsm/SoftHSMv2#908** |
| **OCRmyPDF 16.7.0 `--force-ocr a.pdf a.pdf`** | `a.pdf` scratch (its checker kept) | **FAIL** 1/3 — `a.pdf` opened `w+b` and the kill before the copy: 0 bytes. The cookbook's "Modify a file in place" says the file will only be overwritten if OCRmyPDF is successful; `main` writes the same way. Reproduced without Sideeye (`lab-5.txt`, `lab-6.txt`); **filed: ocrmypdf/OCRmyPDF#1762** |
| hexapdf 1.11.0 `-f modify -i 1-2 a.pdf a.pdf` | `a.pdf` scratch; checker `hexapdf info` (2 or 3 pages) | **FAIL** 5/13 — `a.pdf` at 0 bytes. Not filed: in place only when `-f` lets the output name the input (otiotool's reading, 2026-10-09 user-data-4) |
| xmake 3.1.1 `g --theme=plain` | `xmake.conf` scratch; checker parses the table | **FAIL** 1/4 — 0 bytes. Not filed: a setting. The first checker refused the untouched state (it accepted only `plain`, the seed holds `default`) and was fixed; see below |
| espsecure 5.4.0 `sign-data` in place | `fw.bin` scratch; checker: the original, or the original and a signature espsecure verifies | **FAIL** 1/3 — 0 bytes. Not filed: a firmware image is a build output |
| bat 0.25.0 `cache --build` | `metadata.yaml` scratch | **FAIL** 3/8 — `themes.bin` at 0 bytes. Not filed: a cache |
| meson 1.7.0 `setup --reconfigure` | `meson-logs`, `meson-private` scratch | **FAIL** 1/110 — `compile_commands.json` at 0 bytes. Not filed: a build directory |
| infracost 0.10.46 `configure set` | `.state.json` scratch | **UNKNOWN `multiple_threads_detected`** under supervised (Go) |
| plakar 1.1.7 `rm -apply` | `states`, `packfiles`, `locks` scratch | **UNKNOWN `multiple_threads_detected`** under supervised (Go) |
| ccache 4.11.2 `gcc -c` | the clock pinned too (the next step names the clock) | **UNKNOWN `kill_did_not_land`** both ways. Two clean runs put the stats file in a different, randomly chosen subdirectory (`1/6/stats` in one run, elsewhere in the other: `lab-3.txt`), so a kill numbered by the recording lands on another operation |

The predictions (`PREDICTIONS.md`): 12 of 12 for the PRs. For the fifteen the PASS/FAIL split was
written as a guess and missed often: hexapdf, softhsm, meson and OCRmyPDF FAILed where PASS was guessed;
infracost and plakar met threads where a verdict was guessed; firebase PASSed where threads were guessed;
git with the gc off and gocryptfs under supervised met another `baseline_violates_invariant` before the
scratch, where PASS was guessed; and git's first scratch form FAILed on `COMMIT_EDITMSG`. The refusals
predicted to recur (ccache twice, git, firebase and gocryptfs on the page's path) all did.

## What the round says about Sideeye v1.10.0

- **The next steps carried twelve targets to a verdict.** `baseline_violates_invariant`'s "declare the path
  scratch" with #688's "where and what kind", and `preflight --twice` naming the paths, were enough for
  eleven defines; each needed a checker as well, which the step does not say.
- **A checker that refuses the untouched state reads as a FAIL.** xmake's first checker rejected the
  seeded `theme = "default"`; the violation was at crash point 1, "after (start)", before the operation had
  done anything. Sideeye falsifies a checker against a corrupted state before the run, but nothing asks it
  to accept the state the define starts from, and the verdict blames the target.
- **`kill_did_not_land`'s next step does not name a target that picks its paths at random.** ccache's
  stats subdirectory is chosen at random; the step names modes, owners, timestamps, the clock and what lies
  outside `--state`, and pinning the clock changes nothing.
- **An upstream fix can trade one window for another again**: Exiv2 #9504 removes before it renames, the
  shape ImageMagick's second patch had (2026-09-06).
