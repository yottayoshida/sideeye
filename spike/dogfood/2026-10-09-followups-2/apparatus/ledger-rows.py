#!/usr/bin/env python3
"""The 2026-10-09 follow-ups 2 round, written into the ledgers. Run once from the repository root.

- spike/outcome-funnel.tsv: one row per target this round met (the six PR'd tools, the fifteen), and
  the campaign line. The PR rows are `judged`: a PR that is not merged has not landed, so the original
  rows stay where they are (2026-10-02's terraform precedent); the PR build's verdict is this round's.
- spike/upstream-reports.tsv and spike/unknown-rate/b2-exclusion-aliases.tsv: the two reports filed.
- docs/target-classes.md: a sentence on each row whose tool this round moved, and a verdict row for each
  of the twelve that reached one.

No backticked word holds a `/` in the doc rows: acceptance check 11 reads such a word as a path here."""
from pathlib import Path

C = "dogfood/2026-10-09-followups-2"
R = "spike/dogfood/2026-10-09-followups-2"
E = f"{R}/transcripts/explore"
REC = f"`{R}/RESULTS.md`"
AS = "2026-10-09"
SH_TOOL = "SoftHSM 2.6.1 `softhsm2-util --import`"
OC_TOOL = "OCRmyPDF 16.7.0 `--force-ocr a.pdf a.pdf`"

