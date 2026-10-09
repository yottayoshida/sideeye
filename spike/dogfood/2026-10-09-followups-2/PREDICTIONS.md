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
