# 0103 — Agent skills ship from this repository in the Agent Skills layout

- **Status:** Accepted (2026-10-09)
- **Refs:** #716 (from the 2026-10-05 whole-product review); `docs/scouting.md` (the scouting
  method); `spike/upstream-report-template.md` (the shape of an upstream report); #763 and
  #767 (the MCP tools the skills name).
- **Scope:** `skills/sideeye-scout/SKILL.md`, `skills/sideeye-triage/SKILL.md`,
  `skills/sideeye-report/SKILL.md`, `spike/check-skills.py`, `.github/workflows/ci.yml`,
  `README.md`, `spike/check-readme-shape.sh`.

## Context

Three ways of working with Sideeye had been written down and used: scouting a tool for a
define (`docs/scouting.md`), taking a FAIL on one's own code to a fix, and drafting a report
for another project's maintainers (`spike/upstream-report-template.md`, 280 lines). An agent
could follow them only when someone pointed it at this repository, and the two longer ones
were written as records — their measured numbers and relative links to other records are
what makes them evidence, and what makes them unreadable outside the tree.

## Decision

**Three skills in the Agent Skills layout, `skills/<name>/SKILL.md`, installed with
`npx skills@1.7.1 add yottayoshida/sideeye`.**

- **The layout, and one way to install it.** A directory per skill holding `SKILL.md` with a
  `name` and a `description` in its frontmatter is what Claude Code and the other agents the
  `skills` installer knows read; the installer copies them into the agent's own directory.
  The installer's version is pinned in the README: it runs from npm with the reader's
  permissions, and an unpinned name runs whatever was published last.
- **Names carry `sideeye-`.** `scout`, `triage` and `report` are ordinary words a user's own
  skills may already use, and an install that collides overwrites one or the other.
- **A skill is a procedure and its prohibitions, not a record.** The copy leaves the
  repository, so every link is an absolute URL into `main`, and no measured number is
  written into a skill — numbers live in the records they came from, as `docs/scouting.md`
  already holds. `sideeye-scout` keeps the model floor as a sentence, because it changes what
  an agent should do.
- **The skills install from `main`, ahead of the binary a reader may have.** An MCP tool
  newer than the last release is named as "where the server lists it", with the command line
  as the way when it does not; the CLI commands the skills use are all in v1.10.0.
- **The report skill starts by reading the project's rules and stops when they forbid
  LLM-written or tool-generated reports**, and never files: it hands the person a draft to
  approve word for word, or, where a project forbids that, says the report is theirs to
  write — and translates the person's own text only where the policy itself allows a machine
  translation.
- **`spike/check-skills.py` holds the copies to the code they drive**, in CI with its
  selftest first: every directory under `skills/` carrying the `sideeye-` prefix, the
  frontmatter the format requires, every `sideeye <command>` against the usage lines and
  every flag after it against that command's, every name a skill borrows from the source —
  MCP tools and their arguments, refusal reasons, define keys, `SIDEEYE_*` variables —
  against the source, and every link into this repository against `main`'s tree. The tool,
  reason and key sets are the contract-freeze gate's own definitions
  (`spike/freeze-audit/surface-sets.sh`). Nothing else reads a skill against the code once
  it is installed.

## Alternatives considered

- **A Claude Code plugin marketplace as well.** Two ways to install meant two things to keep
  current, and a plugin's copy is refreshed only when its version moves — measured on another
  project of this maintainer's, where a fix sat unreached until a version bump.
- **The spike documents as skills, unchanged.** 280 lines of a record, linked to other records
  by relative path; an installed copy would resolve none of them.
- **Measuring the skills in CI by running an agent.** A run is slow, costs money and is not
  deterministic; the check holds what can drift mechanically, and a person runs an agent
  when a skill changes.

## Consequences

Measured on 2026-10-09:

- `npx skills@1.7.1 add <checkout> -g -a claude-code -y` into an empty `HOME` installs the
  three, each byte for byte the file in the tree.
- One run each (n=1, not a rate) of a fresh Claude Sonnet 5.5 agent given only the installed
  skill, on a 129-line key-value tool in C written for the purpose, whose `set` truncates its
  store before rewriting it: **scout** wrote a define and a fail-closed checker of its own
  and reached `FAIL 3 of 7`; **triage** changed the tool to write a temporary file, flush it
  and rename it over the store, saw the saved case answer `case_no_longer_applies` (exit 2),
  and reached `PASS 9/9`; **report**, beside a checkout whose `CONTRIBUTING` closes
  LLM-written issues, stopped at its first step and drafted nothing. The same agent given the
  same request **without** the skill also stopped and drafted nothing, so this run does not
  show the report skill's first step doing anything Sonnet 5.5 does not do unprompted.
  The scout and report runs each named a thing their skill left unsaid — that a define
  passes no environment, and what to do with the measured facts under a ban — and each skill
  gained a sentence for it. The review after the runs corrected sentences that were wrong
  although no run tripped on them: `replay`, like `explore`, needs a second witness or `--allow-unverified` to say
  PASS, and its refusal reads `case_no_longer_applies`; the state directory a define names is
  emptied for every world, so it is never the person's real data.
- Not measured: the report skill's draft where no policy forbids one; any model but Sonnet
  5.5; any agent but Claude Code.

A rename of a command, a flag or an MCP tool now reddens `check-skills.py` until the skill
follows. If by 2027-04-09 nobody has reported using the skills, delete them, the check and its
CI job.