funnel = [
    # the PR builds
    ("seconv", "judged", "pass", "-", "-", f"{E}/seconv-pr/explore.json", "-", "SubtitleEdit/subtitleedit#15833 (the maintainer's PR, 99f440ebf8, not merged) PASS 5/5 on 2026-10-09 user-data-4's define; SeConv 5.2.0 FAIL 1/4 beside it"),
    ("aws-cli", "judged", "pass", "-", "-", f"{E}/aws-pr/explore.json", "-", "aws/aws-cli#10649 (c7999845b3, not merged) PASS 4/4 on 2026-09-16's define; Debian's 2.23.6 FAIL 1/3 beside it"),
    ("exiv2", "judged", "fail", "known", "-", f"{E}/exiv2-pr/explore.json", "-", "Exiv2/exiv2#9504 (8e2fc85ae2, not merged) ends the truncation and FAILs 3/16 another way: pic1.jpg removed before the temporary is renamed over it; commented on the PR with a reproduction"),
    ("bean-format", "judged", "pass", "-", "-", f"{E}/beanfmt-pr/explore.json", "-", "beancount/beancount#1054 (cc591f7fcf, not merged) PASS 6/6; Debian's 3.1.0 FAIL 1/3 beside it"),
    ("helm", "judged", "pass", "-", "-", f"{E}/helm-pr/syscalls.json", "-", "helm/helm#32716 (09cda512f9, not merged) PASS 6/6 under --observe syscalls, the next step; v4.3.0 FAIL 1/5 under supervised beside it"),
    ("solvespace", "judged", "fail", "known", "-", f"{E}/solvespace-pr/syscalls.json", "-", "solvespace/solvespace#1784 (a3b470a591, Copilot's, not merged) reports a failed fclose and FAILs 15/17 the same way as v3.2"),
    # the fifteen
    ("mu", "judged", "pass", "-", "-", f"{E}/mu/explore.json", "-", "PASS 24/24 with home (the Xapian index) scratch and a checker on the maildir"),
    ("monero", "judged", "pass", "-", "-", f"{E}/monero/explore.json", "-", "PASS 6/6 with the wallet cache w scratch and a checker that opens the wallet"),
    ("git", "judged", "pass", "-", "-", f"{E}/git-nogc-scratch2/explore.json", "-", "PASS 39/39 with gc and maintenance off, .git/index and .git/COMMIT_EDITMSG scratch, the dates pinned, a checker (fsck, HEAD, the work tree)"),
    ("firebase", "judged", "pass", "-", "-", f"{E}/firebase-nonotifier/explore.json", "-", "PASS 11/11 with NO_UPDATE_NOTIFIER=1, the notifier's child being what wrote the state"),
    ("gocryptfs", "judged", "pass", "-", "-", f"{E}/gocryptfs-check/probe-supervised.json", "-", "PASS 5/5 under --observe supervised with cipher/gocryptfs.conf scratch and a checker through gocryptfs-xray"),
    ("softhsm", "filed", "fail", "awaiting", "softhsm/SoftHSMv2#908", f"{E}/softhsm/explore.json", AS, "FAIL 106/283: token.object truncated and the kill before its write, the token gone from its slot and the key already in it unreachable; reproduced without Sideeye; filed with the owner's approval of the full text"),
    ("ocrmypdf", "filed", "fail", "awaiting", "ocrmypdf/OCRmyPDF#1762", f"{E}/ocrmypdf/explore.json", AS, "FAIL 1/3: the cookbook's in-place run empties the PDF when killed during the final copy, against its own words; reproduced without Sideeye; filed with the owner's approval of the full text"),
    ("hexapdf", "judged", "fail", "not_worth", "-", f"{E}/hexapdf/explore.json", "-", "FAIL 5/13: a.pdf at 0 bytes; in place only when -f lets the output name the input"),
    ("xmake", "judged", "fail", "not_worth", "-", f"{E}/xmake-fixed/explore.json", "-", "FAIL 1/4: xmake.conf at 0 bytes, a setting; the first checker refused the seeded theme and was fixed"),
    ("espsecure", "judged", "fail", "not_worth", "-", f"{E}/espsecure/explore.json", "-", "FAIL 1/3: fw.bin at 0 bytes; a firmware image is a build output"),
    ("bat", "judged", "fail", "not_worth", "-", f"{E}/bat/explore.json", "-", "FAIL 3/8: themes.bin at 0 bytes; a cache"),
    ("meson", "judged", "fail", "not_worth", "-", f"{E}/meson/explore.json", "-", "FAIL 1/110: compile_commands.json at 0 bytes; a build directory"),
    ("infracost", "explored", "unknown", "wall", "-", f"{E}/infracost/supervised.json", "-", "multiple_threads_detected under --observe supervised, with .state.json scratch"),
    ("plakar", "attempted", "unknown", "wall", "-", f"{E}/plakar/supervised.json", "-", "multiple_threads_detected under --observe supervised, with the repository's state files scratch"),
    ("ccache", "explored", "unknown", "wall", "-", f"{E}/ccache-clock/explore.json", "-", "kill_did_not_land with the clock pinned too: the stats file goes to a randomly chosen subdirectory, so the recording's operation numbers name other operations"),
]

p = Path("spike/outcome-funnel.tsv"); rows = p.read_text().rstrip("\n").split("\n")
assert not any(r.startswith(C + "\t") for r in rows), "already written"
rows += ["\t".join([C, t, st, v, sp, rep, ev, asof, note]) for t, st, v, sp, rep, ev, asof, note in funnel]
p.write_text("\n".join(rows) + "\n")
p = Path("spike/outcome-funnel-campaigns.tsv"); s = p.read_text()
p.write_text(s + ("" if s.endswith("\n") else "\n") + f"{C}\t{AS}\tfull\t-\t{R}/RESULTS.md\n")
p = Path("spike/upstream-reports.tsv"); s = p.read_text()
p.write_text(s + ("" if s.endswith("\n") else "\n") + f"softhsm/SoftHSMv2\t908\tstanding\t{SH_TOOL}\nocrmypdf/OCRmyPDF\t1762\tstanding\t{OC_TOOL}\n")
p = Path("spike/unknown-rate/b2-exclusion-aliases.tsv"); s = p.read_text()
p.write_text(s + ("" if s.endswith("\n") else "\n") + f"{SH_TOOL}\t-\tupstream-reports.tsv (SoftHSMv2)\n{OC_TOOL}\t-\tupstream-reports.tsv (Debian's ocrmypdf)\n")

