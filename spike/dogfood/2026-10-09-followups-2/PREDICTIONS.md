# Predictions — 2026-10-09 follow-ups 2

Written before any run, while the box was building. The second "おわり？" of the day found two things
the first recount had narrowed away: fix PRs on this project's upstream reports that nobody had
measured (the first recount read only the reports with a reply or a close), and the 47 unjudged
targets' `--twice` group, which a scratch path and a checker can judge (Home Assistant's way in
`2026-10-09-followups`). This round measures the six fix PRs, each beside the build its report was
measured on, on the page's path of the released v1.10.0.

Not measured, with the reason: terraform #39303 (its last code commit, `28a34e9b8`, is the build
2026-10-02 measured; the one after it moves a changelog file), andreafrancia/trash-cli #428 (the
listing side only; "trash-put is not touched", its own words) and #416 (closed unmerged).

| report | build | prediction | why (from the diff) |
|---|---|---|---|
| SubtitleEdit/subtitleedit#15829 | SeConv 5.2.0 (control) | **FAIL** | the measured truncation |
| | PR #15833 `99f440ebf8` (the maintainer's) | **PASS** | `.<name>.<random>.tmp` beside the subtitle, `Flush(true)`, `File.Move(overwrite: true)` |
| aws/aws-cli#10648 | Debian's awscli (control) | **FAIL** | the measured truncation |
| | PR #10649 `c7999845b3` | **PASS** | `tempfile.mkstemp(dir=…)`, `os.chmod`, `os.replace` |
| Exiv2/exiv2#9482 | Debian's exiv2 (control) | **FAIL** | the measured truncation |
| | PR #9504 `8e2fc85ae2` | **FAIL**, a different shape: the picture absent, its new bytes whole in `pic1.jpg.exv-tmp-<pid>-<n>` | on everything but Windows, `replaceFileAtomically` is `fs::remove(pf)` then `fs::rename(newPath, pf)` — the window ImageMagick's second patch had (`gotcha_upstream_fix_can_be_worse_than_the_report`) |
| beancount/beancount#1051 | Debian's beancount (control) | **FAIL** | the measured truncation |
| | PR #1054 `cc591f7fcf` | **PASS** | `NamedTemporaryFile(dir=…)`, `os.fsync`, `os.chmod`, `os.replace` |
| helm/helm#32709 | helm v4.3.0 (control) | **FAIL** (under supervised, the next step) | the measured truncation |
| | PR #32716 `09cda512f9` | **PASS** | `fileutil.AtomicWriteFile`: a temporary beside the file and a rename |
| solvespace/solvespace#1783 | v3.2 (control) | **FAIL** | the measured truncation |
| | PR #1784 `a3b470a591` (Copilot's) | **FAIL**, the same shape | it checks `fclose`'s result and reports a failed write; the file is still opened truncating before the write |

## The second group, after `preflight --twice` named where two clean runs differ (before these ran)

Fifteen targets no campaign carried to a verdict. Eleven were refused because two clean runs leave
different bytes; `transcripts/twice.txt` and `twice-oracle.txt` name the paths, and each define now
declares them scratch with a checker that reads the data through the tool itself. Four were refused
for another reason, and each is taken one step further. How each tool writes was not read before
these predictions, so the PASS/FAIL split is a guess (about 50%); what is predicted with more
confidence is that each reaches a verdict.

| target | change to the define | prediction |
|---|---|---|
| hexapdf 1.11.0 `modify -i 1-2 a.pdf a.pdf` | `a.pdf` scratch, checker `hexapdf info` (2 or 3 pages) | a verdict; PASS (Ruby's writer goes through a temporary) |
| mu 1.12.9 `move … /archive` | `home` scratch, checker: message 1001 in exactly one folder, whole | a verdict; PASS (a maildir move is one rename) |
| monero-wallet-cli 0.18.5.1 `set_description` | `w` scratch, checker opens the wallet | a verdict; PASS |
| infracost 0.10.46 `configure set api_key` (supervised) | `.state.json` scratch; credentials.yml judged built-in | a verdict; FAIL (Go's `os.WriteFile` truncates) |
| xmake 3.1.1 `g --theme=plain` | `xmake.conf` scratch, checker parses the table | a verdict; FAIL (Lua's `io.open(…, "w")`) |
| espsecure 5.4.0 `sign-data` in place | `fw.bin` scratch, checker verifies the signature or the original | a verdict; FAIL (Python's `open(…, "wb")` over the input) |
| plakar 1.1.7 `rm -apply -tag old` (supervised) | `states`, `packfiles`, `locks` scratch, checker `plakar ls` and `check` | a verdict; PASS |
| softhsm2-util 2.6.1 `--import` | state one level up, `tokens` scratch, checker `pkcs11-tool --list-objects` | a verdict; PASS (a new object file per key) |
| bat 0.25.0 `cache --build` | `metadata.yaml` scratch (its checker kept) | a verdict; FAIL (the cache files truncated and rewritten) |
| meson 1.7.0 `setup --reconfigure` | `meson-logs`, `meson-private` scratch (its checker kept) | a verdict; PASS |
| ocrmypdf 16.7.0 `--force-ocr a.pdf a.pdf` | `a.pdf` scratch (its checker kept) | a verdict; PASS (it writes the output through a temporary) |
| ccache 4.11.2 `gcc -c b.c` | none: the page's path on v1.10.0, its next step followed once | `kill_did_not_land` again |
| git 2.47.3 `commit` | none first, then `-c gc.auto=0 -c maintenance.auto=false` | `child_touched_state_dir` again; with the gc off, a verdict, PASS (git writes through lock files and renames) |
| firebase-tools 15.32.1 `experiments:disable` | none first, then `NO_UPDATE_NOTIFIER=1` | `child_touched_state_dir` again; with the notifier off, `multiple_threads_detected` (Node) |
| gocryptfs 2.6.1 `-passwd` (through `sh`, the new password on stdin) | none: the page's path, then `--observe supervised` named | `child_process_detected` again; supervised past it to a verdict, PASS (gocryptfs.conf through a temporary and a rename) |
