#!/usr/bin/env python3
"""The 2026-10-09 follow-ups 3 round, written into the ledgers. Run once from the repository root.

SubtitleEdit/subtitleedit#15829's fix landed the same day it was filed, so its revalidation went onto the
filing campaign's own row by hand (the funnel reads the filing as the earliest campaign at filed or beyond,
and two campaigns of one date carrying it are refused), not into this script.

- spike/outcome-funnel.tsv: a row per target this round met, and the campaign line.
- spike/upstream-reports.tsv and the B2 aliases: dotenvx/dotenvx#1012.
- docs/target-classes.md: a sentence on each threads-wall row this round moved, and a verdict row for
  each target that reached one.
No backticked word holds a `/` in the doc rows: acceptance check 11 reads such a word as a path."""
from pathlib import Path

C = "dogfood/2026-10-09-followups-3"
R = "spike/dogfood/2026-10-09-followups-3"
E = f"{R}/transcripts/explore"
REC = f"`{R}/RESULTS.md`"
AS = "2026-10-09"
DX_TOOL = "dotenvx 2.32.4 `encrypt`"
NODE1 = "with UV_THREADPOOL_SIZE=1 (one libuv thread)"

def j(d, lab="explore"):
    return f"{E}/{d}/{lab}.json"

funnel = [
    ("yarn", "judged", "fail", "not_worth", "-", j("yarn-pool1"), "-", f"FAIL 1/3 {NODE1}: .yarnrc.yml truncated before its write; a setting and a token re-issued"),
    ("trash", "judged", "pass", "-", "-", j("trash-pool1"), "-", f"PASS 9/9 {NODE1}"),
    ("bibtex-tidy", "judged", "fail", "not_worth", "-", j("bibtex-tidy"), "-", f"FAIL 1/3 {NODE1}: refs.bib truncated; a file under version control"),
    ("dotenvx", "filed", "fail", "awaiting", "dotenvx/dotenvx#1012", j("dotenvx-check"), AS, f"FAIL 1/5 {NODE1}, .env and .env.keys scratch, dotenvx get as checker: .env emptied after .env.keys is written; reproduced without Sideeye; filed with the owner's approval of the full text"),
    ("gemini", "attempted", "unknown", "wall", "-", j("gemini"), "-", f"multiple_threads_detected {NODE1} too"),
    ("gltf-transform", "judged", "fail", "not_worth", "-", j("gltf-transform"), "-", f"FAIL 1/3 {NODE1}: terrain.glb truncated; in place only when the output names the input"),
    ("lingui", "attempted", "unknown", "wall", "-", j("lingui-w1"), "-", f"child_touched_state_dir on Node 22 {NODE1} and --workers 1: a child makes the catalog directories"),
    ("vercel", "attempted", "unknown", "wall", "-", j("vercel"), "-", f"multiple_threads_detected {NODE1} too"),
    ("cspell", "judged", "fail", "not_worth", "-", j("cspell"), "-", f"FAIL 1/4 on Node 22 {NODE1}: cspell.json truncated; a setting"),
    ("capacitor", "judged", "fail", "not_worth", "-", j("capacitor"), "-", f"FAIL 1/4 on Node 22 {NODE1}: sysconfig.json truncated; a setting"),
    ("eslint", "judged", "fail", "not_worth", "-", j("eslint"), "-", f"FAIL 1/3 {NODE1}: a.js truncated by --fix; source under version control"),
    ("prettier", "judged", "fail", "not_worth", "-", j("prettier"), "-", f"FAIL 1/3 {NODE1}: a.js truncated by --write; source under version control"),
    ("stylelint", "judged", "pass", "-", "-", j("stylelint"), "-", f"PASS 6/6 {NODE1}"),
    ("svgo", "judged", "fail", "not_worth", "-", j("svgo"), "-", f"FAIL 1/4 {NODE1}: a.svg truncated; an asset under version control"),
    ("npm pkg set", "judged", "fail", "not_worth", "-", j("npm-pkg-set"), "-", f"FAIL 1/3 {NODE1}: package.json truncated; a file under version control"),
    ("joplin", "judged", "pass", "-", "-", j("joplin-check3"), "-", f"PASS 49/49 {NODE1}, database.sqlite, log.txt and tmp scratch, joplin ls as checker"),
    ("Bitwarden", "attempted", "unknown", "wall", "-", j("bitwarden"), "-", f"multiple_threads_detected {NODE1} too"),
    ("tofu", "attempted", "unknown", "wall", "-", j("tofu", "supervised"), "-", "multiple_threads_detected under supervised with GOMAXPROCS=1 too"),
    ("doctl", "judged", "fail", "not_worth", "-", j("doctl", "supervised"), "-", "FAIL 1/3 under supervised with GOMAXPROCS=1: config.yaml truncated; a token re-issued"),
    ("infracost", "judged", "fail", "not_worth", "-", j("infracost", "supervised"), "-", "FAIL 1/5 under supervised with GOMAXPROCS=1 and .state.json scratch: credentials.yml truncated; a key re-issued"),
    ("plakar", "judged", "pass", "-", "-", j("plakar", "supervised"), "-", "PASS 6/6 under supervised with GOMAXPROCS=1, the state files scratch and plakar as checker"),
    ("zstd", "judged", "pass", "-", "-", j("zstd-check", "syscalls"), "-", "PASS 8/8 under syscalls with --single-thread --no-asyncio and a checker on the data (--single-thread alone still met threads: zstd's I/O thread)"),
    ("lz4", "attempted", "unknown", "wall", "-", j("lz4", "syscalls"), "-", "multiple_threads_detected under syscalls with -T1 too"),
    ("beets", "judged", "pass", "-", "-", j("beets-check"), "-", "PASS 43/43 with threaded: no and library.db scratch"),
    ("rustic", "attempted", "unknown", "wall", "-", j("rustic"), "-", "multiple_threads_detected with RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1 too"),
    ("prek", "attempted", "unknown", "wall", "-", j("prek"), "-", "multiple_threads_detected with RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1 too"),
    ("codex", "attempted", "unknown", "wall", "-", j("codex", "supervised"), "-", "multiple_threads_detected under supervised with RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1 too"),
    ("steamguard", "attempted", "unknown", "wall", "-", j("steamguard"), "-", "multiple_threads_detected with RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1 too"),
    ("dokuwiki", "judged", "fail", "known", "-", j("dokuwiki"), "-", "FAIL 5/31: pages/wiki/start.txt truncated before its write; its tracker's #677"),
    ("lighthouse", "judged", "pass", "-", "-", j("lighthouse"), "-", "PASS 8/8, never explored before (cleared the gate on 2026-10-05)"),
    ("jump", "judged", "pass", "-", "-", j("jump", "supervised"), "-", "PASS 13/13 under supervised, never explored before (cleared the gate on 2026-10-05)"),
    ("keyring", "judged", "fail", "not_worth", "-", j("keyring"), "-", "FAIL 1/3: keyrings.alt's keyring_pass.cfg truncated; the write is keyrings.alt's (29 stars)"),
    ("git-lfs", "judged", "pass", "-", "-", j("gitlfs"), "-", "PASS 18/18, never explored before (cleared the gate on 2026-10-07)"),
]

