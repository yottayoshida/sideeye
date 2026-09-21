# 0084 — The adoption path is measured in a container, and an adoption failure is not a funnel row

Status: Accepted (2026-09-21)

## Context

`docs/ci-quickstart.md:7` tells a project how to adopt Sideeye: *"copy the workflow and
`install-sideeye.sh`, and swap the define."* `quickstart-release.yml` runs that script on Linux
and macOS — against `target-clean` and `target-bug`, two toys this repository wrote for the page.
Fourteen dogfood runs have measured real targets, and every one of them mounted a release tarball
the operator had already unpacked (`spike/dogfood/2026-09-16-userview-3/SELECTION.md`). The
sentence had never been tried on a real project.

Two questions had to be answered before a run could be designed.

**Where.** Three places were available: this repository's own CI, a container, or a pull request
adding a Sideeye gate to the target's own CI. The owner chose the container (2026-09-21). Running
other projects' builds in this repository's CI buys little — the claim about what a runner has is
already tested by `quickstart-release.yml`, and the installer does not care what the target is —
and a pull request to a stranger's repository is a different undertaking from a bounded run.

**Where an adoption failure is recorded.** The outcome funnel (#605, ADR 0070) begins at
`attempted`: *"the target reached a define and the engine ran against it"*
(`docs/outcome-funnel.md`). A target that never got Sideeye installed does not satisfy that and
has no row. The obvious repair — a stage before `attempted` — is not available: `STAGES` is an
ordered list, `RANK` derives from it, and `summary` slices it; a stage at the front would make
all 81 existing rows implicitly claim they cleared it, which is false for every one of them,
because they mounted a tarball instead.

## Decision

**The adoption path is measured in a pinned container, and what that costs is stated rather than
implied.** The image installs Sideeye by running the vendored `install-sideeye.sh` at build time,
where there is a network; the explores run `--network none`, as every dogfood run does. The image
adds `curl`, which `debian:trixie-slim` lacks and a GitHub runner has, and it trusts this
machine's intercepting proxy CA — without which every HTTPS call in a container here fails. **That
CA is where the container stops standing in for a runner**, and it means this run can say nothing
about the page's claim that a runner has what the script needs. `quickstart-release.yml` is where
that is answered.

**An adoption failure is not a funnel row. The slate is defined as the targets that cleared
adoption**, and a target that did not is a rejection row in the campaign's `SELECTION.md`. This
keeps `coverage=full` true rather than approximately true: `COVERAGE` is the closed set
`{full, filings-only}` and the checker validates membership only, so a campaign that lost a target
at adoption and still wrote `full` would pass CI while being false in a way nothing could catch.

**What this costs, written here because it is the point of the decision:** the funnel cannot count
"adoption → verdict → report" end to end. The first leg lives in the campaign's own record, and
reading the chain takes two pages and a person. #605 bought a single page that counts a funnel;
this campaign does not extend it.

**A verdict is tied to the installed binary by file, not by trust.** The report carries no engine
version — only `contract_version`, which a local build of main shares — so nothing inside it
distinguishes the release from a hand-built binary. `install-sideeye.sh`'s stdout is captured to
`/install.path`, the explore script reads that file rather than naming a path, and what it read is
written into the run's transcripts.

## Alternatives considered

- **Add a stage before `attempted`.** Rejected: it would make 81 committed rows claim something
  nobody measured.
- **Add an `engine` column to `outcome-funnel-campaigns.tsv`.** Rejected for this campaign:
  filling it honestly means re-reading twenty campaigns' records, and the question here does not
  need it.
- **Write `coverage` as `full` and note the caveat in prose.** Rejected — the checker would stay
  green over a false value. Defining the slate as the targets that cleared adoption makes the
  value true instead.
- **Run in this repository's CI, or open a pull request against the target.** Both declined by the
  owner, above.
- **Install without the proxy CA and record "adoption failed".** Rejected on measurement: with a
  control in the same run, `https://example.com` fails identically and the certificate offered for
  `api.github.com` is issued by the corporate proxy's own CA rather than by a public one. Recording that as a failure of the
  procedure would have been false.

## Consequences

- The first run under this decision reached one named wall (`oracle_missed_operation`, lefthook,
  statically linked) and no verdict. That is a result about reach, not a failed run.
- Two adoption costs the pages do not state were found, and both cost a round of *"Change the
  define"* with no line named: `lefthook install` must run inside the repository, so the define
  needs a `cwd` the template does not show; and `cwd` is resolved **before** the state directory
  is made, deliberately, so a `cwd` the define's own setup would create can never resolve. Neither
  is fixed here — this campaign measures.
- `docs/ci-quickstart.md` and `install-sideeye.sh` are unchanged. A measurement that also repairs
  what it measures cannot say what the thing measured was like.
