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
EXCLUSION_COLS = ["id", "reason"]
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
    _reject_duplicate_ids(rows)
    return rows

def _reject_duplicate_ids(rows):
    """A trial id names one row. Nothing downstream survives two.

    `by_id` and `reports` are dicts, so a duplicate collapses silently there
    while `expected_for` keeps both — the two then disagree about how many
    trials a generation has. The retired flag guard caught this for the three
    flagged rows; this catches it for all 57.
    """
    seen = {}
    for r in rows:
        if r["id"] in seen:
            die(f"corpus.tsv names {r['id']!r} twice — a trial id is one row")
        seen[r["id"]] = True


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

def read_exclusions(root):
    """trial id -> why its apparatus failure was not fixable.

    The page's SETUP_ERROR rule has two halves — "fix the apparatus and re-run
    that trial; if unfixable, the row is published as excluded, with the reason".
    The first half is the default and leaves no record. This is the second: the
    judgement that a failure could not be fixed is made in a commit, in front of
    a reviewer, rather than by a sweep that drops the row and publishes the rate
    from what remains. The report's `message` says what failed and is not read
    here — it cannot say whether anyone tried to fix it, and the page states that
    count.py reads only machine fields.

    The three shape rules are checked where the file is read, so `emit` and
    `check` both get them: a ledger that is itself broken should refuse in either
    mode, and the message names this predicate rather than whatever downstream
    thing tripped over the bad row.
    """
    m = {}
    for r in read_ledger(root, "exclusions.tsv", EXCLUSION_COLS):
        if r["id"] in m:
            die(f"exclusions.tsv lists {r['id']!r} twice — the later row would win in "
                f"silence, and the reason a reviewer approved would publish as the other one")
        if not r["reason"].strip():
            die(f"exclusions.tsv: {r['id']} is waived with no reason — the page publishes "
                f"an excluded row *with the reason*, and an empty cell is not one")
        if "|" in r["reason"]:
            die(f"exclusions.tsv: {r['id']}'s reason contains a pipe, which would split the "
                f"published table row it is written into")
        if MARK_END in r["reason"]:
            die(f"exclusions.tsv: {r['id']}'s reason carries the results block's end marker. "
                f"The reason is written into that block and `check` finds the block by "
                f"splitting the page on this string, so an injected one shortens the compared "
                f"region on both sides at once — everything past it stops being checked, and "
                f"the reason a reviewer approved can differ from the one the page publishes")
        # That rule was written, withdrawn, and restored, and the withdrawal is the part
        # worth keeping. Four placements were tried and every one died on a predicate
        # that already existed — injected early the truncated block loses rows and the
        # published-rows-against-measured guard fires, injected late the group's rate
        # line goes missing and attribution fires — which read as "structurally
        # unreachable": a SETUP_ERROR row only renders inside a detail table, and a
        # detail table appeared to always be followed by a rate line or an outcome
        # table. The generalisation was false and all four measurements sat inside its
        # blind spot. `check_attribution` skips a group with no rated trial, and the
        # outcome table is only required when the A group has one — so a generation
        # covering B alone, whose trials are all walls and SETUP_ERRORs, has nothing
        # after that detail table. This page contemplates exactly that generation
        # ("A future B measurement is its own decision, with its own generation").
        # Measured on it: green, with the comparison ending mid-cell, and the reason
        # editable past the marker without the gate noticing.
        m[r["id"]] = r["reason"]
    return m


