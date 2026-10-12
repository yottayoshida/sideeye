# 0125 — A daily job reads the trackers and proposes the found page as one pull request

- **Status:** Accepted (2026-10-12)
- **Refs:** #713 (the found page); ADR 0070 (the outcome funnel it renders from); #720 (the page
  called timewarrior fixed upstream while its issue had no reply).
- **Scope:** `spike/upstream-live.py`, `spike/upstream-live.tsv`, `spike/campaign-versions.tsv`,
  `spike/outcome-funnel.py` (`found_block` and the checks on the two new files),
  `.github/workflows/upstream-watch.yml`, `docs/found.md`.

## Context

`docs/found.md` showed the furthest stage the ledgers recorded for each report, read whenever
someone remembered to run `spike/upstream-report-status.sh` and edit `spike/outcome-funnel.tsv`.
Forty-three reports outgrew that: a tracker could close, a fix pull request could merge, and the
page said nothing until a session went looking. The page also named a tool and a state and
nothing else — not what the tool is, what the issue says, whether anyone is working on a fix, or
which Sideeye found it.

## Decision

- **The trackers' state is a committed snapshot.** `spike/upstream-live.py fetch` reads every
  report in `spike/upstream-reports.tsv`, and every issue the repository's owner opened on someone
  else's repository that names Sideeye and is not in that ledger yet, and writes
  `spike/upstream-live.tsv`. The page renders from it, so `--check-doc` stays offline and an
  upstream event cannot turn an unrelated pull request red. The snapshot holds only what the
  page shows and no reading date — a date would change daily and open a pull request daily.
- **A tracker's word is shown beside the record's, never written into it.** The job does not move
  a stage in `spike/outcome-funnel.tsv`. qpdf closed its report as completed and declined the fix;
  a stage taken from the tracker would have called it fixed.
- **Unrecorded filings are listed, not recorded.** A filing the search finds outside the ledger
  appears on the page marked as such, and the job's pull request says to record it. The tool's
  name, the campaign and the evidence are judgements the job cannot make. The mark is the body
  naming Sideeye, which the report template's Disclosure requires; an issue that does not is not
  a report as far as this job can tell.
- **One pull request at a time, opened with the job's own token.** Each run starts from main on a
  fresh branch and compares only the two generated files: the same as main closes the open one,
  the same as the open one keeps it, anything else opens a new one and closes the old with its
  branch. The pull request's text names tools and fields, never an `owner/repo#N` or an issue URL,
  which would put this project on that issue's timeline every time it changed.
- **CI on that pull request waits for approval.** A pull request opened with `GITHUB_TOKEN` starts
  its workflows in an approval-required state; the owner approves and merges. This needs the
  repository setting *Allow GitHub Actions to create and approve pull requests*, on before this
  job first runs; without it `gh pr create` is refused, and the job deletes the branch it pushed
  and fails.
- **The version is per campaign, by hand** (`spike/campaign-versions.tsv`), required of every
  campaign that filed a report.

## Alternatives considered

- **A personal access token**, so CI starts unattended: one more credential with an expiry, held
  for a job whose output a person merges anyway. Taken if approval-required runs ever stop
  counting as the protected branch's required checks.
- **Starting CI with `workflow_dispatch` from the job**: the same job names would run twice on one
  commit, which GitHub warns can leave required checks ambiguous.
- **Reusing one branch and merging main into it**: generated files conflict, a `GITHUB_TOKEN` push
  cannot carry main's workflow changes, and a closed pull request leaves the branch behind.
- **Reading the trackers while rendering**: the page check would depend on the network and on
  upstream.
- **Deriving the version from the campaign's date**: three tags went out on 2026-08-13, and the
  2026-08-15 re-measurement ran on main the day v0.8.0 was tagged.

## Consequences

- The page on main is as current as the last merged upstream-watch pull request.
- GitHub disables a public repository's scheduled workflows after sixty days without activity;
  the job stops silently with them.
- A filing that does not name Sideeye in its body and is not recorded stays off the page.
- `spike/upstream-report-status.sh` stays: it reads comment counts and last activity, which the
  snapshot leaves out because they change without anything happening to a report.