# ---- docs/target-classes.md
T = "2026-10-09 follow-ups 2"
add = {
    "| Subtitle converter writing over its input (.NET) |": f" The maintainer's fix, SubtitleEdit/subtitleedit#15833 (a temporary beside the subtitle and a rename), **PASSes** 5/5 on the same define ({T})",
    "| Cloud CLI rewriting its credentials file | aws-cli 2.23.6 |": f" aws/aws-cli#10649 (an `mkstemp` beside the file and `os.replace`, not merged) **PASSes** 4/4 ({T})",
    "| C++ image metadata editor | exiv2 |": f" Exiv2/exiv2#9504 (not merged) ends the truncation but **FAILs** 3/16 another way: the picture removed before the temporary is renamed over it, nothing at its name and the new bytes beside it; commented on the PR ({T})",
    "| Python ledger formatter | bean-format |": f" beancount/beancount#1054 (a temporary, `fsync` and `os.replace`, not merged) **PASSes** 6/6 ({T})",
    "| Helm client rewriting its repository list (static Go, `--observe supervised`) |": f" helm/helm#32716 (`AtomicWriteFile`, not merged) **PASSes** 6/6 under `--observe syscalls` ({T})",
    "| CAD sketch saved by the command-line tool (`--observe syscalls`, the next step) |": f" solvespace/solvespace#1784 (Copilot's, not merged) reports a failed `fclose` and **FAILs** 15/17 the same way ({T})",
    "| PDF OCR over helper processes | ocrmypdf 16.7.0 |": f" **{T}:** with `a.pdf` scratch it reaches a verdict, FAIL, filed (the first table)",
    "| Caches whose metadata varies between clean runs | bat 0.25.0 |": f" **{T}:** with `metadata.yaml` scratch, FAIL (the first table)",
    "| Caches whose call sequence varies between runs | ccache 4.x |": f" **{T}:** the sequence varies because the stats file goes to a randomly chosen subdirectory; pinning the clock, which the next step names, changes nothing",
    "| Build systems that log their own configuration run | meson 1.7.0 |": f" **{T}:** with `meson-logs` and `meson-private` scratch, FAIL (the first table)",
    "| Bytes that differ between two runs | hexapdf 1.11.0 (clock pinned), mu 1.12.9 (its Xapian index) |": f" **{T}:** each reaches a verdict with the differing path scratch and a checker — hexapdf FAIL, mu PASS (the first table)",
    "| Other walls at the gate | gocryptfs 2.6.1, flatpak 1.16.6 |": f" **{T}:** gocryptfs PASSes under `--observe supervised` with its config scratch and a checker (the first table)",
    "| Bytes that differ between two runs | monero-wallet-cli 0.18.5.1": f" **{T}:** with the differing path scratch, monero PASS and xmake FAIL (the first table); infracost meets threads under supervised",
    "| Other walls at the gate | astropy 8.0.1 `fitscheck -w`": f" **{T}:** firebase-tools PASSes with `NO_UPDATE_NOTIFIER=1` (the first table)",
    "| Bytes that differ between two runs | espsecure (esptool 5.4.0)": f" **{T}:** espsecure FAILs with `fw.bin` scratch and a checker (the first table); plakar meets threads under supervised",
    "| Bytes that differ between two runs | softhsm2-util 2.6.1 `--import`": f" **{T}:** with the state one level up and `tokens` scratch, FAIL, filed (the first table)",
}
verdicts = [
    f"| HSM token rewritten in place (C++, `tokens` scratch, a checker through PKCS#11) | {SH_TOOL} | **FAIL** 106/283 explored worlds, earliest crash point 6 of 282 — `token.object` truncated and the kill before its write: the token gone from its slot, and the key already in it unreachable (its PIN blobs were in that file). Replayed twice; reproduced without Sideeye by strace's `inject`. Reported upstream as softhsm/SoftHSMv2#908 <!-- upstream-report: softhsm/SoftHSMv2#908 --> | {REC} |",
    f"| PDF OCR written over its input, the cookbook's in-place run (`a.pdf` scratch, a PDF reader as checker) | {OC_TOOL} | **FAIL** 1/3 explored worlds, crash point 2 of 2 — `a.pdf` opened to be written and the kill before the copy: **0 bytes** (537 before); the cookbook says the file is only overwritten on success. Replayed twice; reproduced without Sideeye. Reported upstream as ocrmypdf/OCRmyPDF#1762 <!-- upstream-report: ocrmypdf/OCRmyPDF#1762 --> | {REC} |",
    f"| PDF modified over its input (Ruby, `a.pdf` scratch, `hexapdf info` as checker) | hexapdf 1.11.0 `-f modify -i 1-2 a.pdf a.pdf` | **FAIL** 5/13 — `a.pdf` at 0 bytes. Not filed: in place only when `-f` lets the output name the input | {REC} |",
    f"| Build tool's global config (Lua, `xmake.conf` scratch, a checker on the table) | xmake 3.1.1 `g --theme=plain` | **FAIL** 1/4 — `xmake.conf` at 0 bytes. Not filed: a setting | {REC} |",
    f"| Firmware signed in place (Python, `fw.bin` scratch, the signature verified) | espsecure (esptool 5.4.0) `sign-data` | **FAIL** 1/3 — `fw.bin` at 0 bytes. Not filed: a build output | {REC} |",
    f"| Syntax and theme cache rebuilt (Rust, `metadata.yaml` scratch) | bat 0.25.0 `cache --build` | **FAIL** 3/8 — `themes.bin` at 0 bytes. Not filed: a cache | {REC} |",
    f"| Build directory reconfigured (Python, `meson-logs` and `meson-private` scratch) | meson 1.7.0 `setup --reconfigure` | **FAIL** 1/110 — `compile_commands.json` at 0 bytes. Not filed: a build directory | {REC} |",
    f"| Mail moved between maildir folders (the index scratch, a checker on the mail) | mu 1.12.9 `move` | **PASS** 24/24 | {REC} |",
    f"| Wallet description set offline (the cache scratch, the wallet opened as checker) | monero-wallet-cli 0.18.5.1 `set_description` | **PASS** 6/6 | {REC} |",
    f"| Commit with gc and maintenance off (the index and `COMMIT_EDITMSG` scratch, the dates pinned, fsck as checker) | git 2.47.3 `commit` | **PASS** 39/39 — the form without `COMMIT_EDITMSG` scratch FAILed on that file alone | {REC} |",
    f"| CLI config with its update notifier off (Node) | firebase-tools 15.32.1 `experiments:disable` | **PASS** 11/11 with `NO_UPDATE_NOTIFIER=1` | {REC} |",
    f"| Encrypted filesystem's passphrase changed (static Go, `--observe supervised`, the config scratch, the master key unwrapped as checker) | gocryptfs 2.6.1 `-passwd` | **PASS** 5/5 | {REC} |",
]
p = Path("docs/target-classes.md"); lines = p.read_text().split("\n")
assert not any(R in l for l in lines), "already inserted"
for pre, sentence in add.items():
    hits = [i for i, l in enumerate(lines) if l.startswith(pre)]
    assert len(hits) == 1, (pre, len(hits))
    i = hits[0]; cells = lines[i].split(" | ")
    body = cells[-2].rstrip()
    cells[-2] = body + ("" if body.endswith(".") else ".") + sentence
    cells[-1] = cells[-1][:-2].rstrip() + " " + REC + " |"
    lines[i] = " | ".join(cells)
i = next(n for n, l in enumerate(lines) if l.startswith("## Measured, with verdicts"))
j = i + 1
while not lines[j].startswith("|"):
    j += 1
while j < len(lines) and lines[j].startswith("|"):
    j += 1
lines[j:j] = verdicts
p.write_text("\n".join(lines))
print(len(funnel), "funnel rows,", len(add), "rows amended,", len(verdicts), "verdict rows")