def read_apparatus(root, gen_dir):
    """The apparatus record a completed generation was swept under.

    `sweep.sh` writes this file (its apparatus block) and nothing has ever read
    it, so a truncated or absent record passed every rate check that exists
    (#348). Four rules answer that, three of them here and the fourth — that the
    manifest's images are named — in `check`, where the manifest is in hand. They
    sit in the order truncation reaches: a write that stops partway loses the image
    lines, then `head:`, then the digests. The banner is the one line truncation
    can never take alone, which
    is why no rule below asks for it — a banner-only deletion is a targeted edit,
    not the accident this file is here for, and it is indistinguishable in value
    from the targeted edits nothing here catches (rewriting one character of a
    digest, say).

    Two of the three answer failures the producer does not guard. `sweep.sh`
    checks the rc of its docker run and greps for the banner, but nothing looks
    at `git rev-parse HEAD` (a failure writes `head: ` with no value and the
    sweep continues) or at `docker images | grep`, whose empty result writes no
    image lines at all.

    Returns the ids named by image lines, and how many such lines there were. The
    ids come from the image lines only, not from every token in the file: taking
    the whole file lets an id satisfy the rule from anywhere in it, and the page
    promises "a line naming every image the manifest used". Measured before
    narrowing it — deleting all three image lines and appending their ids to the
    banner passed.

    That set is a SUPERSET of what the sweep used: the producer lists every
    `sideeye-ur-*` on the host rather than the ones it ran, so a match establishes
    that the record is intact, never that these are the images the trials ran under.
    The count is returned for the same reason the waiver count above is — the
    obvious alternative, how many distinct images the manifest names, is derivable
    from the manifest alone, so an implementation that opened nothing here would
    print an identical number.
    """
    p = root / "spike/unknown-rate" / gen_dir / "apparatus.txt"
    if not p.exists():
        die(f"{gen_dir}/apparatus.txt is missing — the generation is marked complete but "
            f"records no apparatus, and every rate check below would pass over that")
    lines = p.read_text().splitlines()
    digests = [l for l in lines if re.match(r"^[0-9a-f]{64}\s\s", l)]
    if len(digests) != 2:
        die(f"{gen_dir}/apparatus.txt carries {len(digests)} digest lines, not the engine's "
            f"and the shim's — a record that lost them cannot say which binaries ran")
    if not any(re.match(r"^head: [0-9a-f]{40}$", l) for l in lines):
        die(f"{gen_dir}/apparatus.txt has no resolved head: line — `git rev-parse` failing "
            f"during the sweep writes the key with no value and the sweep continues, so the "
            f"empty form is the one this catches")
    named, n_images = set(), 0
    for l in lines:
        m = re.match(r"^sideeye-ur-\S+\s+(\S+)$", l)
        if m:
            named.add(m.group(1))
            n_images += 1
    return named, n_images


def excluded_cell(trial_id, exclusions):
    """The cell that reports an excluded row, carrying its reason when one is waived.

    Deliberately tolerant where `check` is strict: an unwaived SETUP_ERROR renders
    the way it always did. `check` calls `emit` before its own predicates run, so
    refusing here would kill the unwaived fixture inside the renderer — red, and
    about the renderer rather than about the missing waiver.
    """
    reason = exclusions.get(trial_id)
    return f"SETUP_ERROR (excluded: {reason})" if reason else "SETUP_ERROR (excluded, published)"


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

# The headings emit_generation prints, in its own order. Kept as data beside the
# emitter rather than re-derived by the parser: a parser that keys on prose is
# one wording edit away from selecting the wrong table shape, and a mis-shaped
# parse yields zero rows — which reads as green unless something counts.
GROUP_HEADINGS = (
    ("A", "A-group (the engine's development input — not the threshold basis)"),
    ("control", "Control trials (outside every denominator)"),
    ("B", "B-group (mechanically selected; the threshold basis)"),
)
OUTCOME_HEADING = "Outcome ratio (A-group, per the committed disposition map)"
DETAIL_WIDE = "| trial | tool | class | judge | verdict | unknown_reason | flags |"
DETAIL_FUNNEL = "| target | class | funnel stage | verdict | unknown_reason |"


def parse_k_n(cell):
    """`0/13 (0.0%)` and `1/1 (counts only, n<5)` both mean (k, n)."""
    k, _, n = cell.split(" ")[0].partition("/")
    return int(k), int(n)


def split_published(published):
    """The published block as {(generation, group): section text}.

    Located by heading, never by counting tables: the same slice label appears
    under several groups — `class: c-cli` sits in g1's A, g1's B and g2's A — so
    anything that aggregates across the whole block sums to a number that
    matches no denominator (72 against 28/1/7/36, measured).
    """
    out, gid, cur = {}, None, None
    for line in published.splitlines():
        if line.startswith("### Generation "):
            gid, cur = line[len("### Generation "):].split(" ")[0], None
        elif line.startswith("#### "):
            head, cur = line[len("#### "):], None
            if head == OUTCOME_HEADING:
                cur = (gid, "outcome")
                out[cur] = []
            else:
                for group, name in GROUP_HEADINGS:
                    if head == name:
                        cur = (gid, group)
                        out[cur] = []
                        break
        elif cur is not None:
            out[cur].append(line)
    return {k: "\n".join(v) for k, v in out.items()}