p = Path("spike/outcome-funnel.tsv"); rows = p.read_text().rstrip("\n").split("\n")
assert not any(r.startswith(C + "\t") for r in rows), "already written"
rows += ["\t".join([C, t, st, v, sp, rep, ev, asof, note]) for t, st, v, sp, rep, ev, asof, note in funnel]
p.write_text("\n".join(rows) + "\n")
p = Path("spike/outcome-funnel-campaigns.tsv"); s = p.read_text()
p.write_text(s + ("" if s.endswith("\n") else "\n") + f"{C}\t{AS}\tfull\t-\t{R}/RESULTS.md\n")
p = Path("spike/upstream-reports.tsv"); s = p.read_text()
p.write_text(s + ("" if s.endswith("\n") else "\n") + f"dotenvx/dotenvx\t1012\tstanding\t{DX_TOOL}\n")
p = Path("spike/unknown-rate/b2-exclusion-aliases.tsv"); s = p.read_text()
p.write_text(s + ("" if s.endswith("\n") else "\n") + f"{DX_TOOL}\t-\tupstream-reports.tsv (dotenvx)\n")

T = "2026-10-09 follow-ups 3"
add = {
    "| Node/libuv tools | joplin CLI 3.6.x, 3.7.1 |": f" **{T}:** with `UV_THREADPOOL_SIZE=1` it is past the wall, and with its database, log and `tmp` scratch it PASSes (the first table)",
    "| Node linters fixing a file in place (`--fix`) | eslint 10.11.0, stylelint 17.15.0 |": f" **{T}:** with `UV_THREADPOOL_SIZE=1` both are past it: eslint FAIL, stylelint PASS (the first table)",
    "| Python CLIs that start a thread at the entry point | beets |": f" **{T}:** with `threaded: no` in its config it is past the wall, and with `library.db` scratch PASSes (the first table)",
    "| Compressors with a worker pool | zstd 1.5.x, lz4 1.10.0 |": f" **{T}:** zstd is past it with `--single-thread --no-asyncio` (its I/O thread is the second writer) and PASSes with a checker; lz4 with `-T1` is not",
    "| Unordered writer threads | dotenvx 2.32.4, Electrum 4.8.2": f" **{T}:** with one libuv thread or `GOMAXPROCS=1`, dotenvx, bibtex-tidy and doctl are past it and FAIL — dotenvx filed (the first table); OpenTofu is not",
    "| Unordered writer threads | basic-memory 0.23.2, gemini-cli 0.62.0": f" **{T}:** glTF-Transform is past it with one libuv thread and FAILs; lingui meets a child instead; gemini-cli, vercel, steamguard and codex are not past it",
    "| Unordered writer threads | rustic 0.11.4, prek 0.5.5, cspell 10.3.6 and capacitor 8.5.2 |": f" **{T}:** cspell and capacitor are past it with one libuv thread and FAIL (the first table); rustic and prek are not",
    "| Unordered writer threads (Node 20) | yarn 4.18.1 `config set`": f" **{T}:** with `UV_THREADPOOL_SIZE=1` both are past it: yarn FAIL, trash-cli PASS (the first table)",
    "| Bytes that differ between two runs | monero-wallet-cli 0.18.5.1": f" **{T}:** infracost with `GOMAXPROCS=1` is past the threads too, and FAILs (the first table)",
    "| Bytes that differ between two runs | espsecure (esptool 5.4.0)": f" **{T}:** plakar with `GOMAXPROCS=1` is past the threads too, and PASSes (the first table)",
}
N1 = "one libuv thread (`UV_THREADPOOL_SIZE=1`)"
def fail(cls, tool, res, why):
    return f"| {cls} | {tool} | **FAIL** {res}. {why} | {REC} |"
