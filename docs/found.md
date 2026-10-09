# Found by Sideeye

Every report in `spike/upstream-reports.tsv` — every report this project has recorded filing upstream — is listed here with the tool, a link to it, and the furthest state `spike/outcome-funnel.tsv` records; CI fails when this page and the two ledgers disagree. A report filed without a row in `spike/upstream-reports.tsv`, or outside GitHub, is not here.

A state is the furthest stage the ledgers record for a report, dated by the reading that recorded it — not a live look at the tracker; `spike/upstream-report-status.sh` reads the trackers. *Fixed upstream, re-measured* means this project ran Sideeye again against the fix. A state carries, in brackets, the reason the funnel gives for where it rests — *awaiting* a reply, *declined*, still *discussing*. Counterexamples Sideeye found and nobody filed are not here; `docs/outcome-funnel.md` counts those. The count and the table below are generated; these paragraphs are written by hand.

This is a list of counterexamples, not a badge: nothing on it says a tool is safe, and a tool missing from it was not shown to be ([DESIGN.md](../DESIGN.md) §15 rules badges out).

<!-- found:begin -->

39 reports: 8 fixed upstream and re-measured, 1 fixed upstream, 29 filed, 1 withdrawn.

| Tool | Report | State | As of |
|---|---|---|---|
| timewarrior | [GothenburgBitFactory/timewarrior#778](https://github.com/GothenburgBitFactory/timewarrior/issues/778) | fixed upstream, re-measured | 2026-08-13 |
| himalaya | [pimalaya/himalaya#738](https://github.com/pimalaya/himalaya/issues/738) | fixed upstream, re-measured | 2026-08-22 |
| mogrify | [ImageMagick/ImageMagick#8939](https://github.com/ImageMagick/ImageMagick/issues/8939) | fixed upstream, re-measured | 2026-09-06 |
| codespell 2.4.1 | [codespell-project/codespell#4025](https://github.com/codespell-project/codespell/issues/4025) | fixed upstream, re-measured | 2026-10-02 |
| rubocop 1.39.0 | [rubocop/rubocop#15720](https://github.com/rubocop/rubocop/issues/15720) | fixed upstream, re-measured | 2026-10-02 |
| neovim 0.10.4 and 0.12.5 (`:wshada`) | [neovim/neovim#41940](https://github.com/neovim/neovim/issues/41940) | fixed upstream, re-measured | 2026-10-09 |
| DwarFS 0.15.8 `mkdwarfs --recompress` | [mhx/dwarfs#388](https://github.com/mhx/dwarfs/issues/388) | fixed upstream, re-measured | 2026-10-09 |
| PyMOL 3.1.0 (Debian) `save` of a `.pse` | [schrodinger/pymol-open-source#520](https://github.com/schrodinger/pymol-open-source/issues/520) | fixed upstream, re-measured | 2026-10-09 |
| tombi 1.5.6 and 1.7.0 | [tombi-toml/tombi#2265](https://github.com/tombi-toml/tombi/issues/2265) | fixed upstream | 2026-10-02 |
| topydo | [topydo/topydo#341](https://github.com/topydo/topydo/issues/341) | filed (awaiting) | 2026-08-14 |
| calcurse | [lfos/calcurse#529](https://github.com/lfos/calcurse/issues/529) | filed (awaiting) | 2026-08-14 |
| GNU Stow | [aspiers/stow#139](https://github.com/aspiers/stow/issues/139) | filed (awaiting) | 2026-08-14 |
| poetry | [python-poetry/poetry#11019](https://github.com/python-poetry/poetry/issues/11019) | filed (awaiting) | 2026-08-22 |
| qpdf | [qpdf/qpdf#1773](https://github.com/qpdf/qpdf/issues/1773) | filed (awaiting) | 2026-09-04 |
| trash-cli | [andreafrancia/trash-cli#414](https://github.com/andreafrancia/trash-cli/issues/414) | filed (awaiting) | 2026-09-04 |
| exiv2 | [Exiv2/exiv2#9482](https://github.com/Exiv2/exiv2/issues/9482) | filed (awaiting) | 2026-09-05 |
| fonttools | [fonttools/fonttools#4170](https://github.com/fonttools/fonttools/issues/4170) | filed (declined) | 2026-09-16 |
| bean-format | [beancount/beancount#1051](https://github.com/beancount/beancount/issues/1051) | filed (awaiting) | 2026-09-16 |
| pyupgrade | [asottile/pyupgrade#1101](https://github.com/asottile/pyupgrade/issues/1101) | filed (declined) | 2026-09-16 |
| jpegtran | [libjpeg-turbo/libjpeg-turbo#914](https://github.com/libjpeg-turbo/libjpeg-turbo/issues/914) | filed (discussing) | 2026-09-16 |
| oxipng 10.2.1 | [oxipng/oxipng#873](https://github.com/oxipng/oxipng/issues/873) | filed (declined) | 2026-09-16 |
| cargo 1.97.1 | [rust-lang/cargo#17481](https://github.com/rust-lang/cargo/issues/17481) | filed (declined) | 2026-09-16 |
| aws-cli 2.23.6 | [aws/aws-cli#10648](https://github.com/aws/aws-cli/issues/10648) | filed (awaiting) | 2026-09-16 |
| ast-grep 0.45.3 | [ast-grep/ast-grep#2959](https://github.com/ast-grep/ast-grep/issues/2959) | filed (awaiting) | 2026-09-22 |
| nbqa 1.9.1 (`nbqa black`, black 26.5.1) | [nbQA-dev/nbQA#908](https://github.com/nbQA-dev/nbQA/issues/908) | filed (awaiting) | 2026-09-28 |
| terraform 1.16.4 `fmt` | [hashicorp/terraform#39299](https://github.com/hashicorp/terraform/issues/39299) | filed (awaiting) | 2026-09-28 |
| helm 4.3.0 `repo remove` | [helm/helm#32709](https://github.com/helm/helm/issues/32709) | filed (awaiting) | 2026-10-02 |
| ktlint 1.8.0 | [ktlint/ktlint#3409](https://github.com/ktlint/ktlint/issues/3409) | filed (awaiting) | 2026-10-02 |
| git-cliff 2.14.2 `--prepend` | [orhun/git-cliff#1650](https://github.com/orhun/git-cliff/issues/1650) | filed (awaiting) | 2026-10-02 |
| notesmd-cli 0.3.7 `move` | [Yakitrak/notesmd-cli#137](https://github.com/Yakitrak/notesmd-cli/issues/137) | filed (awaiting) | 2026-10-03 |
| mapshaper 0.7.72 `-o force` | [mbloch/mapshaper#706](https://github.com/mbloch/mapshaper/issues/706) | filed (declined) | 2026-10-09 |
| SolveSpace 3.2 `solvespace-cli regenerate` | [solvespace/solvespace#1783](https://github.com/solvespace/solvespace/issues/1783) | filed (awaiting) | 2026-10-05 |
| ffsubsync 0.5.1 `--overwrite-input` | [smacke/ffsubsync#240](https://github.com/smacke/ffsubsync/issues/240) | filed (awaiting) | 2026-10-05 |
| WP-CLI 2.12.0 `config set` | [wp-cli/config-command#233](https://github.com/wp-cli/config-command/issues/233) | filed (awaiting) | 2026-10-05 |
| Subtitle Edit's SeConv 5.2.0 `subs.srt subrip --offset:-2000 --overwrite` | [SubtitleEdit/subtitleedit#15829](https://github.com/SubtitleEdit/subtitleedit/issues/15829) | filed (awaiting) | 2026-10-09 |
| MCA Selector 2.9 `--mode delete --query "InhabitedTime < 1000"` | [Querz/mcaselector#613](https://github.com/Querz/mcaselector/issues/613) | filed (awaiting) | 2026-10-09 |
| SoftHSM 2.6.1 `softhsm2-util --import` | [softhsm/SoftHSMv2#908](https://github.com/softhsm/SoftHSMv2/issues/908) | filed (awaiting) | 2026-10-09 |
| OCRmyPDF 16.7.0 `--force-ocr a.pdf a.pdf` | [ocrmypdf/OCRmyPDF#1762](https://github.com/ocrmypdf/OCRmyPDF/issues/1762) | filed (awaiting) | 2026-10-09 |
| devtodo | [alecthomas/devtodo#9](https://github.com/alecthomas/devtodo/issues/9) | withdrawn | 2026-08-14 |

<!-- found:end -->