def parse_section(text):
    """One section as (detail rows, slices, reason counts, rate).

    A detail row carries only the columns its own header declares: the wide
    table has `judge`, the funnel table does not, so the caller cannot
    reconstruct that axis for a funnel section and has to say so.

    SETUP_ERROR rows are dropped, and wall rows with them: both are published
    and neither belongs to a denominator. An implementation that forgets the
    exclusion is green on the live tree and on `fixtures/good` — neither
    contains a SETUP_ERROR row — which is why that exclusion carries a fixture.
    """
    detail, slices, reasons, rate, shape = [], {}, {}, None, None
    for line in text.splitlines():
        if line == DETAIL_WIDE:
            shape = "wide"
        elif line == DETAIL_FUNNEL:
            shape = "funnel"
        elif line.startswith("UNKNOWN rate, per-trial: **"):
            rate = parse_k_n(line.split("**")[1])
        elif line.startswith("| ") and not line.startswith("|---"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) == 2 and cells[0].partition(":")[0] in ("tool", "class", "judge"):
                axis, _, value = cells[0].partition(": ")
                if (axis, value) in slices:
                    # Not a new detection: the renderer builds slices from sets, so
                    # it cannot emit a duplicate without also drifting from the
                    # recomputation, and the byte-compare already refuses that. What
                    # this converts is the diagnosis — a generic drift becomes the
                    # specific reason — and it stops the scan volume this check
                    # reports from silently undercounting, since a duplicate would
                    # otherwise collapse into one dict entry.
                    die(f"the published block repeats slice {axis}: {value} — a duplicated row "
                        f"collapses into one and would be counted once by every check here")
                slices[(axis, value)] = parse_k_n(cells[1])
            elif len(cells) == 2 and cells[1].isdigit():
                reasons[cells[0]] = int(cells[1])
            elif shape == "wide" and len(cells) == 7 and cells[0] != "trial":
                if not cells[4].startswith("SETUP_ERROR"):
                    detail.append({"tool": cells[1], "cls": cells[2], "judge": cells[3],
                                   "v": cells[4].split(" (")[0]})
            elif shape == "funnel" and len(cells) == 5 and cells[0] != "target":
                if cells[2] == "explored":
                    detail.append({"tool": cells[0], "cls": cells[1],
                                   "v": cells[3].split(" (")[0]})
    return detail, slices, reasons, rate


AXES = (("tool", "tool"), ("class", "cls"), ("judge", "judge"))


