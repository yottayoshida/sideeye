#!/usr/bin/env python3
"""outcome-funnel.py — how far each target got, from a define to an upstream fix (#605).

Why this exists: this project measures reach and verdict quality carefully and does
not measure what happens after a verdict exists. A FAIL may be already known,
recoverable, not worth reporting, reported and declined, acknowledged, fixed, or
re-measured against a fix. Those states lived across BUILDLOG, dogfood notes,
target-class rows and the upstream-report ledger, so nobody could count them end to
end -- and the next engineering priority depends on where the drop-off is. If most
fresh targets still refuse, reach work dominates. If targets are judgeable but few
FAILs are worth reporting, widening reach further will not change outcomes.

THE RECORD IS spike/outcome-funnel.tsv. One row per (campaign, target): how far that
campaign got with that target, and why it stopped there. The row does not repeat the
evidence -- it names it, and this script holds the row to what the named evidence
says. That is the whole point: a hand-written funnel goes stale silently, and the
first draft of this one said eleven targets reached exploration where the reports say
fourteen (bat explored 8 worlds, ccache 55, meson 110, each before refusing).

Stages, in order. A row carries the FURTHEST one it reached:

  attempted     the target reached a define and the engine ran against it.
                Not "screened": spike/dogfood/RUNS.md spells that word for the
                candidates a run turned away ("20 measured ..., 21 screened out"),
                and docs/target-classes.md's first table spells "Measured" for
                targets that have a verdict. Both would read backwards here.
  explored      the report says explored >= 1 (worlds run, baseline included).
  judged        PASS or FAIL. An operation that performs nothing PASSes with
                crash_points 0 and explored 0 (docs/report-schema.md), and that is
                not a verdict about the tool -- it does not reach this stage.
  novel         the run's record says the finding is not already known.
  report_worthy the owner judged it worth filing.
  filed         an upstream report exists.
  acknowledged  upstream confirmed the defect. Not contact: a substantive reply
                that declines, and an open discussion with no resolution, leave the
                row at `filed` with `declined` or `discussing` saying which.
  fixed         upstream landed a fix.
  revalidated   this project re-measured against the fix.

WHAT THIS CANNOT SEE, said here rather than left to be discovered:

  * Every stage above `judged`. The comparison against a report stops there: a report
    cannot know whether its finding was novel, was judged worth filing, or was filed.
    Those stages are the record's word, held only by the internal rules below.
  * Which report a row names, when a campaign produced several for the same target.
    mlr answered UNKNOWN five times and PASS once; composer PASS, PASS, then FAIL.
    The row names the one its campaign's record names, and nothing here checks that
    choice -- a row naming the convenient report passes every rule below.
  * Any target whose campaign kept no report JSON. Those rows are held to existence
    and to the record naming the target -- in its text or in its file name, which for
    a refusal transcript is the only place the tool is named -- and nothing more;
    `summary` prints how many rows are in each state rather than letting the reader
    assume.
  * The live state of an upstream report. `as_of` says when the tail was last read
    and spike/upstream-report-status.sh measures it now; nothing here reaches a
    tracker.
  * Whether a dogfood run happened at all. There is deliberately NO rule that every
    directory under spike/dogfood/ has rows -- a new run would go red for no reason
    its author could act on. The containment that does exist runs the other way:
    a report in spike/upstream-reports.tsv with no row here is red, because filing
    a report and forgetting the funnel is the drift this record exists to stop.

Usage:
  python3 spike/outcome-funnel.py check                  # the records agree
  python3 spike/outcome-funnel.py summary                # the funnel
  python3 spike/outcome-funnel.py summary --campaign X   # one campaign
  python3 spike/outcome-funnel.py summary --since DATE   # campaigns from DATE on
  python3 spike/outcome-funnel.py --check-doc            # both generated blocks match
  python3 spike/outcome-funnel.py --write-doc            # regenerate both blocks
  python3 spike/outcome-funnel.py --selftest             # falsify the checker

Two pages carry a generated block: docs/outcome-funnel.md (the counts) and docs/found.md
(every report in spike/upstream-reports.tsv with its furthest state here, #713).

Exit 0 it holds, 1 the records disagree, 2 the check could not run -- and, from
--selftest, a predicate that no longer fires, which is the same thing said of the
checker itself. Never read a 2 as a pass: a comparison that failed to run is not the
agreement of two sets nobody built.
"""

import argparse
import json
import os
import re
import sys
import tempfile