def ok(cls, tool, res):
    return f"| {cls} | {tool} | **PASS** {res} | {REC} |"
verdicts = [
    fail(f"Encrypted dotenv file rewritten in place (Node, {N1}, the two files scratch, `dotenvx get` as checker)", DX_TOOL, "1/5 explored worlds — `.env` emptied after `.env.keys` is written: the values gone", "Replayed twice; reproduced without Sideeye. Reported upstream as dotenvx/dotenvx#1012 <!-- upstream-report: dotenvx/dotenvx#1012 -->"),
    fail(f"Package manager's user config (Node, {N1})", "yarn 4.18.1 `config set`", "1/3 — `.yarnrc.yml` truncated before its write", "Not filed: a setting"),
    ok(f"File moved to the trash (Node, {N1})", "sindresorhus's trash-cli 7.2.0 `trash`", "9/9"),
    fail(f"Bibliography tidied in place (Node, {N1})", "bibtex-tidy 1.15.1", "1/3 — `refs.bib`", "Not filed: under version control"),
    fail(f"3D model rewritten onto its input (Node, {N1})", "glTF-Transform 4.5.1 `weld`", "1/3 — `terrain.glb`", "Not filed: in place only when the output names the input"),
    fail(f"Spell checker's settings (Node 22, {N1})", "cspell 10.3.6 `link add`", "1/4 — `cspell.json`", "Not filed: a setting"),
    fail(f"Mobile toolkit's telemetry setting (Node 22, {N1})", "capacitor 8.5.2 `telemetry off`", "1/4 — `sysconfig.json`", "Not filed: a setting"),
    fail(f"Linter fixing in place (Node, {N1})", "eslint 10.11.0 `--fix`", "1/3 — `a.js`", "Not filed: under version control"),
    fail(f"Formatter writing in place (Node, {N1})", "prettier 3.9.7 `--write`", "1/3 — `a.js`", "Not filed: under version control"),
    ok(f"Style linter fixing in place (Node, {N1})", "stylelint 17.15.0 `--fix`", "6/6"),
    fail(f"SVG optimised in place (Node, {N1})", "svgo 4.1.0", "1/4 — `a.svg`", "Not filed: under version control"),
    fail(f"Package manifest edited (Node, {N1})", "npm 9.2.0 `pkg set`", "1/3 — `package.json`", "Not filed: under version control"),
    ok(f"Notes added (Node, {N1}, the database, log and `tmp` scratch, `joplin ls` as checker)", "joplin 3.7.1 `mknote`", "49/49"),
    fail("Cloud CLI's auth config (static Go, `--observe supervised`, `GOMAXPROCS=1`)", "doctl 1.177.0", "1/3 — `config.yaml`", "Not filed: a token re-issued"),
    fail("Cost estimator's credentials (static Go, `--observe supervised`, `GOMAXPROCS=1`, `.state.json` scratch)", "infracost 0.10.46 `configure set`", "1/5 — `credentials.yml`", "Not filed: a key re-issued"),
    ok("Backup repository pruned (static Go, `--observe supervised`, `GOMAXPROCS=1`, the state files scratch, plakar as checker)", "plakar 1.1.7 `rm -apply`", "6/6"),
    ok("Compressor replacing its input (`--single-thread --no-asyncio`, a checker on the data)", "zstd 1.5.7 `--rm`", "8/8 under `--observe syscalls`"),
    ok("Music library import (Python, `threaded: no`, `library.db` scratch)", "beets 2.1.0 `import`", "43/43"),
    fail("Wiki page saved (PHP)", "DokuWiki 2026-07-14c", "5/31 — `start.txt` truncated before its write", "Not filed: its tracker's #677"),
    ok("Ethereum validator definitions (Rust)", "Lighthouse 8.2.3", "8/8"),
    ok("Directory jumper's scores (static Go, `--observe supervised`)", "jump 0.69.0", "13/13"),
    fail("Plaintext keyring backend (Python)", "keyring 25.7.0 with keyrings.alt 5.0.2", "1/3 — `keyring_pass.cfg`", "Not filed: the write is keyrings.alt's (29 stars)"),
    ok("Git LFS hooks and config (Go)", "git-lfs 3.8.0 `install`", "18/18"),
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
k = i + 1
while not lines[k].startswith("|"):
    k += 1
while k < len(lines) and lines[k].startswith("|"):
    k += 1
lines[k:k] = verdicts
p.write_text("\n".join(lines))
print(len(funnel), "funnel rows,", len(add), "rows amended,", len(verdicts), "verdict rows")