def check_attribution(tables, published):
    """Every rated row reaches every published aggregate exactly once.

    `docs/unknown-rate.md` promises a marked row "sits in the denominator, its
    slices and the outcome ratio exactly once"; before this, only the
    denominator was checked, and `tabulate`'s own docstring says why that is not
    enough — a renderer that prints a row and skips it when aggregating looks
    right in both places. The byte-compare cannot see it either: both sides come
    from the same renderer.

    Named attribution, not conservation, because `check` already has an assert
    called that (the disposition one below) and `spike/acceptance.sh` names it in
    the sentence listing predicates without fixtures.

    Two things this deliberately does NOT do, each for a measured reason:

      * It sums nothing. A total is preserved by a renderer that counts a row
        twice under one label and drops another — and the row that mutation can
        hide is `a-himalaya-copy`, which carries `apparatus_declared`, i.e. the
        very subject of the sentence. Attribution is per label, not in aggregate.

      * It takes denominators from the measurement and numerators from the
        published detail rows, never the reverse. Only one fixture
        (`tampered-verdict`) reaches the docs comparison at all, and it moves a
        verdict — a numerator. Binding numerators to `trials` here would fire on
        it first and turn its pinned message into a hollow red. Denominators
        carry no such constraint. The numerator IS bound to the measurement,
        after the byte-compare, where that displacement cannot happen.

    Returns (sections, detail rows, slice rows, axes measured by denominator
    alone) so the caller can name its own scan volume: this walks the
    measurement and demands the published side match it, so an empty parse
    fails on the first section rather than passing over nothing.
    """
    sections = split_published(published)
    n_sec = n_detail = n_slice = n_outcome = 0
    sum_only = []
    for gen, _exp, _man, trials, _walls, _serr in tables:
        gid = gen["id"]
        for group, name in GROUP_HEADINGS:
            g = [t for t in trials if t["group"] == group]
            if not g:
                continue
            if (gid, group) not in sections:
                die(f"{gid}/{group}: {len(g)} rated trials, but the published block has no "
                    f"section headed {name!r}")
            detail, slices, reasons, rate = parse_section(sections[(gid, group)])
            n_sec, n_detail, n_slice = n_sec + 1, n_detail + len(detail), n_slice + len(slices)

            # The denominator, first: it is what every later comparison is
            # relative to, and a fixture that perturbs it must die here rather
            # than on a slice that disagrees for a downstream reason.
            if rate is None:
                die(f"{gid}/{group}: the published section carries no per-trial rate line")
            k_pub, n_pub = rate
            if n_pub != len(g):
                die(f"{gid}/{group}: the published denominator is {n_pub} against {len(g)} rated "
                    f"trials — the table and the measurement disagree about how many ran")
            if len(detail) != len(g):
                die(f"{gid}/{group}: the published per-trial table carries {len(detail)} rated "
                    f"rows against {len(g)} rated trials")

            # Family presence, before attribution: a family the renderer dropped
            # entirely leaves nothing to compare, and a loop over the families
            # that happen to be present would pass over it.
            for axis, field in AXES:
                want = sorted({t[field] for t in g})
                got = sorted({v for (a, v) in slices if a == axis})
                if want != got:
                    die(f"{gid}/{group}: the {axis} slices name {got} against {want} in the "
                        f"measurement — a slice family that loses a label loses its rows with it")

            funnel = any("judge" not in d for d in detail)
            for axis, field in AXES:
                for value in sorted({t[field] for t in g}):
                    k_s, n_s = slices[(axis, value)]
                    want_n = sum(1 for t in g if t[field] == value)
                    if n_s != want_n:
                        die(f"{gid}/{group}: slice {axis}: {value} counts {n_s} against {want_n} "
                            f"rated trials — a row reaches its slice exactly once or not at all")
                    if funnel and axis == "judge":
                        sum_only.append(f"{gid}/{group}/judge")
                        continue
                    want_k = sum(1 for d in detail if d[field] == value and d["v"] == "UNKNOWN")
                    if k_s != want_k:
                        die(f"{gid}/{group}: slice {axis}: {value} claims {k_s} UNKNOWN against "
                            f"{want_k} in the published rows — the table disagrees with itself "
                            f"(the measurement-bound comparison runs after the byte-compare)")

            # A biconditional, not a sum: the table is emitted only when the
            # numerator is non-zero, so "sum it when present" is green for a
            # renderer that drops it while rows remain.
            if bool(reasons) != (k_pub > 0):
                die(f"{gid}/{group}: the reason table is "
                    f"{'present' if reasons else 'absent'} with a published numerator of {k_pub}")
            if reasons and sum(reasons.values()) != k_pub:
                die(f"{gid}/{group}: the reason counts sum to {sum(reasons.values())} against a "
                    f"published numerator of {k_pub}")

        # The third thing the sentence names, and the one a section-shaped loop
        # walks past: the outcome table is emitted once per generation, after the
        # group loop, under its own heading — so a check that iterates group
        # sections never reaches it. It partitions the A-group by verdict (FAIL
        # split by disposition, then UNKNOWN, then PASS), which makes it the one
        # aggregate whose rows must sum to a denominator rather than match a
        # slice: every A-group trial lands in exactly one row.
        ga = [t for t in trials if t["group"] == "A"]
        if ga:
            if (gid, "outcome") not in sections:
                die(f"{gid}: {len(ga)} A-group trials, but the published block has no outcome "
                    f"table — the ratio the promise names is not there to check")
            _d, _s, rows, _r = parse_section(sections[(gid, "outcome")])
            n_outcome += len(rows)
            if sum(rows.values()) != len(ga):
                die(f"{gid}: the outcome rows sum to {sum(rows.values())} against {len(ga)} "
                    f"A-group trials — a row leaves the ratio without leaving a trace")
            # The per-row comparison is NOT here: it reads verdicts, which makes it
            # numerator-side, and `tampered-verdict` reaches this point. Measured:
            # placing it here takes that fixture's pinned message. It runs after
            # the byte-compare with the rate numerator, for the same reason.
    return n_sec, n_detail, n_slice, n_outcome, sorted(set(sum_only))


