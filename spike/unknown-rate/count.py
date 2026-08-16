#!/usr/bin/env python3
"""Recompute the #84 UNKNOWN-rate tables from the committed artifacts.

Two modes:

  count.py emit  [--root DIR]   print the canonical results block (markdown)
  count.py check [--root DIR]   exit non-zero unless the checked-out docs,
                                corpus, manifest, reports and define bytes
                                all agree

The published numbers in docs/unknown-rate.md are pasted from `emit` and
held there by `check` (wired into spike/acceptance.sh): the block between
the begin/end markers must equal a fresh recomputation byte for byte, so a
number cannot drift from the reports it claims to summarize. `check` also
recomputes every manifest define digest from the checkout — "the committed
defines ran verbatim" is checked, not asserted — and requires every
unknown_reason to be a member of the closed set documented in
docs/report-schema.md (the docs hold each other).

Pre-data state (the apparatus PR): artifacts/ does not exist yet; `check`
then requires the docs to carry the literal placeholder line instead of
results — an empty table can never read as a measured zero.

The counting rules are frozen in docs/unknown-rate.md; this file is their
implementation. Cells with n < 5 print counts only, never a percentage.
"""
import json
import re
import sys
from pathlib import Path

MARK_BEGIN = "<!-- unknown-rate:results:begin -->"
MARK_END = "<!-- unknown-rate:results:end -->"
PLACEHOLDER = "_Not yet measured: the sweep has not run. This line is asserted by count.py check._"
SMALL_N = 5

def die(msg):
    print(f"count.py: {msg}", file=sys.stderr)
    sys.exit(1)

def pct_or_counts(k, n):
    if n == 0:
        return f"{k}/{n}"
    if n < SMALL_N:
        return f"{k}/{n} (counts only, n<{SMALL_N})"
    return f"{k}/{n} ({100.0 * k / n:.1f}%)"