STAGES = [
    "attempted", "explored", "judged", "novel", "report_worthy",
    "filed", "acknowledged", "fixed", "revalidated",
]
RANK = {s: i for i, s in enumerate(STAGES)}
VERDICTS = {"pass", "fail", "unknown", "-"}
# Why a row stopped where it did. A closed set so it can be counted; the reason in
# prose lives in `note`. `known` and `not_worth` are separate on purpose: pre-commit
# was not filed because no content is lost, which is a judgement about worth, and
# writing it as `known` would claim the run assessed novelty when it did not.
STOPS = {
    "-", "wall", "no_operations", "known", "not_worth", "no_content_lost",
    "awaiting", "declined", "withdrawn", "discussing",
}
COVERAGE = {"full", "filings-only"}
REPORT_RE = re.compile(r"^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
# A report JSON is recognised by what it carries, never by its extension. Two kinds of
# .json under spike/dogfood/ are not reports: the strace readings under
# 2026-09-13-joplin-turns/transcripts/ (forty of them, twenty in runs/ and twenty in
# logger-error/, none carrying a verdict) and the case files a
# replay reads. Deciding by suffix would hold rows to the wrong documents.
REPORT_KEYS = {"schema", "verdict", "explored", "crash_points"}

DOC = "docs/outcome-funnel.md"
BEGIN = "<!-- outcome-funnel:summary:begin -->"
END = "<!-- outcome-funnel:summary:end -->"
# The second generated page (#713): every report in spike/upstream-reports.tsv, with the
# furthest state this ledger records for it. A sentinel for `_tree` below: render the
# page from the tree's own records rather than writing a fixed text.
FOUND = "docs/found.md"
FOUND_BEGIN = "<!-- found:begin -->"
FOUND_END = "<!-- found:end -->"
RENDER = object()


class Broken(Exception):
    """The check could not run (exit 2), as distinct from records that disagree."""


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_tsv(path, fields, what):
    """Rows of exactly `fields` tab-separated values. A row with the wrong count is
    refused rather than skipped: a row written with spaces is one field, and the two
    scripts this project already runs lost a report exactly that way (#297)."""
    if not os.path.isfile(path):
        raise Broken("cannot read %s: %s" % (what, path))
    out = []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != fields:
                raise Broken(
                    "%s line %d: %d tab-separated field(s), want %d -- a row written "
                    "with spaces is one field and would vanish in silence"
                    % (what, n, len(parts), fields))
            out.append((n, parts))
    return out


def read_report(root, rel):
    """The report a row names, or None when the file is not one."""
    path = os.path.join(root, rel)
    if not path.endswith(".json"):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(doc, dict) or not REPORT_KEYS.issubset(doc.keys()):
        return None
    return doc


def read_upstream(root):
    """The report ledger with every column kept. `load` reduces it to the set of reports;
    docs/found.md needs the status and the tool's name as well (#713)."""
    out = []
    for n, (owner, number, status, finding) in read_tsv(
            os.path.join(root, "spike/upstream-reports.tsv"), 4, "upstream-reports"):
        out.append({"line": n, "owner": owner, "number": number, "status": status,
                    "finding": finding, "report": "%s#%s" % (owner, number)})
    return out


def reports_at_filed(campaigns, rows):
    """Each report's rows at `filed` or beyond, earliest campaign first (then file order).
    One place for `check`'s filing rules and for docs/found.md: the first entry's date is
    the filing, and the furthest row is the state the page shows."""
    by_report = {}
    for row in rows:
        if row["report"] != "-" and RANK.get(row["stage"], -1) >= RANK["filed"]:
            c = campaigns.get(row["campaign"])
            by_report.setdefault(row["report"], []).append((c["date"] if c else "", row))
    for dated in by_report.values():
        dated.sort(key=lambda dr: (dr[0], dr[1]["line"]))
    return by_report


def furthest(dated):
    """The row a report's state is read from: the highest stage, and of two rows at that
    stage the later campaign's (then the later line) -- the newer reading of the same
    tail. By campaign date, not file order: the funnel file is not written in date order."""
    return max(dated, key=lambda dr: (RANK[dr[1]["stage"]], dr[0], dr[1]["line"]))[1]


# Read from transcripts (.txt) only. A markdown record quotes other targets' blocks and
# writes the word in prose: unrestricted, this took the joplin refusal quoted inside the
# 2026-09-11 RESULTS.md for three other rows citing that same page, and the word after
# "UNKNOWN" in a sentence of BUILDLOG.md for a fourth. Anchoring to the file's first
# byte instead was measured and rejected for the opposite error -- beets.txt and
# joplin.txt carry a line of the target's own output above the verdict, so the rule
# would have skipped the two rows it should read.
REFUSAL_LINE = re.compile(r"^UNKNOWN[ \t]+([a-z0-9_]+)", re.MULTILINE)


def refusals_named_by(doc, body, evidence):
    """The refusals the evidence itself raises, as a set.

    From a report that is one field. From a transcript it is every `UNKNOWN <reason>`
    line the engine wrote, because a transcript can hold more than one run; the row is
    then held to naming one of them rather than a particular one.
    """
    if doc is not None:
        reason = doc.get("unknown_reason")
        return {reason} if isinstance(reason, str) and reason else set()
    if not evidence.endswith(".txt"):
        return set()
    return set(REFUSAL_LINE.findall(body or ""))

def stage_from_report(doc):
    """The furthest stage the report alone establishes."""
    verdict = str(doc.get("verdict", ""))
    try:
        explored = int(doc.get("explored", 0))
        crash_points = int(doc.get("crash_points", 0))
    except (TypeError, ValueError):
        return None
    if verdict in ("PASS", "FAIL") and crash_points > 0:
        return "judged"
    if explored >= 1:
        return "explored"
    return "attempted"


def verdict_from_report(doc):
    return {"PASS": "pass", "FAIL": "fail"}.get(str(doc.get("verdict", "")), "unknown")


def load(root):
    campaigns = {}
    for n, (name, date, coverage, candidates, evidence) in read_tsv(
            os.path.join(root, "spike/outcome-funnel-campaigns.tsv"), 5, "campaigns"):
        if name in campaigns:
            raise Broken("campaigns line %d: %s is listed twice" % (n, name))
        campaigns[name] = {
            "line": n, "date": date, "coverage": coverage,
            "candidates": candidates, "evidence": evidence,
        }
    rows = []
    for n, parts in read_tsv(
            os.path.join(root, "spike/outcome-funnel.tsv"), 9, "funnel"):
        keys = ("campaign", "target", "stage", "verdict", "stop",
                "report", "evidence", "as_of", "note")
        row = dict(zip(keys, parts))
        row["line"] = n
        rows.append(row)
    filed = {u["report"] for u in read_upstream(root)}
    return campaigns, rows, filed


def check_refusal(bad, at, row, doc, body):
    """A refused run's own reason has to appear in the row's note.

    One direction only. A note may name a second refusal the row met elsewhere (the
    2026-09-16 zstd row names the one each observation mode gave), and a note may name
    none at all where the evidence refused nothing. What it may not do is describe the
    row with a refusal the evidence did not raise -- which is how a discarded
    measurement got cited: gopass.txt refuses boundary_without_oracle, the note said
    no_shim_marker, and the run's RESULTS.md had already thrown that transcript out.
    """
    reasons = refusals_named_by(doc, body, row["evidence"])
    if reasons and not any(r in row["note"] for r in reasons):
        bad.append("%s: the evidence refuses %s and the note names none of them -- "
                   "check the row is citing the measurement it describes"
                   % (at, ", ".join("`%s`" % r for r in sorted(reasons))))

def check(root):
    """Returns (rc, lines). rc 0 ok, 1 the records disagree."""
    campaigns, rows, filed = load(root)
    if not rows and not filed:
        raise Broken("both records are empty -- an empty funnel and an empty report "
                     "ledger agree, and that agreement is not a measurement")
    bad = []

    for name, c in sorted(campaigns.items()):
        if c["coverage"] not in COVERAGE:
            bad.append("campaigns line %d: coverage %r is not one of %s"
                       % (c["line"], c["coverage"], "/".join(sorted(COVERAGE))))
        if not DATE_RE.match(c["date"]):
            bad.append("campaigns line %d: date %r is not YYYY-MM-DD -- --since "
                       "reads it" % (c["line"], c["date"]))
        if c["candidates"] != "-" and not c["candidates"].isdigit():
            bad.append("campaigns line %d: candidates %r is neither a number nor -"
                       % (c["line"], c["candidates"]))
        if not os.path.exists(os.path.join(root, c["evidence"])):
            bad.append("campaigns line %d: %s does not name a file in this repository"
                       % (c["line"], c["evidence"]))

    seen = {}
    real_root = os.path.realpath(root)
    for row in rows:
        at = "funnel line %d (%s / %s)" % (row["line"], row["campaign"], row["target"])
        key = (row["campaign"], row["target"])
        if key in seen:
            bad.append("%s: already recorded on line %d" % (at, seen[key]))
        seen[key] = row["line"]
        if row["campaign"] not in campaigns:
            bad.append("%s: no such campaign in the campaigns file" % at)
        if row["stage"] not in RANK:
            bad.append("%s: stage %r is not one of %s"
                       % (at, row["stage"], "/".join(STAGES)))
            continue
        if row["verdict"] not in VERDICTS:
            bad.append("%s: verdict %r is not one of %s"
                       % (at, row["verdict"], "/".join(sorted(VERDICTS))))
        if row["stop"] not in STOPS:
            bad.append("%s: stop %r is not one of %s"
                       % (at, row["stop"], "/".join(sorted(STOPS))))
        rank = RANK[row["stage"]]

        if rank >= RANK["judged"] and row["verdict"] not in ("pass", "fail"):
            bad.append("%s: stage %s needs a verdict of pass or fail, not %r"
                       % (at, row["stage"], row["verdict"]))
        # A counterexample is what novel / report_worthy / filed are about, so those
        # three need a FAIL. The tail does not: the 2026-09-06 patch3 row re-measured
        # mogrify against the fix and PASSed, and that PASS is exactly what
        # `revalidated` means. Requiring FAIL all the way up would make the top of
        # the ladder reachable only by a fix that did not work.
        if RANK["novel"] <= rank <= RANK["filed"] and row["verdict"] != "fail":
            bad.append("%s: stage %s is about a counterexample and the verdict is %r"
                       % (at, row["stage"], row["verdict"]))

        if rank >= RANK["filed"]:
            if row["report"] == "-":
                bad.append("%s: stage %s without an upstream report" % (at, row["stage"]))
            if not DATE_RE.match(row["as_of"]):
                bad.append("%s: stage %s needs as_of -- a tail state with no reading "
                           "date is indistinguishable from one nobody re-read"
                           % (at, row["stage"]))
        elif row["as_of"] != "-":
            bad.append("%s: as_of is for rows that reached filed; this one is %s"
                       % (at, row["stage"]))

        if row["report"] != "-":
            if not REPORT_RE.match(row["report"]):
                bad.append("%s: report %r is not owner/repo#N" % (at, row["report"]))
            elif row["report"] not in filed:
                bad.append("%s: %s is not in spike/upstream-reports.tsv -- a report "
                           "this project did not file belongs in the note"
                           % (at, row["report"]))

        # Resolved and held inside the tree: the column says "a path in this
        # repository", and `../` reached outside it while satisfying every other rule.
        path = os.path.realpath(os.path.join(root, row["evidence"]))
        if os.path.commonpath([path, real_root]) != real_root:
            bad.append("%s: evidence %s resolves outside this repository"
                       % (at, row["evidence"]))
            continue
        if not os.path.exists(path):
            bad.append("%s: evidence %s does not name a file in this repository"
                       % (at, row["evidence"]))
            continue
        doc = read_report(root, row["evidence"])
        if doc is None:
            # Not a report. Existence alone would accept any file in the tree, so the
            # record has to at least name the target it is cited for -- in its text, or
            # in its path, because an engine refusal transcript carries the refusal and
            # never the tool's name (preflight-round1/chezmoi.txt says `no_shim_marker`
            # and nothing else; the run put "chezmoi" in the file name).
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    body = fh.read()
            except OSError as exc:
                # A directory passes os.path.exists and fails to open. That is a row
                # written wrong, not a check that could not run.
                bad.append("%s: evidence %s could not be read as a record (%s)"
                           % (at, row["evidence"], exc.__class__.__name__))
                continue
            target = row["target"].lower()
            if target not in body.lower() and target not in row["evidence"].lower():
                bad.append("%s: %s names this target neither in its text nor in its "
                           "path, so it cannot be the record for this row"
                           % (at, row["evidence"]))
            check_refusal(bad, at, row, None, body)
            continue
        implied = stage_from_report(doc)
        if implied is None:
            bad.append("%s: %s does not carry readable counters"
                       % (at, row["evidence"]))
            continue
        want = verdict_from_report(doc)
        if row["verdict"] != want:
            bad.append("%s: the row says %s, %s says %s"
                       % (at, row["verdict"], row["evidence"], want))
        check_refusal(bad, at, row, doc, None)
        capped = STAGES[min(rank, RANK["judged"])]
        if capped != implied:
            bad.append("%s: the row reaches %s, %s establishes %s (verdict %s, "
                       "explored %s, crash points %s)"
                       % (at, row["stage"], row["evidence"], implied,
                          doc.get("verdict"), doc.get("explored"),
                          doc.get("crash_points")))

    # One filing per report, and the filing is the earliest campaign carrying it at
    # filed or beyond. Not "one row per report": ImageMagick#8939 was filed by the
    # 2026-09-05 run, answered on the same issue by the refix run, and re-measured by
    # the patch3 run -- and that last row is the only `revalidated` this project has.
    # A rule of one row per report would make the top of the ladder unreachable.
    by_report = reports_at_filed(campaigns, rows)
    for report, dated in sorted(by_report.items()):
        first_date = dated[0][0]
        if len(dated) > 1 and dated[1][0] == first_date:
            bad.append("%s: two campaigns dated %s both carry it at filed or beyond, "
                       "so which one filed it cannot be read" % (report, first_date))
        for i, (_date, row) in enumerate(dated):
            if i > 0 and row["stage"] == "filed":
                bad.append("funnel line %d: %s was filed by the %s campaign; a later "
                           "row saying `filed` claims the filing twice"
                           % (row["line"], report, dated[0][1]["campaign"]))
    for report in sorted(filed):
        if report not in by_report:
            bad.append("%s is in spike/upstream-reports.tsv and reaches no row here "
                       "-- add the row for the campaign that filed it" % report)
    # Withdrawn is said in both records, and docs/found.md shows the ledger's word. The
    # two have to agree, or the page states one and this file the other (#713).
    for u in read_upstream(root):
        dated = by_report.get(u["report"])
        if not dated:
            continue
        top = furthest(dated)
        if (u["status"] == "withdrawn") != (top["stop"] == "withdrawn"):
            bad.append("%s: spike/upstream-reports.tsv says %s and its furthest row here "
                       "(funnel line %d) stops at %s -- the two records disagree on "
                       "whether it was withdrawn"
                       % (u["report"], u["status"], top["line"], top["stop"]))

    if bad:
        return 1, ["REFUSE the funnel does not agree with what it names:"] + \
                  ["  " + b for b in bad]
    return 0, ["ok: %d rows over %d campaigns, each holding to the evidence it names"
               % (len(rows), len(campaigns))]


def summarise(root, campaign=None, since=None):
    campaigns, rows, _filed = load(root)
    if campaign is not None:
        if campaign not in campaigns:
            raise Broken("no such campaign: %s" % campaign)
        rows = [r for r in rows if r["campaign"] == campaign]
        names = {campaign}
    else:
        names = set(campaigns)
    if since is not None:
        if not DATE_RE.match(since):
            raise Broken("--since wants YYYY-MM-DD, got %r" % since)
        names = {n for n in names if campaigns[n]["date"] >= since}
        rows = [r for r in rows if r["campaign"] in names]

    full = {n for n in names if campaigns[n]["coverage"] == "full"}
    reach = [r for r in rows if r["campaign"] in full]
    out = []
    scope = campaign if campaign else ("since " + since if since else "every campaign")
    out.append("outcome funnel -- %s" % scope)
    out.append("")
    out.append("%d encounters (one campaign meeting one target) over %d campaigns, "
               "%d of them" % (len(rows), len(names), len(full)))
    out.append("recording every target they met; %d distinct targets."
               % len({r["target"] for r in rows}))
    screened = [campaigns[n]["candidates"] for n in sorted(names)
                if campaigns[n]["candidates"] != "-"]
    backed = sum(1 for r in rows if read_report(root, r["evidence"]) is not None)
    out.append("%d rows are held to a report this repository committed; %d name a "
               "written record only." % (backed, len(rows) - backed))
    if screened:
        out.append("%d candidates screened before the slates were fixed, over the %d "
                   "campaign(s) that" % (sum(int(c) for c in screened), len(screened)))
        out.append("recorded one; the rest kept no such count.")
    out.append("")
    out.append("reach, over the %d campaign(s) that recorded every target they met"
               % len(full))
    for stage in STAGES[:RANK["judged"] + 1]:
        n = sum(1 for r in reach if RANK.get(r["stage"], -1) >= RANK[stage])
        out.append("  %-14s %4d" % (stage, n))
    for verdict in ("pass", "fail"):
        n = sum(1 for r in reach
                if r["verdict"] == verdict and RANK.get(r["stage"], -1) >= RANK["judged"])
        out.append("    %-12s %4d" % (verdict.upper(), n))
    out.append("")
    # Both columns, because one alone invites a subtraction that is not a funnel
    # step: the reach block above counts full-coverage campaigns only, while a
    # filings-only campaign contributes to the outcome block and to nothing above it.
    # Three columns, because two of them answer different questions and the page asks
    # the third. The row counts are encounters: mogrify is counted twice at
    # `revalidated`, once for the refix run and once for patch3. "reports" is how many
    # distinct upstream reports stand at that stage, which is what "how many reports
    # turned into something upstream" means.
    out.append("outcome            encounters   in full campaigns   distinct reports")
    for stage in STAGES[RANK["novel"]:]:
        at_least = [r for r in rows if RANK.get(r["stage"], -1) >= RANK[stage]]
        nf = sum(1 for r in reach if RANK.get(r["stage"], -1) >= RANK[stage])
        reps = len({r["report"] for r in at_least if r["report"] != "-"})
        out.append("  %-14s %8d %15d %14d" % (stage, len(at_least), nf, reps))
    out.append("")
    stops = {}
    for r in rows:
        if r["stop"] != "-":
            stops[r["stop"]] = stops.get(r["stop"], 0) + 1
    out.append("why encounters stopped: " +
               (", ".join("%s %d" % kv for kv in sorted(stops.items())) or "nothing recorded"))
    reads = sorted(r["as_of"] for r in rows if r["as_of"] != "-")
    if reads:
        out.append("upstream states last read between %s and %s; "
                   "spike/upstream-report-status.sh measures them now."
                   % (reads[0], reads[-1]))
    return "\n".join(out)


# The state a report shows, strongest first; the order is also the page's order.
FOUND_STATES = ["fixed upstream, re-measured", "fixed upstream", "acknowledged", "filed",
                "withdrawn"]


def found_state(u, top):
    """What docs/found.md says of one report: the ledger's withdrawn, or the furthest
    row's stage, with its stop where it has one -- `revalidated` with `discussing` is a
    fix that was re-measured and argued over, and the page says so rather than drop it."""
    if u["status"] == "withdrawn":
        return "withdrawn", "withdrawn"
    kind = {"revalidated": "fixed upstream, re-measured",
            "fixed": "fixed upstream"}.get(top["stage"], top["stage"])
    shown = kind if top["stop"] == "-" else "%s (%s)" % (kind, top["stop"])
    return kind, shown


def found_block(root):
    """docs/found.md's block: one row per report in spike/upstream-reports.tsv (#713)."""
    campaigns, rows, _filed = load(root)
    by_report = reports_at_filed(campaigns, rows)
    entries = []
    for u in read_upstream(root):
        dated = by_report.get(u["report"])
        if not dated:
            raise Broken("%s is in spike/upstream-reports.tsv and has no funnel row at "
                         "filed or beyond -- %s cannot give it a state"
                         % (u["report"], FOUND))
        top = furthest(dated)
        kind, shown = found_state(u, top)
        # The date the shown state was read: the furthest row's, not the newest row's. A
        # later campaign that read a lower stage would otherwise date an older state.
        entries.append((FOUND_STATES.index(kind), dated[0][0], u["line"], u, shown,
                        top["as_of"]))
    entries.sort(key=lambda e: e[:3])
    counts = []
    for i, kind in enumerate(FOUND_STATES):
        n = sum(1 for e in entries if e[0] == i)
        if n:
            counts.append("%d %s" % (n, kind.replace(", re-measured", " and re-measured")))
    head = ("%d report%s: %s." % (len(entries), "" if len(entries) == 1 else "s",
                                   ", ".join(counts)) if entries else "No reports.")
    out = [FOUND_BEGIN, "", head, "",
           "| Tool | Report | State | As of |", "|---|---|---|---|"]
    for _k, _d, _l, u, shown, as_of in entries:
        out.append("| %s | [%s](https://github.com/%s/issues/%s) | %s | %s |"
                   % (u["finding"].replace("|", "\\|"), u["report"], u["owner"],
                      u["number"], shown, as_of))
    out += ["", FOUND_END]
    return "\n".join(out)


def doc_block(root):
    return "\n".join([BEGIN, "", "```", summarise(root), "```", "", END])


# The generated pages, in the order they are checked and written. A refusal names its
# page at the head of its sentence, so the self-test can tell one page from the other.
PAGES = [(DOC, BEGIN, END, doc_block), (FOUND, FOUND_BEGIN, FOUND_END, found_block)]


def read_doc(root, doc, begin, end_marker):
    path = os.path.join(root, doc)
    if not os.path.isfile(path):
        raise Broken("cannot read %s" % doc)
    with open(path, encoding="utf-8") as fh:
        body = fh.read()
    start, end = body.find(begin), body.find(end_marker)
    if start < 0 or end < 0 or end < start:
        raise Broken("%s does not carry the pair of markers this block lives between"
                     % doc)
    return path, body, start, end + len(end_marker)


def check_doc(root):
    rc, lines = 0, []
    for doc, begin, end, render in PAGES:
        one_rc, one = check_one_doc(root, doc, begin, end, render)
        rc, lines = max(rc, one_rc), lines + one
    return rc, lines


def check_one_doc(root, doc, begin, end_marker, render):
    _path, body, start, end = read_doc(root, doc, begin, end_marker)
    have, want = body[start:end], render(root)
    if have == want:
        return 0, ["ok: the block in %s is what the ledger renders" % doc]
    # Name the first line that differs rather than the two lengths: a figure edited
    # by one digit leaves the lengths equal, which is the edit this check exists for.
    hl, wl = have.splitlines(), want.splitlines()
    detail = []
    for i in range(max(len(hl), len(wl))):
        h = hl[i] if i < len(hl) else "(the page ends here)"
        w = wl[i] if i < len(wl) else "(the rendering ends here)"
        if h != w:
            detail = ["  first difference, line %d of the block:" % (i + 1),
                      "    the page:      %s" % h,
                      "    the ledger:    %s" % w]
            break
    return 1, ["REFUSE %s no longer matches the ledger. Regenerate it with "
               "`python3 spike/outcome-funnel.py --write-doc`." % doc] + detail


def write_doc(root):
    # Every block rendered before any page is written: a refusal while rendering the
    # second page must not leave the first rewritten and the second stale.
    pending = []
    for doc, begin, end_marker, render in PAGES:
        path, body, start, end = read_doc(root, doc, begin, end_marker)
        pending.append((doc, path, body[:start] + render(root) + body[end:]))
    for _doc, path, text in pending:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
    return 0, ["wrote the block in %s" % doc for doc, _p, _t in pending]


# --------------------------------------------------------------------------- tests

CAMPAIGNS_T = "dogfood/x\t2026-09-16\tfull\t9\tspike/x/RESULTS.md\n"
UPSTREAM_T = "# c\nowner/repo\t7\tstanding\tthing\n"
# For legs about a row that files nothing: with no filings in the tree, the containment
# rule stays quiet and the leg's own clause is the only thing that can redden it. Legs
# that left a filing in the ledger went red for two reasons at once, and a needle cannot
# tell which one it matched.
UPSTREAM_EMPTY = "# no filings in this tree\n"


def _tree(tmp, rows, campaigns=CAMPAIGNS_T, upstream=UPSTREAM_T, report=None,
          page=None, found=None):
    os.makedirs(os.path.join(tmp, "spike/x"), exist_ok=True)
    os.makedirs(os.path.join(tmp, "docs"), exist_ok=True)
    with open(os.path.join(tmp, "spike/x/RESULTS.md"), "w") as fh:
        fh.write("thing and other-thing were measured\n")
    with open(os.path.join(tmp, "spike/x/t.txt"), "w") as fh:
        fh.write("UNKNOWN  some_wall\n   the run refused; the target was thing\n")
    doc = {"schema": 1, "verdict": "FAIL", "explored": 3, "crash_points": 2}
    doc.update(report or {})
    with open(os.path.join(tmp, "spike/x/r.json"), "w") as fh:
        json.dump(doc, fh)
    for name, body in (("spike/outcome-funnel-campaigns.tsv", campaigns),
                       ("spike/outcome-funnel.tsv", rows),
                       ("spike/upstream-reports.tsv", upstream)):
        with open(os.path.join(tmp, name), "w") as fh:
            fh.write(body)
    # The pages after the records, so RENDER can read them. Rendering runs here, outside
    # the selftest's own try: a leg asks for RENDER only where its tree renders.
    if page is RENDER:
        page = "# page\n\n" + doc_block(tmp) + "\n"
    if found is RENDER:
        found = "# found\n\n" + found_block(tmp) + "\n"
    with open(os.path.join(tmp, DOC), "w") as fh:
        fh.write(page if page is not None
                 else "# page\n\n" + BEGIN + "\nstale\n" + END + "\n")
    with open(os.path.join(tmp, FOUND), "w") as fh:
        fh.write(found if found is not None
                 else "# found\n\n" + FOUND_BEGIN + "\nstale\n" + FOUND_END + "\n")
    return tmp


def _row(**kw):
    f = {"campaign": "dogfood/x", "target": "thing", "stage": "filed",
         "verdict": "fail", "stop": "awaiting", "report": "owner/repo#7",
         "evidence": "spike/x/r.json", "as_of": "2026-09-16", "note": "n"}
    f.update(kw)
    return "\t".join(f[k] for k in ("campaign", "target", "stage", "verdict", "stop",
                                    "report", "evidence", "as_of", "note")) + "\n"


def _wall(**kw):
    """A row that stopped at a wall, for the clauses about records that are not reports."""
    f = {"stage": "attempted", "verdict": "unknown", "stop": "wall", "report": "-",
         "as_of": "-", "evidence": "spike/x/t.txt", "note": "some_wall"}
    f.update(kw)
    return _row(**f)


# The ledger `found_block` is held to (#713): every state a report can render, and the
# two orders of rows that tell a correct pick of the furthest row from a wrong one --
# owner/a's lower row comes first, owner/b's higher row comes first. A rendering that takes
# the first row, the last row, or acknowledged for fixed, differs from FOUND_WANT.
CAMPAIGNS_F = ("dogfood/x\t2026-09-16\tfull\t9\tspike/x/RESULTS.md\n"
               "dogfood/y\t2026-09-17\tfull\t-\tspike/x/RESULTS.md\n"
               "dogfood/z\t2026-09-18\tfull\t-\tspike/x/RESULTS.md\n"
               "dogfood/w\t2026-09-18\tfull\t-\tspike/x/RESULTS.md\n")
ROWS_F = (
    _row(target="a", report="owner/a#1", stage="filed", stop="awaiting", as_of="2026-09-16")
    + _row(campaign="dogfood/y", target="b", report="owner/b#2", stage="fixed", stop="-",
           as_of="2026-09-20")
    + _row(campaign="dogfood/y", target="a", report="owner/a#1", stage="revalidated",
           stop="discussing", as_of="2026-09-21")
    + _row(target="b", report="owner/b#2", stage="filed", stop="awaiting", as_of="2026-09-16")
    + _row(target="c", report="owner/c#3", stage="acknowledged", stop="-", as_of="2026-09-18")
    + _row(target="d", report="owner/d#4", stage="filed", stop="declined", as_of="2026-09-19")
    + _row(target="e", report="owner/e#5", stage="filed", stop="discussing", as_of="2026-09-17")
    + _row(target="f", report="owner/f#6", stage="filed", stop="withdrawn", as_of="2026-09-16")
    # owner/g: the latest campaign read a lower stage than the one before it -- the state is
    # the furthest row's, and so is its date, not the latest campaign's (R1 of the diff).
    + _row(target="g", report="owner/g#7", stage="filed", stop="awaiting", as_of="2026-09-16")
    + _row(campaign="dogfood/y", target="g", report="owner/g#7", stage="fixed", stop="-",
           as_of="2026-09-22")
    + _row(campaign="dogfood/z", target="g", report="owner/g#7", stage="acknowledged",
           stop="discussing", as_of="2026-09-25")
    # owner/h: two rows at the furthest stage, written in the file against their dates --
    # the later campaign's reading wins, whatever the file order.
    + _row(campaign="dogfood/z", target="h", report="owner/h#8", stage="acknowledged",
           stop="discussing", as_of="2026-09-24")
    + _row(target="h", report="owner/h#8", stage="filed", stop="awaiting", as_of="2026-09-16")
    + _row(campaign="dogfood/y", target="h", report="owner/h#8", stage="acknowledged",
           stop="-", as_of="2026-09-23")
    # owner/i: the same two-rows-at-one-stage, written in date order -- a rendering that
    # keeps the first row it met at the top stage differs here (R2 of the diff).
    + _row(target="i", report="owner/i#9", stage="filed", stop="awaiting", as_of="2026-09-16")
    + _row(campaign="dogfood/y", target="i", report="owner/i#9", stage="acknowledged",
           stop="discussing", as_of="2026-09-17")
    + _row(campaign="dogfood/z", target="i", report="owner/i#9", stage="acknowledged",
           stop="-", as_of="2026-09-26")
    # owner/j: two rows at the top stage on one date, as ImageMagick's refix and patch3 are;
    # the later line is the later reading.
    + _row(target="j", report="owner/j#10", stage="filed", stop="awaiting", as_of="2026-09-16")
    + _row(campaign="dogfood/z", target="j", report="owner/j#10", stage="acknowledged",
           stop="discussing", as_of="2026-09-18")
    + _row(campaign="dogfood/w", target="j", report="owner/j#10", stage="acknowledged",
           stop="-", as_of="2026-09-27"))
UPSTREAM_F = ("# f\nowner/a\t1\tstanding\ttool a\nowner/b\t2\tstanding\ttool b\n"
              "owner/c\t3\tstanding\ttool c\nowner/e\t5\tstanding\ttool e\n"
              "owner/d\t4\tstanding\ttool | d\nowner/f\t6\twithdrawn\ttool f\n"
              "owner/g\t7\tstanding\ttool g\nowner/h\t8\tstanding\ttool h\n"
              "owner/i\t9\tstanding\ttool i\nowner/j\t10\tstanding\ttool j\n")
FOUND_WANT = "\n".join([
    FOUND_BEGIN, "",
    "10 reports: 1 fixed upstream and re-measured, 2 fixed upstream, 4 acknowledged, "
    "2 filed, 1 withdrawn.",
    "",
    "| Tool | Report | State | As of |",
    "|---|---|---|---|",
    "| tool a | [owner/a#1](https://github.com/owner/a/issues/1) | fixed upstream, re-measured (discussing) | 2026-09-21 |",
    "| tool b | [owner/b#2](https://github.com/owner/b/issues/2) | fixed upstream | 2026-09-20 |",
    "| tool g | [owner/g#7](https://github.com/owner/g/issues/7) | fixed upstream | 2026-09-22 |",
    "| tool c | [owner/c#3](https://github.com/owner/c/issues/3) | acknowledged | 2026-09-18 |",
    "| tool h | [owner/h#8](https://github.com/owner/h/issues/8) | acknowledged (discussing) | 2026-09-24 |",
    "| tool i | [owner/i#9](https://github.com/owner/i/issues/9) | acknowledged | 2026-09-26 |",
    "| tool j | [owner/j#10](https://github.com/owner/j/issues/10) | acknowledged | 2026-09-27 |",
    "| tool e | [owner/e#5](https://github.com/owner/e/issues/5) | filed (discussing) | 2026-09-17 |",
    "| tool \\| d | [owner/d#4](https://github.com/owner/d/issues/4) | filed (declined) | 2026-09-19 |",
    "| tool f | [owner/f#6](https://github.com/owner/f/issues/6) | withdrawn | 2026-09-16 |",
    "", FOUND_END])


def _found_as_wanted(root):
    have = found_block(root)
    if have == FOUND_WANT:
        return 0, ["found_block renders the ledger as wanted"]
    return 1, ["found_block rendered something else:"] + \
              ["  " + line for line in have.splitlines()]


# Every refusal `check`, `check_doc`, `found_block` and `summary` can raise, seen red once.
# Measured when this list was first written by tracing each leg and collecting the line it
# reddened; every clause added since came with its leg. No count is written here: the one
# that was went stale the first time a clause was added. A clause without a leg here is a
# clause nobody has watched fail (#342).
#
# Some legs redden more than one clause -- a row with an invalid stage also fails the
# containment sweep, because an invalid row is skipped before its report is collected --
# and two of them redden the same clause through different branches of
# `stage_from_report`. That is why each leg is matched on the clause's own sentence and
# not on the exit code alone: an extra refusal cannot make a leg pass, because the
# sentence it looks for is the one only that clause writes.
CAMPAIGNS_Y = CAMPAIGNS_T + "dogfood/y\t2026-09-17\tfull\t-\tspike/x/RESULTS.md\n"
LEGS = [
    ("green", dict(rows=_row()), 0, "each holding to the evidence"),
    # --- the campaigns file
    ("a coverage nobody can count over",
     dict(rows=_row(), campaigns="dogfood/x\t2026-09-16\tsome\t9\tspike/x/RESULTS.md\n"),
     1, "is not one of"),
    ("a date --since cannot read",
     dict(rows=_row(), campaigns="dogfood/x\tSeptember\tfull\t9\tspike/x/RESULTS.md\n"),
     1, "is not YYYY-MM-DD"),
    ("a candidate count that is neither a number nor absent",
     dict(rows=_row(), campaigns="dogfood/x\t2026-09-16\tfull\tsome\tspike/x/RESULTS.md\n"),
     1, "neither a number nor"),
    ("a campaign whose record is not in the repository",
     dict(rows=_row(), campaigns="dogfood/x\t2026-09-16\tfull\t9\tspike/x/gone.md\n"),
     1, "does not name a file"),
    ("the same campaign listed twice",
     dict(rows=_row(), campaigns=CAMPAIGNS_T + CAMPAIGNS_T), 2, "is listed twice"),
    # --- parsing
    ("a row written with one field too few",
     dict(rows="dogfood/x\tthing\tfiled\tfail\tawaiting\towner/repo#7\tspike/x/r.json\tn\n"),
     2, "tab-separated field(s), want 9"),
    ("both records empty", dict(rows="", upstream="# nothing\n"), 2, "both records are empty"),
    # --- the row's own fields
    ("a campaign the campaigns file does not list",
     dict(rows=_row(campaign="dogfood/z")), 1, "no such campaign"),
    ("a stage outside the ladder", dict(rows=_row(stage="shipped")), 1, "is not one of"),
    ("a verdict outside the set", dict(rows=_row(verdict="maybe")), 1, "verdict 'maybe'"),
    ("a stop outside the set", dict(rows=_row(stop="bored")), 1, "stop 'bored'"),
    ("judged without a verdict",
     dict(rows=_wall(stage="judged")), 1, "needs a verdict of pass or fail"),
    ("novel claimed over a PASS",
     dict(upstream=UPSTREAM_EMPTY, rows=_row(stage="novel", verdict="pass", stop="-", report="-", as_of="-"),
          report={"verdict": "PASS", "explored": 3, "crash_points": 2}),
     1, "about a counterexample"),
    ("filed with no upstream report",
     dict(upstream=UPSTREAM_EMPTY, rows=_row(report="-")), 1, "without an upstream report"),
    ("filed with no reading date", dict(rows=_row(as_of="-")), 1, "needs as_of"),
    ("a reading date on a row that never filed",
     dict(rows=_wall(as_of="2026-09-16")), 1, "as_of is for rows that reached filed"),
    ("a report identifier that is not owner/repo#N",
     dict(rows=_row(report="repo-7")), 1, "is not owner/repo#N"),
    ("a report this project never filed",
     dict(rows=_row(report="someone/else#1")), 1, "not in spike/upstream-reports.tsv"),
    # --- the evidence
    ("the evidence does not exist",
     dict(rows=_row(evidence="spike/x/gone.json")), 1, "does not name a file"),
    ("a written record that never names the target",
     dict(rows=_wall(target="absent-tool", evidence="spike/x/RESULTS.md", note="n")),
     1, "names this target neither in its text nor in its path"),
    ("a transcript whose refusal the note does not name",
     dict(rows=_wall(note="a different wall entirely")), 1, "the evidence refuses"),
    ("a report whose counters cannot be read",
     dict(rows=_row(), report={"explored": "several"}), 1, "readable counters"),
    ("the verdict is flipped away from the report",
     dict(upstream=UPSTREAM_EMPTY, rows=_row(verdict="pass", stage="judged", stop="-", report="-", as_of="-")),
     1, "the row says pass"),
    ("an operation that performed nothing is called a verdict",
     dict(upstream=UPSTREAM_EMPTY, rows=_row(stage="judged", verdict="pass", stop="-", report="-", as_of="-"),
          report={"verdict": "PASS", "explored": 0, "crash_points": 0}),
     1, "establishes attempted"),
    ("a wall is claimed to have explored worlds",
     dict(upstream=UPSTREAM_EMPTY, rows=_row(stage="explored", verdict="unknown", stop="wall", report="-",
                    as_of="-"),
          report={"verdict": "UNKNOWN", "unknown_reason": "some_wall", "explored": 0,
                  "crash_points": 0}, ),
     1, "establishes attempted"),
    # --- across rows
    ("the same target twice in one campaign", dict(rows=_row() + _row()), 1,
     "already recorded on line"),
    ("two campaigns of one date both claiming a filing",
     dict(rows=_row() + _row(campaign="dogfood/y"),
          campaigns=CAMPAIGNS_T + "dogfood/y\t2026-09-16\tfull\t-\tspike/x/RESULTS.md\n"),
     1, "both carry it at filed or beyond"),
    ("the filing claimed twice",
     dict(rows=_row() + _row(campaign="dogfood/y"), campaigns=CAMPAIGNS_Y), 1,
     "claims the filing twice"),
    # The one leg that keeps a filing in the ledger deliberately: an empty ledger is
    # exactly what would make this clause unreachable.
    ("a report in the ledger that reaches no row",
     dict(rows=_row(stage="judged", verdict="fail", stop="known", report="-",
                    as_of="-")),
     1, "reaches no row here"),
    # --- the records themselves, and the other entrance
    ("the funnel is not there at all",
     dict(rows=_row(), remove="spike/outcome-funnel.tsv"), 2, "cannot read funnel"),
    ("a directory written where a record belongs",
     dict(rows=_wall(evidence="spike/x", note="some_wall"), upstream=UPSTREAM_EMPTY),
     1, "could not be read as a record"),
    ("evidence that climbs out of the repository",
     dict(rows=_wall(evidence="spike/x/../../../outside.txt"),
          upstream=UPSTREAM_EMPTY),
     1, "resolves outside this repository"),
    ("the page's block is not what the ledger renders",
     dict(rows=_row(), fn=check_doc), 1, "REFUSE docs/outcome-funnel.md no longer matches"),
    ("the page has lost the markers the block lives between",
     dict(rows=_row(), fn=check_doc, page="# page\n\nno markers here\n"),
     2, "docs/outcome-funnel.md does not carry the pair of markers"),
    ("the page is not there at all",
     dict(rows=_row(), fn=check_doc, remove="docs/outcome-funnel.md"),
     2, "cannot read docs/outcome-funnel.md"),
    # --- docs/found.md (#713). Each with the funnel page rendered, so a refusal of that
    # page cannot be what the leg matched.
    ("both pages are what the ledgers render",
     dict(rows=_row(), fn=check_doc, page=RENDER, found=RENDER),
     0, "ok: the block in docs/found.md is what the ledger renders"),
    ("the found page's block is not what the ledgers render",
     dict(rows=_row(), fn=check_doc, page=RENDER), 1, "REFUSE docs/found.md no longer matches"),
    ("the found page has lost its markers",
     dict(rows=_row(), fn=check_doc, page=RENDER, found="# found\n\nno markers here\n"),
     2, "docs/found.md does not carry the pair of markers"),
    ("the found page is not there at all",
     dict(rows=_row(), fn=check_doc, page=RENDER, remove="docs/found.md"),
     2, "cannot read docs/found.md"),
    ("a filed report whose only row is below filed has no state to render",
     dict(rows=_row(stage="judged", stop="known"), fn=check_doc, page=RENDER),
     2, "has no funnel row at filed or beyond"),
    ("the ledger says withdrawn and the funnel's furthest row does not",
     dict(rows=_row(), upstream="# c\nowner/repo\t7\twithdrawn\tthing\n"),
     1, "disagree on whether it was withdrawn"),
    ("the funnel's furthest row says withdrawn and the ledger does not",
     dict(rows=_row(stop="withdrawn")),
     1, "disagree on whether it was withdrawn"),
    ("withdrawn is read off the furthest row, not off any row",
     dict(rows=_row(stop="withdrawn") + _row(campaign="dogfood/y", stage="acknowledged",
                                             stop="-"),
          campaigns=CAMPAIGNS_Y, upstream="# c\nowner/repo\t7\twithdrawn\tthing\n"),
     1, "disagree on whether it was withdrawn"),
    ("withdrawn on the furthest row and in the ledger agree, whatever the first row says",
     dict(rows=_row() + _row(campaign="dogfood/y", stage="acknowledged", stop="withdrawn"),
          campaigns=CAMPAIGNS_Y, upstream="# c\nowner/repo\t7\twithdrawn\tthing\n"),
     0, "each holding to the evidence"),
    ("one report is one report",
     dict(rows=_row(), fn=lambda root: (0 if "\n1 report: 1 filed.\n" in found_block(root)
                                        else 1, [found_block(root)])),
     0, "1 report: 1 filed"),
    ("an empty report ledger renders no reports",
     dict(rows=_row(stage="judged", stop="known", report="-"), upstream=UPSTREAM_EMPTY,
          fn=lambda root: (0 if "\nNo reports.\n" in found_block(root) else 1,
                           [found_block(root)])),
     0, "No reports."),
    ("every state the found page can show, from both orders of rows",
     dict(rows=ROWS_F, campaigns=CAMPAIGNS_F, upstream=UPSTREAM_F, fn=_found_as_wanted),
     0, "renders the ledger as wanted"),
    # --- the entrances `summary` opens
    ("a campaign nobody can summarise",
     dict(rows=_row(), fn=lambda root: (0, [summarise(root, campaign="nope")])),
     2, "no such campaign"),
    ("a --since that is not a date",
     dict(rows=_row(), fn=lambda root: (0, [summarise(root, since="yesterday")])),
     2, "--since wants YYYY-MM-DD"),
]


def selftest(root):
    """Every clause of `check`, seen red once. A checker nobody has watched fail is a
    checker whose predicates are untested (#342)."""
    failed = 0
    for name, tree, want, needle in LEGS:
        with tempfile.TemporaryDirectory() as tmp:
            tree = dict(tree)
            remove = tree.pop("remove", None)
            fn = tree.pop("fn", check)
            _tree(tmp, **tree)
            if remove:
                os.remove(os.path.join(tmp, remove))
            try:
                rc, lines = fn(tmp)
            except Broken as exc:
                rc, lines = 2, ["BROKEN " + str(exc)]
            body = "\n".join(lines)
            if rc != want or needle not in body:
                failed += 1
                print("== self-test FAILED: %s -- exited %d wanting %d" % (name, rc, want))
                print("\n".join("     | " + line for line in lines))
            else:
                print("== ok: %s" % name)
    # The committed tree, last: a red leg above proves the rule, this proves the data.
    try:
        rc, lines = check(root)
    except Broken as exc:
        rc, lines = 2, ["BROKEN " + str(exc)]
    if rc != 0:
        failed += 1
        print("== self-test FAILED: the committed records do not agree")
        print("\n".join("     | " + line for line in lines))
    else:
        print("== ok: the committed records agree")
    return 2 if failed else 0


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("mode", nargs="?", default="check", choices=["check", "summary"])
    ap.add_argument("--campaign")
    ap.add_argument("--since")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--check-doc", action="store_true")
    ap.add_argument("--write-doc", action="store_true")
    args = ap.parse_args(argv)
    root = repo_root()
    try:
        if args.selftest:
            return selftest(root)
        if args.check_doc:
            rc, lines = check_doc(root)
        elif args.write_doc:
            rc, lines = write_doc(root)
        elif args.mode == "summary":
            print(summarise(root, args.campaign, args.since))
            return 0
        else:
            rc, lines = check(root)
    except Broken as exc:
        print("BROKEN %s" % exc)
        return 2
    print("\n".join(lines))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
