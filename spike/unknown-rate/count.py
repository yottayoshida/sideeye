#!/usr/bin/env python3
"""Recompute the #84 UNKNOWN-rate tables from the committed artifacts.

Two modes:

  count.py emit  [--root DIR]   print the canonical results block (markdown)
  count.py check [--root DIR]   exit non-zero unless the checked-out docs,
                                corpus, ledgers, manifests, reports and
                                define bytes all agree

The published numbers in docs/unknown-rate.md are pasted from `emit` and
held there by `check` (wired into spike/acceptance.sh): the block between
the begin/end markers must equal a fresh recomputation byte for byte, so a
number cannot drift from the reports it claims to summarize. `check` also
recomputes every manifest define digest from the checkout — "the committed
defines ran verbatim" is checked, not asserted — and requires every
unknown_reason to be a member of the closed set documented in
docs/report-schema.md (the docs hold each other).

Generations (#239). A generation is one sweep: one engine build, one
artifacts directory, listed in generations.tsv. Corpus rows carry the
generation they enter from, so a generation's expected trial set is every
row with since <= it in a group it covers. A generation is `complete` (its
manifest matches that set exactly) or `unstarted` (no manifest, and the
docs carry the placeholder). Anything between the two is a partially
measured sweep, which is an error rather than a state that can be recorded
— `partial` is not a value generations.tsv accepts, so a half-finished
sweep cannot be published by writing it down. This is what lets a rulebook
PR add corpus rows for a generation that has not run: the completed
generation's expected set does not include them.

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
CORPUS_COLS = ["id", "group", "tool", "cls", "judge", "launcher", "args",
               "artdir", "rpath", "defines", "since", "flags"]
GEN_COLS = ["id", "date", "dir", "groups", "status"]
GEN_STATUSES = ("complete", "unstarted")
GROUPS = ("A", "B", "control")
OUTCOME_COLS = ["tool", "disposition", "source"]
# The four the outcome table prints, plus one for a tool the record carries
# no FAIL for. A tool marked no-fail-recorded that then produces a FAIL is
# caught by the conservation check in check(), not by this list.
PRINTED_DISPOSITIONS = ("reported-upstream", "withdrawn", "kept-unreported", "new-this-sweep")
DISPOSITIONS = PRINTED_DISPOSITIONS + ("no-fail-recorded",)
COHORT_PREFIX = "spike/cohort"
# A cohort target directory is <target> or <target>-rN with N >= 2: the first
# revision carries no suffix. The bounds are fail-closed on purpose — a
# permissive pattern read "-r2" as base "" revision 2 and "foo-r0" as base
# "foo" revision 0, either of which satisfies the supersession predicate for
# a pair that is not a revision chain at all.
REVISION_RE = re.compile(r"^(?P<base>[A-Za-z0-9][A-Za-z0-9._-]*?)(?:-r(?P<rev>[2-9][0-9]*))?$")

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
        if len(f) != len(CORPUS_COLS):
            die(f"corpus.tsv row does not have {len(CORPUS_COLS)} columns: {line!r}")
        rows.append(dict(zip(CORPUS_COLS, f)))
    return rows

def read_generations(root):
    rows = []
    for line in (root / "spike/unknown-rate/generations.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(GEN_COLS):
            die(f"generations.tsv row does not have {len(GEN_COLS)} columns: {line!r}")
        g = dict(zip(GEN_COLS, f))
        if g["status"] not in GEN_STATUSES:
            die(f"generation {g['id']}: status {g['status']!r} is not one of "
                f"{'/'.join(GEN_STATUSES)} — a partially measured sweep is an error, "
                f"not a status to record")
        # An unrecognised group name silently covers nothing, which removes
        # every row in that group from every expected set — the corpus rows
        # are then measured by no generation and missed by every check.
        for grp in g["groups"].split(","):
            if grp not in GROUPS:
                die(f"generation {g['id']}: group {grp!r} is not one of {'/'.join(GROUPS)}")
        rows.append(g)
    if not rows:
        die("generations.tsv lists no generations")
    return rows

def expected_for(corpus, generations, gen):
    """The trial rows a generation is responsible for, in corpus order."""
    order = {g["id"]: i for i, g in enumerate(generations)}
    limit = order[gen["id"]]
    groups = set(gen["groups"].split(","))
    out = []
    for c in corpus:
        if c["since"] not in order:
            die(f"corpus row {c['id']}: since={c['since']!r} is not a generation")
        if order[c["since"]] <= limit and c["group"] in groups:
            out.append(c)
    return out

def read_manifest(root, gen_dir):
    p = root / "spike/unknown-rate" / gen_dir / "manifest.tsv"
    if not p.exists():
        return None
    rows = []
    for line in p.read_text().splitlines():
        f = line.split("\t")
        if len(f) != 10:
            die(f"{gen_dir}/manifest.tsv row does not have 10 columns: {line!r}")
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

def load_reports(root, gen_dir, manifest):
    """Attach verdict data to every non-wall manifest row.

    The reports are read from THIS generation's directory. Reading them from
    another one would attach a previous sweep's verdicts to this sweep's
    rows with every classifying column intact.
    """
    out = {}
    arts = root / "spike/unknown-rate" / gen_dir
    for row in manifest:
        if row["argv"].startswith("wall:"):
            out[row["id"]] = {"wall": row["argv"][5:]}
            continue
        rp = arts / row["rpath"]
        if not rp.exists():
            die(f"report missing for {row['id']} in {gen_dir}: {row['rpath']}")
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
    """tool -> disposition, with the shape held rather than assumed.

    Every loosening here is silent in the published table: a row short of
    its source column loses the provenance the disposition rests on, a
    duplicate tool lets the later row win with nothing said, and a
    misspelt disposition matches none of the four printed outcome rows —
    so that tool's FAILs leave the ratio without leaving a trace.
    """
    m = {}
    p = root / "spike/unknown-rate/outcome-map.tsv"
    for line in p.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(OUTCOME_COLS):
            die(f"outcome-map.tsv row does not have {len(OUTCOME_COLS)} columns "
                f"({', '.join(OUTCOME_COLS)}): {line!r}")
        if f[0] in m:
            die(f"outcome-map.tsv lists {f[0]!r} twice — the later row would win in silence")
        if f[1] not in DISPOSITIONS:
            die(f"outcome-map.tsv: disposition {f[1]!r} for {f[0]} is not one of "
                f"{'/'.join(DISPOSITIONS)}")
        m[f[0]] = f[1]
    return m

def read_ledger(root, name, cols):
    """A tab-separated ledger with a comment header; first column is the key."""
    rows = []
    for line in (root / "spike/unknown-rate" / name).read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(cols):
            die(f"{name} row does not have {len(cols)} columns: {line!r}")
        rows.append(dict(zip(cols, f)))
    return rows

def split_revision(define):
    """spike/cohortN/<target>[-rM]/ops -> (cohortN, base target, revision).

    An unsuffixed directory is revision 1: cohort 2's chain is hg, hg-r2,
    hg-r3, hg-r4, and the first one carries no suffix.
    """
    parts = define.split("/")
    if (len(parts) != 4 or parts[0] != "spike"
            or not parts[1].startswith("cohort") or parts[3] != "ops"):
        die(f"not a cohort define path (want spike/cohortN/<target>/ops): {define!r}")
    m = REVISION_RE.match(parts[2])
    if not m:
        die(f"cohort target directory {parts[2]!r} is not <target> or <target>-rN with N >= 2")
    return parts[1], m.group("base"), int(m.group("rev") or 1)

def cohort_defines_on_disk(root):
    """Every committed cohort define directory, as repo-relative paths."""
    out = set()
    for toml in sorted((root / "spike").glob("cohort*/*/ops/*.toml")):
        out.add(str(toml.parent.relative_to(root)))
    return out

def rate_line(label, trials, verdict="UNKNOWN"):
    n = len(trials)
    k = sum(1 for t in trials if t["v"] == verdict)
    return f"| {label} | {pct_or_counts(k, n)} |"

def tabulate(manifest, reports, by_id):
    """Split a generation's manifest into rated trials, walls and setup errors.

    Returned separately from the rendering so `check` can assert what
    reaches the arithmetic rather than what reaches the table — a flagged
    row that a renderer prints and an aggregation skips would look right in
    both places otherwise.
    """
    trials, walls, setup_errors = [], [], []
    for row in manifest:
        r = reports[row["id"]]
        c = by_id[row["id"]]
        base = {"id": row["id"], "group": row["group"], "tool": row["tool"],
                "cls": row["cls"], "judge": row["judge"], "flags": c["flags"]}
        if "wall" in r:
            walls.append({**base, "wall": r["wall"]})
        elif r["verdict"] == "SETUP_ERROR":
            setup_errors.append(base)
        else:
            trials.append({**base, "v": r["verdict"], "reason": r["reason"],
                           "cp0": r["verdict"] == "PASS" and r["crash_points"] == 0})
    return trials, walls, setup_errors

def emit_generation(gen, trials, walls, setup_errors, outcome):
    L = []
    L.append("")
    L.append(f"### Generation {gen['id']} — measured {gen['date']} ({gen['groups']})")
    for group, gname in (("A", "A-group (the engine's development input — not the threshold basis)"),
                         ("control", "Control trials (outside every denominator)"),
                         ("B", "B-group (mechanically selected; the threshold basis)")):
        g = [t for t in trials if t["group"] == group]
        gw = [w for w in walls if w["group"] == group]
        gs = [s for s in setup_errors if s["group"] == group]
        if not g and not gw and not gs:
            continue
        L.append("")
        L.append(f"#### {gname}")
        if group == "B":
            L.append("")
            L.append("| target | class | funnel stage | verdict | unknown_reason |")
            L.append("|---|---|---|---|---|")
            for w in gw:
                L.append(f"| {w['tool']} | {w['cls']} | wall {w['wall']} | - | - |")
            for t in g:
                flag = " (0 crash points)" if t["cp0"] else ""
                L.append(f"| {t['tool']} | {t['cls']} | explored | {t['v']}{flag} | {t['reason'] or '-'} |")
            for s in gs:
                L.append(f"| {s['tool']} | {s['cls']} | SETUP_ERROR (excluded, published) | - | - |")
        else:
            L.append("")
            L.append("| trial | tool | class | judge | verdict | unknown_reason | flags |")
            L.append("|---|---|---|---|---|---|---|")
            for t in g:
                flag = " (0 crash points)" if t["cp0"] else ""
                L.append(f"| {t['id']} | {t['tool']} | {t['cls']} | {t['judge']} | "
                         f"{t['v']}{flag} | {t['reason'] or '-'} | {t['flags']} |")
            for s in gs:
                L.append(f"| {s['id']} | {s['tool']} | {s['cls']} | {s['judge']} | "
                         f"SETUP_ERROR (excluded, published) | - | {s['flags']} |")
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

    ga = [t for t in trials if t["group"] == "A"]
    if ga:
        L.append("")
        L.append("#### Outcome ratio (A-group, per the committed disposition map)")
        L.append("")
        L.append("| outcome | count |")
        L.append("|---|---|")
        fails = [t for t in ga if t["v"] == "FAIL"]
        for d in PRINTED_DISPOSITIONS:
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
    return L

def generation_tables(root):
    """Per generation: (gen, expected, manifest, trials, walls, setup_errors).

    Shared by emit and check so the two cannot disagree about what a
    generation measured.
    """
    corpus = read_corpus(root)
    generations = read_generations(root)
    by_id = {c["id"]: c for c in corpus}
    out = []
    for gen in generations:
        exp = expected_for(corpus, generations, gen)
        man = read_manifest(root, gen["dir"])
        # Reports are read only for a generation that claims to be complete.
        # Reading them for one recorded as unstarted would die on a missing
        # report — true, but about the wrong thing: the defect there is the
        # status, and a check that reports "report missing" for it is red for
        # a reason nobody asked about (measured while building the fixture
        # for exactly that case).
        if man is None or gen["status"] != "complete":
            out.append((gen, exp, man, [], [], []))
            continue
        reports = load_reports(root, gen["dir"], man)
        trials, walls, setup_errors = tabulate(man, reports, by_id)
        out.append((gen, exp, man, trials, walls, setup_errors))
    return corpus, generations, out

def emit(root):
    corpus, generations, tables = generation_tables(root)
    outcome = read_outcome_map(root)
    L = [MARK_BEGIN,
         "_Generated by `spike/unknown-rate/count.py emit` — do not edit between the markers._"]
    for gen, exp, man, trials, walls, setup_errors in tables:
        if man is None:
            L.append("")
            L.append(f"### Generation {gen['id']} — not yet measured ({gen['groups']})")
            L.append("")
            L.append(PLACEHOLDER)
            continue
        L.extend(emit_generation(gen, trials, walls, setup_errors, outcome))
    L.append(MARK_END)
    return "\n".join(L) + "\n"

def check_ledgers(root, corpus):
    """The three cohort ledgers partition the committed cohort defines."""
    sup = read_ledger(root, "supersession.tsv", ["predecessor", "successor", "reason"])
    exc = read_ledger(root, "class-exclusions.tsv", ["define", "row", "reason"])

    in_corpus = {c["defines"] for c in corpus if c["defines"].startswith(COHORT_PREFIX)}
    in_sup = {r["predecessor"] for r in sup}
    in_exc = {r["define"] for r in exc}

    for a, b, na, nb in ((in_corpus, in_sup, "corpus.tsv", "supersession.tsv"),
                         (in_corpus, in_exc, "corpus.tsv", "class-exclusions.tsv"),
                         (in_sup, in_exc, "supersession.tsv", "class-exclusions.tsv")):
        both = a & b
        if both:
            die(f"{na} and {nb} both claim {sorted(both)} — the ledgers must be disjoint")

    on_disk = cohort_defines_on_disk(root)
    union = in_corpus | in_sup | in_exc
    missing = on_disk - union
    if missing:
        die(f"committed cohort defines in no ledger: {sorted(missing)} — every one must be "
            f"measured, superseded or excluded by class, and silence is not one of those")
    extra = union - on_disk
    if extra:
        die(f"ledgers name defines that are not on disk: {sorted(extra)}")

    # A supersession row's whole claim is narrow: a LATER REVISION OF THE
    # SAME TARGET replaced this define, and that revision is measured.
    # Checking only "the successor is some corpus define" leaves the file a
    # place to park anything — measured, with hg's successor rewritten to
    # borg-r3 and the check still green. All three parts are held here.
    for r in sup:
        if r["successor"] not in in_corpus:
            die(f"supersession.tsv: {r['predecessor']} names successor {r['successor']}, "
                f"which is not a corpus define — a superseded row must be replaced by a "
                f"measured one")
        pc, pb, pr = split_revision(r["predecessor"])
        sc, sb, sr = split_revision(r["successor"])
        if (pc, pb) != (sc, sb):
            die(f"supersession.tsv: {r['predecessor']} names successor {r['successor']}, "
                f"which is a different target ({pc}/{pb} vs {sc}/{sb}) — this file records "
                f"revisions of one target replacing each other, not arbitrary exclusions")
        if sr <= pr:
            die(f"supersession.tsv: {r['predecessor']} (revision {pr}) names successor "
                f"{r['successor']} (revision {sr}), which is not later — a define is not "
                f"superseded by one that came before it")

def check_dispositions(root, corpus, outcome):
    """Cohort tools are triaged from the record, not parked as new."""
    tools = sorted({c["tool"] for c in corpus if c["defines"].startswith(COHORT_PREFIX)})
    for t in tools:
        if t not in outcome:
            die(f"outcome-map.tsv has no row for {t} — a corpus tool with no disposition "
                f"falls through to new-this-sweep by default, which is indistinguishable "
                f"from an untriaged finding")
        if outcome[t] == "new-this-sweep":
            die(f"outcome-map.tsv records {t} as new-this-sweep, but its verdicts predate "
                f"this sweep and docs/target-classes.md states their disposition — "
                f"declaring an already-triaged tool untriaged satisfies the map without "
                f"carrying its meaning")

def check(root):
    corpus, generations, tables = generation_tables(root)
    outcome = read_outcome_map(root)
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

    check_ledgers(root, corpus)
    check_dispositions(root, corpus, outcome)

    # Every corpus row must be inside some generation's expected set. A row
    # whose entering generation does not cover its group belongs to no
    # generation at all: it is measured by nothing, and every completeness
    # check passes over it. Narrowing a generation's groups is enough to do
    # that to eight rows at once.
    by_gen = {g["id"]: g for g in generations}
    for c in corpus:
        if c["since"] not in by_gen:
            die(f"corpus row {c['id']}: since={c['since']!r} is not a generation")
        cover = by_gen[c["since"]]["groups"].split(",")
        if c["group"] not in cover:
            die(f"corpus row {c['id']} is in group {c['group']} but enters at generation "
                f"{c['since']}, which covers {'/'.join(cover)} — a row no generation covers "
                f"is measured by nothing and missed by every completeness check")

    enum = enum_from_schema_doc(root)
    by_id_c = {c["id"]: c for c in corpus}
    measured = 0

    for gen, exp, manifest, trials, walls, setup_errors in tables:
        gid = gen["id"]
        if gen["status"] == "unstarted":
            if manifest is not None:
                die(f"generation {gid} is marked unstarted but {gen['dir']}/manifest.tsv "
                    f"exists — a sweep that ran is not unstarted")
            continue
        # status is complete (read_generations rejects anything else)
        if manifest is None:
            die(f"generation {gid} is marked complete but has no manifest at "
                f"{gen['dir']}/manifest.tsv")
        ids_e = [c["id"] for c in exp]
        ids_m = [m["id"] for m in manifest]
        if ids_m != ids_e:
            die(f"generation {gid}: manifest covers {len(ids_m)} trials against its expected "
                f"{len(ids_e)} (order included) — a partially measured generation is not "
                f"publishable, and recording it as complete is how it would become so")
        measured += len(ids_e)

        # The published tables are built from MANIFEST columns; hold every
        # classifying column to the frozen corpus, or a re-labeled manifest row
        # (a trial moved between groups, an UNKNOWN re-filed as a funnel wall)
        # would flow into the tables with the docs regenerated to match — R1
        # measured exactly that passing the byte-compare alone.
        for row in manifest:
            c = by_id_c[row["id"]]
            for k in ("group", "tool", "cls", "judge"):
                if row[k] != c[k]:
                    die(f"{gid}/{row['id']}: manifest {k} {row[k]!r} differs from the frozen corpus {c[k]!r}")
            wall_m = row["argv"].startswith("wall:")
            wall_c = c["launcher"] == "-"
            if wall_m != wall_c:
                die(f"{gid}/{row['id']}: wall-ness differs between manifest and corpus")
            if wall_c and row["argv"] != f"wall:{c['args']}":
                die(f"{gid}/{row['id']}: wall reason {row['argv']!r} differs from corpus {c['args']!r}")
            if not wall_c:
                # The report path decides WHICH report speaks for the trial; an
                # unbound rpath lets verdicts swap between trials with every
                # classifying column intact (R2 measured the B-group rate
                # flipping 1/1 -> 0/1 that way). The argv binding closes the
                # same door for the record's invocation column.
                if row["rpath"] != f"{c['artdir']}/{c['rpath']}":
                    die(f"{gid}/{row['id']}: manifest report path {row['rpath']!r} differs from the frozen corpus")
                if row["argv"] != f"{c['launcher']} {c['args']}":
                    die(f"{gid}/{row['id']}: manifest argv {row['argv']!r} differs from the frozen corpus")

        reports = load_reports(root, gen["dir"], manifest)
        for row in manifest:
            r = reports[row["id"]]
            if "wall" not in r and r["verdict"] == "UNKNOWN" and r["reason"] not in enum:
                die(f"{gid}/{row['id']}: unknown_reason {r['reason']!r} not in the documented closed set")

        for row in manifest:
            want = digest_for(root, by_id_c[row["id"]]["defines"])
            if want != row["digest"]:
                die(f"{gid}/{row['id']}: define digest mismatch — the defines in the checkout are "
                    f"not the bytes the sweep hashed")

        # A flag on a corpus row has to reach the arithmetic, not only the
        # table: a marked trial sits in its group's denominator exactly once,
        # like any other. An implementation that renders the mark and then
        # skips the row when counting would print something true and compute
        # something else.
        rated = [t["id"] for t in trials]
        for c in exp:
            if c["flags"] == "-" or c["launcher"] == "-":
                continue
            r = reports[c["id"]]
            if "wall" in r or r["verdict"] == "SETUP_ERROR":
                continue
            if rated.count(c["id"]) != 1:
                die(f"{gid}/{c['id']} carries flags {c['flags']!r} and appears {rated.count(c['id'])} "
                    f"times in the rated set — a flagged trial counts exactly once")

        # Conservation: every A-group FAIL lands in one of the four rows the
        # outcome table prints. A disposition outside that set — a tool
        # recorded as having no FAIL that then produces one — would drop out
        # of the ratio with the table still summing to something plausible.
        ga = [t for t in trials if t["group"] == "A"]
        fails = [t for t in ga if t["v"] == "FAIL"]
        stray = sorted({t["tool"] for t in fails
                        if outcome.get(t["tool"], "new-this-sweep") not in PRINTED_DISPOSITIONS})
        if stray:
            die(f"{gid}: A-group FAILs from {stray} carry a disposition the outcome table does "
                f"not print — they would leave the ratio without leaving a trace")

    if measured == 0:
        if PLACEHOLDER not in docs:
            die("no generation has measured anything, and docs/unknown-rate.md lacks the "
                "not-yet-measured placeholder")
        print(f"count.py check: pre-data state — placeholder asserted, corpus parsed "
              f"({len(corpus)} rows, {len(generations)} generations)")
        return

    if MARK_BEGIN not in docs or MARK_END not in docs:
        die("docs/unknown-rate.md lacks the results markers")
    published = docs.split(MARK_BEGIN)[1].split(MARK_END)[0]
    # Row-count first, on the PUBLISHED side: after the byte-compare passes
    # this could never fire (the recomputation always emits one row per
    # measured row — R1 proved the original order unreachable), so the
    # empty-table guard has to look at the docs before trusting them.
    pub_rows = [l for l in published.splitlines() if l.startswith("| ")]
    if len(pub_rows) < measured:
        die(f"published tables carry {len(pub_rows)} rows for {measured} measured trials — "
            f"an empty or truncated table cannot stand in for the measurement")
    computed = block.split(MARK_BEGIN)[1].split(MARK_END)[0]
    if published != computed:
        die("published results block differs from recomputation (drift)")
    print(f"count.py check: OK — {len(corpus)} corpus rows across {len(generations)} generations, "
          f"{measured} measured, digests verified, docs in sync")

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("emit", "check"):
        print(__doc__)
        sys.exit(2)
    if "--root" in sys.argv:
        root = Path(sys.argv[sys.argv.index("--root") + 1])
    else:
        root = Path(__file__).resolve().parents[2]
    if sys.argv[1] == "emit":
        sys.stdout.write(emit(root))
    else:
        check(root)

if __name__ == "__main__":
    main()