def emit_generation(gen, trials, walls, setup_errors, outcome, exclusions):
    L = []
    L.append("")
    L.append(f"### Generation {gen['id']} — measured {gen['date']} ({gen['groups']})")
    # The headings come from GROUP_HEADINGS, not a literal here: `check` locates
    # its sections by these strings, so two copies means a wording edit silently
    # stops the attribution check finding anything to check.
    for group, gname in GROUP_HEADINGS:
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
                L.append(f"| {s['tool']} | {s['cls']} | {excluded_cell(s['id'], exclusions)} | - | - |")
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
                         f"{excluded_cell(s['id'], exclusions)} | - | {s['flags']} |")
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
        L.append(f"#### {OUTCOME_HEADING}")
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
    exclusions = read_exclusions(root)
    L = [MARK_BEGIN,
         "_Generated by `spike/unknown-rate/count.py emit` — do not edit between the markers._"]
    for gen, exp, man, trials, walls, setup_errors in tables:
        if man is None:
            L.append("")
            L.append(f"### Generation {gen['id']} — not yet measured ({gen['groups']})")
            L.append("")
            L.append(PLACEHOLDER)
            continue
        L.extend(emit_generation(gen, trials, walls, setup_errors, outcome, exclusions))
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
    exclusions = read_exclusions(root)
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
    # Counted, not just checked: on a tree with no apparatus failures the waiver
    # predicates look at nothing, and a success line that does not say so cannot be
    # told apart from one that checked something. The live tree is that tree today.
    waived, seen_waivers = 0, set()
    # Both halves are reported, and the wording says "covered by" rather than
    # "against" on purpose: every other pair on the success line is a comparison this
    # check enforces, and this one is not. The record lists every `sideeye-ur-*` on
    # the sweep host, so its count can exceed what the manifests use without anything
    # being wrong. The apparatus side is here because it cannot be derived from
    # anything else in the tree — that is what separates a run that read the records
    # from one that opened nothing. Neither is asserted non-zero: a generation whose
    # trials are all walls names no images, and zero is the honest count.
    apparatus_images, manifest_images = 0, 0

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
        # After the unstarted `continue` and the missing-manifest die on purpose: a
        # generation with no manifest has no images to bind, and an unstarted one has
        # no apparatus to record. Not in `generation_tables` either — that is shared
        # with `emit`, and moving the refusal there would change which surface says no.
        apparatus, n_img = read_apparatus(root, gen["dir"])
        used = {row["image"] for row in manifest if not row["argv"].startswith("wall:")}
        unlisted = sorted(used - apparatus)
        if unlisted:
            die(f"{gid}: manifest names images the apparatus record does not: {unlisted} — "
                f"the record is short of the run it is supposed to describe")
        apparatus_images += n_img
        manifest_images += len(used)

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

        # The flagged-trial guard that stood here is gone. It asked whether a
        # marked row reached the rated set exactly once, and could only fire on a
        # duplicate corpus id: `:543` pins the manifest id list to the expected one
        # order-included, `tabulate` puts each manifest row in exactly one bucket,
        # and the guard re-derived its skip conditions from the same `reports`
        # mapping `tabulate` branches on. Measured before deleting it — a corpus
        # with a duplicated id made it fire with its own message, and nothing else
        # did — and that input is now covered more widely by `_reject_duplicate_ids`,
        # which applies to all 57 corpus rows rather than the 3 that carry flags.
        #
        # What a flagged row reaches is checked where the promise lives:
        # `check_attribution`, against every published aggregate.
        #
        # A partition assert over `tabulate`'s output stood here briefly and was
        # removed on review. `tabulate` performs exactly one unconditional append
        # per manifest row (if/elif/else, no filter), so the assert was unsatisfiable
        # for every input — true by construction, which is the same reason the guard
        # above was deleted. Falsifying it required mutating `tabulate` itself, i.e.
        # asserting an invariant about code rather than about data, and this file's
        # own standard is that a new guard is falsified once against its predicate.

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

        # The page's SETUP_ERROR rule is two-sided and only one side was enforced.
        # A row that failed to set up leaves the rated denominator whatever anyone
        # decided about it, so a sweep with one apparatus failure publishes a rate
        # over n-1 and reads exactly like a sweep of n. The default the page states
        # is "fix the apparatus and re-run that trial"; publishing the row instead
        # is the exception, allowed only "if unfixable", and that judgement is a
        # person's. This is where the person has to have written it down.
        for s in setup_errors:
            waived += 1
            if s["id"] not in exclusions:
                die(f"{gid}/{s['id']}: SETUP_ERROR with no row in exclusions.tsv — the page "
                    f"re-runs an apparatus failure and publishes it as excluded only if it "
                    f"cannot be fixed, so a generation cannot be complete while nobody has "
                    f"said which of those two happened")
            seen_waivers.add(s["id"])

    # And the other direction. A waiver whose trial no longer fails — or never did —
    # excuses nothing, and the reason it carries would go on reading as approved
    # while the row it named has moved on.
    orphans = sorted(set(exclusions) - seen_waivers)
    if orphans:
        die(f"exclusions.tsv waives {orphans}, which is not a SETUP_ERROR in any complete "
            f"generation — a waiver outliving its trial excuses nothing")

    if measured == 0:
        if PLACEHOLDER not in docs:
            die("no generation has measured anything, and docs/unknown-rate.md lacks the "
                "not-yet-measured placeholder")
        # No waiver count here: the orphan check above runs before this branch, so a
        # pre-data tree with any waiver at all has already died. The number would be
        # zero on every run that reaches this line, which is the opposite of the
        # reason the main success line carries one.
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
    n_sec, n_detail, n_slice, n_outcome, sum_only = check_attribution(tables, published)
    computed = block.split(MARK_BEGIN)[1].split(MARK_END)[0]
    if published != computed:
        die("published results block differs from recomputation (drift)")

    # The numerator, bound to the measurement — and it has to sit HERE, after the
    # byte-compare, not with the rest of attribution. Before it, this fires on
    # `tampered-verdict` (the only fixture that reaches the block) and displaces
    # its pinned message. After it, it is still live: the byte-compare proves
    # published == computed, and computed came from the renderer, so recomputing
    # k from `trials` directly is the one comparison a renderer bug in the
    # numerator cannot survive. Unlike `pub_rows` above, this is not dead here.
    #
    # No data-only fixture can make it red — a fixture that perturbs the number
    # dies earlier — so it is named in acceptance.sh's list of predicates
    # carrying no fixture rather than pretending to have one.
    pub_sections = split_published(published)
    for gen, _e, _m, trials, _w, _s in tables:
        for group, _name in GROUP_HEADINGS:
            g = [t for t in trials if t["group"] == group]
            if not g:
                continue
            _d, _sl, _r, rate = parse_section(pub_sections[(gen["id"], group)])
            want_k = sum(1 for t in g if t["v"] == "UNKNOWN")
            if rate[0] != want_k:
                die(f"{gen['id']}/{group}: the published numerator is {rate[0]} against {want_k} "
                    f"UNKNOWN in the measurement")
            # Per slice, and against the measurement — not against the published
            # detail rows. Reconciling a slice numerator with the detail table is
            # published-against-published: both come from the renderer, which is
            # the defect this whole check exists to close, and the first version
            # of it reproduced that defect one level down. Measured: a renderer
            # that reports the flagged row as PASS in the detail table AND drops
            # it from every slice numerator, while leaving the rate line honest,
            # passed everything until this ran.
            funnel = any("judge" not in d for d in _d)
            for axis, field in AXES:
                if funnel and axis == "judge":
                    continue
                for value in sorted({t[field] for t in g}):
                    k_s, _n = _sl[(axis, value)]
                    wk = sum(1 for t in g if t[field] == value and t["v"] == "UNKNOWN")
                    if k_s != wk:
                        die(f"{gen['id']}/{group}: slice {axis}: {value} claims {k_s} UNKNOWN "
                            f"against {wk} in the measurement")
        ga = [t for t in trials if t["group"] == "A"]
        if ga:
            _d, _s, rows, _r = parse_section(pub_sections[(gen["id"], "outcome")])
            for label, want in (("UNKNOWN", sum(1 for t in ga if t["v"] == "UNKNOWN")),
                                ("PASS", sum(1 for t in ga if t["v"] == "PASS"))):
                if rows.get(label) != want:
                    die(f"{gen['id']}: the outcome table puts {rows.get(label)} in {label} "
                        f"against {want} in the measurement")
            fails = sum(1 for t in ga if t["v"] == "FAIL")
            pub_fails = sum(v for k, v in rows.items() if k.startswith("FAIL, "))
            if pub_fails != fails:
                die(f"{gen['id']}: the outcome table's FAIL rows sum to {pub_fails} against "
                    f"{fails} A-group FAILs")

    weaker = f"; {len(sum_only)} axis measured by denominator alone ({', '.join(sum_only)})" if sum_only else ""
    print(f"count.py check: OK — {len(corpus)} corpus rows across {len(generations)} generations, "
          f"{measured} measured, digests verified, docs in sync; attribution reconciled "
          f"{n_detail} published rows against {n_slice} slices and {n_outcome} outcome rows "
          f"across {n_sec} sections{weaker}; {waived} SETUP_ERROR rows against "
          f"{len(exclusions)} waivers; {manifest_images} manifest images covered by "
          f"{apparatus_images} apparatus image lines read")

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
