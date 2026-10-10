# 0104 — A generation names the machine it was swept on

- **Status:** Accepted (2026-10-10)
- **Refs:** #696 (from the 2026-10-05 whole-product review); ADR 0073 (a generation pinned to a
  released engine); `.github/workflows/spike-fsusage.yml` (a measurement workflow that is not CI).
- **Scope:** `spike/unknown-rate/sweep.sh`, `spike/unknown-rate/count.py`,
  `spike/unknown-rate/engine-pins.tsv`, `spike/unknown-rate/generations.tsv`,
  `spike/unknown-rate/fixtures/machine-*`, `spike/acceptance.sh`,
  `.github/workflows/spike-unknown-rate-x86.yml`, `docs/unknown-rate.md`.

## Context

Every real-target measurement on `docs/unknown-rate.md` was taken on Linux aarch64, in
containers under Docker Desktop, and the page said so in prose. #696 asks for a measured row
on Linux x86_64 (and for macOS, a row or the statement that there is none). The B and B2
groups can be swept again on GitHub's x86_64 runner as a new generation, g4, pinned to g3's
release in its x86_64 build — `fetch-engine.sh` already keys its cache by asset so that two
generations can pin one tag's two builds. What the page had no way to say was which machine a
generation ran on: `generations.tsv` has no column for it, and the headings carry the
generation, the date and the groups.

## Decision

**The sweep records the machine, and the page reads the machine from that record.**

- `sweep.sh` writes `machine: <host> <container>` (`uname -m`, with macOS's `arm64` spelled
  `aarch64`) into `apparatus.txt`, and `ci-run: <run id>` when a workflow runs it.
- `count.py` reads a generation's machine from that line — the container's value — and reads a
  generation without the line as Linux aarch64, which is where every such generation ran.
  `emit` names the platform in the heading only when it is not aarch64
  (`### Generation g4 — measured … (B,B2) on Linux x86_64`), so g1 to g3 and every fixture
  keep the heading they had.
- `count.py check` holds the line to the rest of the record: two known names, the same twice
  (they differ when the trials were emulated); a pinned asset whose name carries an
  architecture agrees with it, the default included, so a record that lost its line cannot
  carry an x86_64 asset under an aarch64 heading; every trial directory holds a `launcher-rc`;
  and the published heading names the platform. The last two apply only where the line is
  present, because the fixtures carry no `launcher-rc`; every live generation before the line
  carries one per trial directory (g1 34 of 34, g2 34 of 34, g3 26 of 26), so the restriction
  excuses none of them.
- The sweep stops where it used to go on: the host makes each trial directory before the
  container runs (on a native Linux host the container's root owns what it makes, and the
  host could not write `launcher-rc` into it), and a failed `launcher-rc` write or oracle fold
  ends the sweep instead of finishing it at exit 0.
- The x86_64 sweep runs from `spike-unknown-rate-x86.yml`, by hand only, at a commit named as
  an input, with a `smoke` input that stops before the trials. The record is the first sweep
  that completes, copied into the tree in a pull request of its own.

## Alternatives considered

- **A platform column in `generations.tsv`.** Explicit, and the file is read by every fixture:
  seventy-eight `generations.tsv` would change to say what their apparatus already implies.
- **The architecture from the pinned asset's name.** Twenty-four fixtures pin
  `fixture.tar.gz`, which names none, and g1 and g2 pin nothing; reading an unparsed name as
  aarch64 is a default that cannot fail, and a pin says what was fetched, not where it ran.
- **The sweep on every push of a branch.** Each push would sweep again, and a later push could
  publish whichever run read best. g3 was swept once at the merge commit of its apparatus; g4
  is swept the same way.

## Consequences

- A generation measured elsewhere than Linux aarch64 says so where its numbers are, and a
  record that does not say where it ran cannot be published under another machine's name.
- What `emit` prints under g4 keeps the shape g3's re-measurement of g1's B gave it: the
  B-group heading ("the threshold basis", the group's role, not the generation's), the
  re-measurement note ("on this generation's engine … the threshold basis is unchanged"),
  and a macOS column derived by the same platform-free formula from g4's Linux results.
  Criterion 4's basis stays g3, and the kill-criteria review's Row 8 reads g4 as it reads
  any platform's sweep (owner, 2026-10-10); the threshold section says so
  before the sweep. The B2 authoring clock is printed under the generation that first
  measured B2 only: g4 authored nothing. What else differs from g3 — the Debian packages
  of the day, the kernel, the VM, the runtime's AppArmor profile — is said before the sweep
  in g4's `expected-before-reading.md` (now `spike/unknown-rate/artifacts-g4/`), and goes into the Platform section,
  outside the generated block, with the results.
- macOS keeps a derived column and gains no measured one: the B and B2 targets are Debian
  packages and their defines assume Debian's paths and seeds.
