# 0080 — The release quickstart is a copied script, and its macOS lane claims less

Status: Accepted (2026-09-20)

## Context

#620 asks for a documented, CI-tested path from an empty GitHub Actions runner to
`sideeye explore` using a published release artifact, with no Zig compiler and no build of
Sideeye. It deliberately does not pre-select a surface: "A small install script, a reusable
workflow, or an action are all possible surfaces. The smallest durable one should win."

Two facts shape the answer, both measured rather than assumed. The release publishes three
assets — `x86_64-linux`, `aarch64-linux`, `aarch64-macos` — and GitHub serves a `sha256`
digest for each through the releases API, which an **unauthenticated** `curl` can read
(measured 2026-09-20; `gh` cannot, without a token, which is what `docs/cli.md`'s existing
instructions use). And a tarball unpacks flat, binary beside shim, which is the layout
`findShim` (#78) searches before `../lib` — so a release consumer passes no `--shim` at all.

## Decision

**The surface is a shell script committed beside the quickstart's define, which an adopter
copies along with the workflow.** Not an action, not a reusable workflow.

**The macOS lane installs the release asset and explores a target with a real bug, with no
completeness oracle, and says so.** It does not use `fs_usage`.

### Why a copied script

This repository's quickstart doctrine is already "the workflow IS the documentation, and CI
keeps it honest" (`docs/ci-quickstart.md`). A copied script extends that: the correctness
lives in one file that this repository's CI executes on every push, and an adopter takes it
the way they take the workflow. It adds no compatibility surface — nothing outside this
repository is pinned to it, because a copy is a copy.

### Why the macOS lane claims less

`--oracle-fs-usage` would give macOS a verified PASS, and #620 asks for it "where the runner
permits it". Three measured reasons say not here:

1. **This repository has already ruled on it.** `spike-fsusage.yml`'s first paragraph: "This
   is a measurement apparatus, not standing CI — it triggers only on its own spike branch and
   by hand, and **it must never be made a required check**." A standing lane resting on
   `sudo -n` contradicts that ruling rather than extending it.
2. **A hard 96-byte ceiling on the state root.** `--oracle-fs-usage` refuses before the
   observer starts when the resolved state path exceeds it (`src/main.zig`,
   `fsu_sentinel_max_root = 156 − 20 − 40`), because `fs_usage` cuts long pathnames from the
   left. A quickstart whose state path a reader is invited to change would carry an
   invisible length rule.
3. **The clean lane's shape is unmeasured under that oracle.** The existing macOS
   verified-PASS evidence is an `open`/`write`/`close` toy. ADR 0031's `fs_usage` oracle
   turns narrowings into refusals, and a clean define that renames has never been measured
   reaching PASS through it.

What the lane does instead is exact rather than degraded: it explores a target with a planted
bug and gates on the FAIL. **A FAIL needs no oracle** — measured on macOS, 2026-09-20, with
neither `--oracle` nor `--allow-unverified` — and `ci.yml` already says why where it makes the
same choice: "a FAIL is a verdict on its own evidence." The verified-PASS path is exercised on
Linux, under `strace`, and the page says plainly that macOS carries no PASS evidence here.

## Alternatives considered

| rejected | why |
|---|---|
| **A composite action** (`uses: yottayoshida/sideeye@vX`) | Three lines for the adopter, and a **sixth public surface** for this repository. `docs/contract-freeze.md` declares five and records every break of each on its own ruling; an action's inputs and its version compatibility would join them. #620 explicitly declined to pre-select one. |
| **A reusable workflow** (`workflow_call`) | Takes the whole job, so an adopter's checkout, cache and matrix have to be arranged around it, and its inputs are the same weight of contract as an action's. |
| **Inline YAML only** | The install logic would be duplicated across the Linux and macOS lanes, so correctness would live in two places that can drift — the shape #620 warns against ("do not introduce an installer whose correctness is weaker than the existing tarball instructions"). |
| **`gh api`, as `docs/cli.md` documents** | `gh` needs a token even for a public read, so a copied script would fail for an adopter whose job has none and for anyone running it outside `gh auth login`. Unauthenticated `curl` reads the same digests (measured). The page's commands stay as they are — they are for a person at a terminal, and this is for a runner. |
| **Publishing `SHA256SUMS` or signing** | ADR 0061 already decided against the first (same trust root in a second file) and left signature/provenance deliberately unbuilt. This change consumes what exists and does not reopen it. |
| **A new self-contained target under `docs/`** | Drafted and dropped. `ci.yml` already compiles exactly the toy it wants with one line — `cc -DBUGGY=1 -o … spike/toys/toy.c -lpthread` — and the default build is the clean one, so both lanes come from the existing file with two compiles and no new source. |

## Consequences

- **Every pull request now downloads a published release asset.** That is a red path this
  repository did not have: an asset removed, replaced by a repair upload, or an API outage
  turns a PR red for a reason unrelated to its diff. It is recorded rather than mitigated —
  a pinned asset that stopped existing is a fact worth a red build.
- The API call is unauthenticated unless `GITHUB_TOKEN` is present, so it shares the runner's
  rate limit. The script prints which way it authenticated, so a rate-limit failure reads as
  one.
- The pinned version does not follow the latest release, by design. A quickstart that stays
  green on an old pin is the correct behaviour, and moving the pin is release work.
- macOS carries no verified-PASS evidence in this workflow. If the `fs_usage` questions above
  are answered later — a measured clean-with-rename PASS, and a ruling that standing CI may
  depend on `sudo -n` — the lane can be deepened without changing anything decided here.
