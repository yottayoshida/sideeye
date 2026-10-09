#!/usr/bin/env python3
"""The last eight of the 2026-10-09 follow-ups 3 round, after ledger-rows.py: the walls taken one switch or
one filesystem further. Run once from the repository root, after ledger-rows.py.
No backticked word holds a `/` in the doc rows (acceptance check 11)."""
from pathlib import Path

C = "dogfood/2026-10-09-followups-3"
R = "spike/dogfood/2026-10-09-followups-3"
E = f"{R}/transcripts/explore"
REC = f"`{R}/RESULTS.md`"
FAT = "on a FAT filesystem (no O_TMPFILE, no ACL)"

def j(d, lab="explore"):
    return f"{E}/{d}/{lab}.json"

new = [
    ("vim", "judged", "fail", "not_worth", "-", j("vim-fat"), "-", f"FAIL 1/12 {FAT}, where vim writes no ACL back: a.txt truncated before its write with nowritebackup, the user's own choice of no backup"),
    ("kvantum", "judged", "pass", "-", "-", j("kvantum-fat"), "-", f"PASS {FAT}: Qt's O_TMPFILE fails EOPNOTSUPP and it saves through a named temporary and a rename"),
    ("h2cli", "judged", "fail", "no_content_lost", "-", j("h2cli-fat-check"), "-", f"FAIL 1/9 {FAT}, drumkit.xml scratch and a checker reading the kit: drumkit.xml truncated before its write, the old bytes whole in the dated .bak h2cli writes first"),
    ("flatpak", "attempted", "unknown", "wall", "-", j("flatpak-fat"), "-", f"unsupported_syscall_observed (fallocate) {FAT}: libglnx's named-temporary fallback reserves space first"),
    ("ostree", "attempted", "unknown", "wall", "-", j("ostree-fat"), "-", f"unsupported_syscall_observed (fallocate) {FAT}, Debian's ostree: libglnx's fallback, as for flatpak"),
    ("ccache", "explored", "unknown", "wall", "-", j("ccache-nostats-builtin"), "-", "nothing_could_fail with CCACHE_NOSTATS=1 (the random stats subdirectory gone): the operation only creates cache files, and a checker on its output cannot fail, since ccache rebuilds a damaged entry itself (checker_not_falsified)"),
    ("fitscheck", "judged", "fail", "not_worth", "-", j("fitscheck-nommap"), "-", "FAIL 1/6 with astropy's use_memmap = False: obs.fits torn between two writes of its header; not filed, since the default (a shared mapping) is not what this measured"),
]
p = Path("spike/outcome-funnel.tsv"); rows = p.read_text().rstrip("\n").split("\n")
out = []; fixed = 0
for r in rows:
    f = r.split("\t")
    if len(f) == 9 and f[0] == C and f[1] == "lingui":
        f[2:9] = ["judged", "fail", "not_worth", "-", j("lingui-direct"), "-",
                  "FAIL 3/7 on Node 22 with lingui-extract.js invoked directly (lingui.js runs it as a child, which was the child_touched_state_dir), --workers 1 and one libuv thread: en/messages.po truncated; a catalog under version control"]
        r = "\t".join(f); fixed += 1
    out.append(r)
assert fixed == 1
assert not any(r.startswith(C + "\tvim\t") for r in out), "already written"
out += ["\t".join([C, t, st, v, sp, rep, ev, asof, note]) for t, st, v, sp, rep, ev, asof, note in new]
p.write_text("\n".join(out) + "\n")

T = "2026-10-09 follow-ups 3"
add = {
    "| Editors that write the target's extended attributes back | vim 9.x |": f" **{T}:** {FAT.replace('(no O_TMPFILE, no ACL)', '')}vim writes no ACL back and reaches a verdict, FAIL (the first table)",
    "| Caches whose call sequence varies between runs | ccache 4.x |": f" With its statistics off (`CCACHE_NOSTATS=1`) the call sequence is fixed and the run is `nothing_could_fail`: it only creates cache files, and ccache rebuilds a damaged entry itself, so no checker can fail",
    "| Other walls at the gate | gocryptfs 2.6.1, flatpak 1.16.6 |": f" flatpak on a FAT filesystem takes libglnx's named-temporary path and meets `fallocate`, which Sideeye does not model",
    "| Other walls at the gate | astropy 8.0.1 `fitscheck -w`": f" fitscheck with astropy's `use_memmap = False` has no shared mapping and FAILs (the first table)",
    "| Qt's save through an unnamed temporary file | Kvantum 1.1.4": f" **{T}:** on a FAT filesystem the `O_TMPFILE` open fails and Qt saves through a named temporary: Kvantum PASS, Hydrogen FAIL with its backup whole (the first table)",
    "| Other walls at the gate | goaccess 1.12 `--persist --restore`, libostree 2026.4 `remote add`": f" **{T}:** Debian's ostree on a FAT filesystem takes libglnx's named-temporary path and meets `fallocate`",
}
def fail(cls, tool, res, why):
    return f"| {cls} | {tool} | **FAIL** {res}. {why} | {REC} |"
verdicts = [
    fail("Editor writing in place on a FAT filesystem (no ACL to write back)", "vim 9.1 `%s` and `wq` with `nowritebackup`", "1/12 — `a.txt` truncated before its write", "Not filed: no backup was the user's choice"),
    f"| Theme manager's config on a FAT filesystem (Qt's named-temporary fallback) | Kvantum 1.1.4 `kvantummanager --set` | **PASS** | {REC} |",
    fail("Drum kit upgraded on a FAT filesystem (Qt, `drumkit.xml` scratch, a checker reading the kit)", "Hydrogen 1.2.2 `h2cli -u`", "1/9 — `drumkit.xml` truncated before its write", "Not filed: its dated backup holds the old bytes whole"),
    fail("FITS checksums written in place, astropy's memory map off", "astropy 8.0.1 `fitscheck -w`", "1/6 — `obs.fits` torn between two writes of its header", "Not filed: the default path (a shared mapping) is not what this measured"),
    fail("Message catalogs extracted (Node 22, the subcommand's script run directly)", "lingui 6.9.0 `lingui-extract.js`", "3/7 — the English `messages.po` truncated before its write", "Not filed: catalogs live under version control"),
]
p = Path("docs/target-classes.md"); lines = p.read_text().split("\n")
for pre, sentence in add.items():
    hits = [i for i, l in enumerate(lines) if l.startswith(pre)]
    assert len(hits) == 1, (pre, len(hits))
    i = hits[0]; cells = lines[i].split(" | ")
    body = cells[-2].rstrip()
    cells[-2] = body + ("" if body.endswith(".") else ".") + " " + sentence.lstrip()
    if REC not in cells[-1]:
        cells[-1] = cells[-1][:-2].rstrip() + " " + REC + " |"
    lines[i] = " | ".join(cells)
i = next(n for n, l in enumerate(lines) if l.startswith("## Measured, with verdicts"))
k = i + 1
while not lines[k].startswith("|"):
    k += 1
while k < len(lines) and lines[k].startswith("|"):
    k += 1
lines[k:k] = verdicts
p.write_text("\n".join(lines))
print(len(new), "funnel rows added, lingui moved,", len(add), "rows amended,", len(verdicts), "verdict rows")