def read_corpus(root):
    rows = []
    for line in (root / "spike/unknown-rate/corpus.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != 10:
            die(f"corpus.tsv row does not have 10 columns: {line!r}")
        rows.append(dict(zip(
            ["id", "group", "tool", "cls", "judge", "launcher", "args",
             "artdir", "rpath", "defines"], f)))
    return rows

def read_manifest(root):
    p = root / "spike/unknown-rate/artifacts/manifest.tsv"
    if not p.exists():
        return None
    rows = []
    for line in p.read_text().splitlines():
        f = line.split("\t")
        if len(f) != 10:
            die(f"manifest.tsv row does not have 10 columns: {line!r}")
        rows.append(dict(zip(
            ["id", "group", "tool", "cls", "judge", "image", "argv",
             "digest", "rpath", "rc"], f)))
    return rows

def enum_from_schema_doc(root):
    text = (root / "docs/report-schema.md").read_text()
    m = re.search(r"`unknown_reason` values \(closed set[^)]*\):(.*?)\n\n",
                  text, re.S)
    if not m:
        die("could not find the unknown_reason closed set in docs/report-schema.md")
    return set(re.findall(r"`([a-z0-9_]+)`", m.group(1)))

def sha256_file(p):
    import hashlib
    h = hashlib.sha256()
    h.update(p.read_bytes())
    return h.hexdigest()

_digest_cache = {}

def digest_for(root, defines):
    # Mirror of sweep.sh digest_for: sorted "sha256  path" lines, hashed.
    # Memoized: several corpus rows share one defines directory (topydo's
    # thirteen trials hash the same ops/ tree).
    if defines in _digest_cache:
        return _digest_cache[defines]
    import hashlib
    lines = []
    for spec in defines.split(";"):
        p = root / spec
        if not p.exists():
            die(f"define path missing from checkout: {spec}")
        files = sorted(q for q in p.rglob("*") if q.is_file()) if p.is_dir() else [p]
        for q in files:
            lines.append(f"{sha256_file(q)}  {q.relative_to(root)}")
    payload = "\n".join(sorted(lines)) + "\n"
    d = hashlib.sha256(payload.encode()).hexdigest()
    _digest_cache[defines] = d
    return d

def load_reports(root, manifest):
    """Attach verdict data to every non-wall manifest row."""
    out = {}
    arts = root / "spike/unknown-rate/artifacts"
    for row in manifest:
        if row["argv"].startswith("wall:"):
            out[row["id"]] = {"wall": row["argv"][5:]}
            continue
        rp = arts / row["rpath"]
        if not rp.exists():
            die(f"report missing for {row['id']}: {row['rpath']}")
        doc = json.loads(rp.read_text())
        if doc.get("schema") != "sideeye/report":
            die(f"{row['id']}: not a sideeye/report document")
        out[row["id"]] = {
            "verdict": doc["verdict"],
            "reason": doc.get("unknown_reason", ""),
            "crash_points": doc.get("crash_points"),
        }
    return out

def read_outcome_map(root):
    m = {}
    p = root / "spike/unknown-rate/outcome-map.tsv"
    for line in p.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        tool, disposition = line.split("\t")
        m[tool] = disposition
    return m

def rate_line(label, trials, verdict="UNKNOWN"):
    n = len(trials)
    k = sum(1 for t in trials if t["v"] == verdict)
    return f"| {label} | {pct_or_counts(k, n)} |"

def emit(root):
    corpus = read_corpus(root)
    manifest = read_manifest(root)
    if manifest is None:
        return PLACEHOLDER + "\n"
    reports = load_reports(root, manifest)
    outcome = read_outcome_map(root)

    # Flatten to judged trials (walls and SETUP_ERROR are listed, not rated).
    trials = []
    walls = []
    setup_errors = []
    for row in manifest:
        r = reports[row["id"]]
        base = {"id": row["id"], "group": row["group"], "tool": row["tool"],
                "cls": row["cls"], "judge": row["judge"]}
        if "wall" in r:
            walls.append({**base, "wall": r["wall"]})
        elif r["verdict"] == "SETUP_ERROR":
            setup_errors.append(base)
        else:
            trials.append({**base, "v": r["verdict"], "reason": r["reason"],
                           "cp0": r["verdict"] == "PASS" and r["crash_points"] == 0})

    L = []
    L.append(MARK_BEGIN)
    L.append("_Generated by `spike/unknown-rate/count.py emit` — do not edit between the markers._")
    for group, gname in (("A", "A-group (the engine's development input — not the threshold basis)"),
                         ("control", "Control trials (outside every denominator)"),
                         ("B", "B-group (mechanically selected; the threshold basis)")):
        g = [t for t in trials if t["group"] == group]
        L.append("")
        L.append(f"#### {gname}")
        if group == "B":
            L.append("")
            L.append("| target | class | funnel stage | verdict | unknown_reason |")
            L.append("|---|---|---|---|---|")
            for w in [w for w in walls if w["group"] == "B"]:
                L.append(f"| {w['tool']} | {w['cls']} | wall {w['wall']} | - | - |")
            for t in g:
                flag = " (0 crash points)" if t["cp0"] else ""
                L.append(f"| {t['tool']} | {t['cls']} | explored | {t['v']}{flag} | {t['reason'] or '-'} |")
            for s in [s for s in setup_errors if s["group"] == "B"]:
                L.append(f"| {s['tool']} | {s['cls']} | SETUP_ERROR (excluded, published) | - | - |")
        else:
            L.append("")
            L.append("| trial | tool | class | judge | verdict | unknown_reason |")
            L.append("|---|---|---|---|---|---|")
            for t in g:
                flag = " (0 crash points)" if t["cp0"] else ""
                L.append(f"| {t['id']} | {t['tool']} | {t['cls']} | {t['judge']} | {t['v']}{flag} | {t['reason'] or '-'} |")
            for s in [s for s in setup_errors if s["group"] == group]:
                L.append(f"| {s['id']} | {s['tool']} | {s['cls']} | {s['judge']} | SETUP_ERROR (excluded, published) | - |")
        if not g:
            continue
        L.append("")
        L.append(f"UNKNOWN rate, per-trial: **{pct_or_counts(sum(1 for t in g if t['v']=='UNKNOWN'), len(g))}**")
        L.append("")
        L.append("| slice | UNKNOWN |")
        L.append("|---|---|")
        for tool in sorted({t["tool"] for t in g}):
            L.append(rate_line(f"tool: {tool}", [t for t in g if t["tool"] == tool]))
        for cls in sorted({t["cls"] for t in g}):
            L.append(rate_line(f"class: {cls}", [t for t in g if t["cls"] == cls]))
        for judge in sorted({t["judge"] for t in g}):
            L.append(rate_line(f"judge: {judge}", [t for t in g if t["judge"] == judge]))
        reasons = sorted({t["reason"] for t in g if t["v"] == "UNKNOWN"})
        if reasons:
            L.append("")
            L.append("| unknown_reason | count |")
            L.append("|---|---|")
            for r in reasons:
                L.append(f"| {r} | {sum(1 for t in g if t['reason'] == r)} |")

    L.append("")
    L.append("#### Outcome ratio (A-group, per the committed disposition map)")
    L.append("")
    L.append("| outcome | count |")
    L.append("|---|---|")
    ga = [t for t in trials if t["group"] == "A"]
    fails = [t for t in ga if t["v"] == "FAIL"]
    for d in ("reported-upstream", "withdrawn", "kept-unreported", "new-this-sweep"):
        k = sum(1 for t in fails if outcome.get(t["tool"], "new-this-sweep") == d)
        L.append(f"| FAIL, {d} | {k} |")
    L.append(f"| UNKNOWN | {sum(1 for t in ga if t['v'] == 'UNKNOWN')} |")
    L.append(f"| PASS | {sum(1 for t in ga if t['v'] == 'PASS')} |")

    L.append("")
    L.append("#### macOS column (derived, not measured)")
    L.append("")
    L.append("Formula (mechanism: `requireCompleteness`, src/main.zig — no oracle exists on macOS,")
    L.append("so every strict PASS becomes `completeness_not_verified`; a FAIL stands on its own")
    L.append("evidence and is unchanged; a Linux UNKNOWN is not re-derived):")
    for group in ("A", "B"):
        g = [t for t in trials if t["group"] == group]
        if not g:
            continue
        k = sum(1 for t in g if t["v"] in ("UNKNOWN", "PASS"))
        L.append(f"- {group}-group derived UNKNOWN rate on macOS: {pct_or_counts(k, len(g))}")
    L.append(MARK_END)
    return "\n".join(L) + "\n"

def check(root):
    corpus = read_corpus(root)
    manifest = read_manifest(root)
    docs = (root / "docs/unknown-rate.md").read_text()
    block = emit(root)

    # The B-group rows must be exactly the committed mechanical selection,
    # order included — "no hand touched the list" is checked, not narrated.
    # This binds pre-data too: the apparatus PR is where a hand-edit would
    # first try to slip in.
    def read_lines(rel):
        p = root / rel
        if not p.exists():
            die(f"{rel} is missing — the selection chain cannot be checked")
        return p.read_text().splitlines()

    bt = [l for l in read_lines("spike/unknown-rate/b-targets.txt") if l]
    bc = [c["tool"] for c in corpus if c["group"] == "B"]
    if bc != bt:
        die("corpus B rows differ from the committed b-targets.txt selection (order included)")
    # And the selection itself must still be the mechanical derivation:
    # first N of (candidates minus exclusions). Without this, editing
    # b-targets.txt and the corpus together would keep everything
    # "consistent" (R2 measured that pair-edit passing).
    cands = [l for l in read_lines("spike/unknown-rate/b-candidates.txt") if l]
    excl = set()
    for line in read_lines("spike/unknown-rate/b-exclusions.txt"):
        if line and not line.startswith("#"):
            excl.add(line.split("\t")[0])
    derived = [c for c in cands if c not in excl][:len(bt)]
    if derived != bt:
        die("b-targets.txt is not the first-N derivation of b-candidates.txt minus b-exclusions.txt")

    if manifest is None:
        if PLACEHOLDER not in docs:
            die("no artifacts, and docs/unknown-rate.md lacks the not-yet-measured placeholder")
        print("count.py check: pre-data state — placeholder asserted, corpus parsed "
              f"({len(corpus)} rows)")
        return

    if len(manifest) != len(corpus):
        die(f"manifest rows ({len(manifest)}) != corpus rows ({len(corpus)})")
    ids_c = [c["id"] for c in corpus]
    ids_m = [m["id"] for m in manifest]
    if ids_c != ids_m:
        die("manifest trial ids differ from corpus (order included)")

    # The published tables are built from MANIFEST columns; hold every
    # classifying column to the frozen corpus, or a re-labeled manifest row
    # (a trial moved between groups, an UNKNOWN re-filed as a funnel wall)
    # would flow into the tables with the docs regenerated to match — R1
    # measured exactly that passing the byte-compare alone.
    by_id_c = {c["id"]: c for c in corpus}
    for row in manifest:
        c = by_id_c[row["id"]]
        for k in ("group", "tool", "cls", "judge"):
            if row[k] != c[k]:
                die(f"{row['id']}: manifest {k} {row[k]!r} differs from the frozen corpus {c[k]!r}")
        wall_m = row["argv"].startswith("wall:")
        wall_c = c["launcher"] == "-"
        if wall_m != wall_c:
            die(f"{row['id']}: wall-ness differs between manifest and corpus")
        if wall_c and row["argv"] != f"wall:{c['args']}":
            die(f"{row['id']}: wall reason {row['argv']!r} differs from corpus {c['args']!r}")
        if not wall_c:
            # The report path decides WHICH report speaks for the trial; an
            # unbound rpath lets verdicts swap between trials with every
            # classifying column intact (R2 measured the B-group rate
            # flipping 1/1 -> 0/1 that way). The argv binding closes the
            # same door for the record's invocation column.
            if row["rpath"] != f"{c['artdir']}/{c['rpath']}":
                die(f"{row['id']}: manifest report path {row['rpath']!r} differs from the frozen corpus")
            if row["argv"] != f"{c['launcher']} {c['args']}":
                die(f"{row['id']}: manifest argv {row['argv']!r} differs from the frozen corpus")

    enum = enum_from_schema_doc(root)
    reports = load_reports(root, manifest)
    for row in manifest:
        r = reports[row["id"]]
        if "wall" not in r and r["verdict"] == "UNKNOWN" and r["reason"] not in enum:
            die(f"{row['id']}: unknown_reason {r['reason']!r} not in the documented closed set")

    by_id = {c["id"]: c for c in corpus}
    for row in manifest:
        want = digest_for(root, by_id[row["id"]]["defines"])
        if want != row["digest"]:
            die(f"{row['id']}: define digest mismatch — the defines in the checkout are "
                f"not the bytes the sweep hashed")

    if MARK_BEGIN not in docs or MARK_END not in docs:
        die("docs/unknown-rate.md lacks the results markers")
    published = docs.split(MARK_BEGIN)[1].split(MARK_END)[0]
    # Row-count first, on the PUBLISHED side: after the byte-compare passes
    # this could never fire (the recomputation always emits one row per
    # manifest row — R1 proved the original order unreachable), so the
    # empty-table guard has to look at the docs before trusting them.
    pub_rows = [l for l in published.splitlines() if l.startswith("| ")]
    if len(pub_rows) < len(corpus):
        die(f"published tables carry {len(pub_rows)} rows for {len(corpus)} corpus trials — "
            f"an empty or truncated table cannot stand in for the measurement")
    computed = block.split(MARK_BEGIN)[1].split(MARK_END)[0]
    if published != computed:
        die("published results block differs from recomputation (drift)")
    print(f"count.py check: OK — {len(corpus)} trials, digests verified, docs in sync")

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("emit", "check"):
        die("usage: count.py emit|check [--root DIR]")
    root = Path(".")
    if "--root" in sys.argv:
        root = Path(sys.argv[sys.argv.index("--root") + 1])
    if not (root / "spike/unknown-rate/corpus.tsv").exists():
        die(f"--root {root} does not look like the repo (no corpus.tsv)")
    if sys.argv[1] == "emit":
        sys.stdout.write(emit(root))
    else:
        check(root)

if __name__ == "__main__":
    main()
