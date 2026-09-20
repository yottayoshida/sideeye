# CI quickstart (GitHub Actions)

The example here is not a listing — it is
[`.github/workflows/quickstart-release.yml`](../.github/workflows/quickstart-release.yml),
a real workflow that runs on every push to main and every pull request in this repository,
against the defines in [`docs/ci-quickstart/release/`](ci-quickstart/release/). A quickstart
that CI itself executes cannot quietly rot into fiction. To adopt it: copy the workflow and
[`install-sideeye.sh`](ci-quickstart/release/install-sideeye.sh), and swap the define.

**It installs a published release. There is no Zig and no build of Sideeye** (#620, ADR 0080) —
your setup effort goes into your define and your checker, not into Sideeye's toolchain. The
older [`quickstart.yml`](../.github/workflows/quickstart.yml) still builds from source and
stays as *this repository's* self-test; if you want that path, it is documented by its own
comments.

Its actions are pinned to commit SHAs rather than tags, which is this repository's own
rule (ADR 0061) and not something the quickstart needs: copy it as it stands and let
whatever keeps your actions current update them, or put the tags back. The gate below is
the part that matters.

## The three pieces

**1. A `sideeye.toml` next to your project** — the define: where the state
lives, how to produce it, and the one operation to explore.

```toml
[world]
state = "/tmp/myapp-state"        # scratch directory sideeye empties and rebuilds

[define]
setup     = "./ci/seed-state.sh"  # produces the initial state, runs once
operation = "myapp commit"        # explored: killed before each state-changing op
# check   = "./ci/verify.sh"      # optional L2: your own invariant, run after each crash
```

**`state` is sacrificial.** Exploration empties and rebuilds that directory once per
world — hundreds of times in one run — and what comes back is a restore from the
snapshot, with modes flattened and ownership dropped (#121). It is a scratch copy your
`setup` produces, never a directory anything else depends on. This page used to name
`/var/lib/myapp` here; sideeye now refuses a root inside a system tree rather than
emptying it (#267).

If you replay saved cases through the MCP server, know that replay confines the
case's state to `SIDEEYE_MCP_STATE_ROOT` (default: the server root) — a case whose
state lives under `/tmp`, as above, needs `SIDEEYE_MCP_STATE_ROOT=/tmp` on the
server. Widen that variable, never `SIDEEYE_MCP_ROOT`; and with it unset, the
workspace root itself is the declared destruction range (#266, ADR 0022) — so with
it unset, choose a root whose contents you can afford to lose. Since #329 the root
may be a single-component mount (`/work`), but what the vet refuses is a system
location or a directory containing one, never a directory merely because it is
shallow.

Relative paths and place-naming commands (`./x`, `../x`) resolve against the
toml's own directory, so the file means the same thing from any cwd (ADR 0007).
Commands split on spaces — no quoting. An argument that carries a space is
spelled with the argv form, one line, passed verbatim (ADR 0019):
`operation = ["myapp", "commit", "-m", "a message with spaces"]`. A define
spelled as argv skips `sideeye preflight` (flags carry the string form only)
and goes straight to `explore --config`, which answers strictly more.

**2. The workflow steps** — run the installer's own selftest, check that no Zig is on `PATH`,
install `strace` (the completeness oracle; without it a would-be PASS refuses as
`completeness_not_verified` — sideeye does not certify what it could not fully observe),
install a pinned Sideeye from the release, then explore:

```sh
bin=$(sh install-sideeye.sh v1.5.0 "$RUNNER_TEMP/sideeye")
"$bin" explore --config sideeye.toml \
  --oracle /usr/bin/strace \
  --json report.json
```

**stdout is the path and nothing else** — the running commentary goes to stderr, so the
capture above is the whole calling convention. In a workflow, `echo "SIDEEYE_BIN=$bin" >>
"$GITHUB_ENV"` carries it to later steps. The script needs `curl`, `tar`, `python3` and a
sha256 tool, all of which GitHub-hosted runners have; it does not need Zig, a compiler, or `gh`.

The version is an argument with no default: following the latest release would let a build
you did not choose turn your gate red, or green. The installer selects the asset for the
runner's platform, **refuses outright when the release has none** rather than reaching for a
neighbouring one, and checks the download against the sha256 GitHub publishes for that asset
before anything runs. What that check establishes — the bytes are the ones GitHub holds, not
who produced them — is stated in [cli.md](cli.md#installing-without-homebrew), which is also
where the by-hand form of the same two commands lives. `sh install-sideeye.sh --selftest`
runs its own failure cases, with no network, and the workflow runs it before it trusts it.

**One caution on copying the PASS lane's assertion.** It gates on `verdict == "PASS" and
oracle_verified`, which is right for a target whose own process does the writing. A define whose
operation writes through a child process earns `oracle_verified_subject_only` instead, with
`oracle_verified` staying false — a legitimate PASS that this assertion would call red. Read
[report-schema.md](report-schema.md) for which of the two your target reaches before you copy
the check.

**No `--shim`.** A release tarball unpacks flat, binary beside shim, and sideeye looks beside
itself before `../lib` (#78) — so the flag would be path surgery for nothing. Pass it only if
you have separated the two files.

**On macOS the same workflow explores a target with a planted bug and asserts the FAIL, with
no oracle.** A FAIL is evidence on its own; a verified PASS on that platform would mean
`fs_usage` under `sudo`, which this repository has ruled out of standing CI. So the macOS lane
proves the installed binary and shim work there, and makes no PASS-side claim — the Linux job
is where `oracle_verified` is asserted. ADR 0080 has the three reasons.

**3. The gate** — the exit code is the whole integration:

| Exit | Verdict | In CI |
|---|---|---|
| 0 | PASS | Green. Read `not_tested` in the report before celebrating — it lists what this run does not claim. |
| 1 | FAIL | Fail the job. The report's `earliest` object is the counterexample; `replay` is the exact command that reproduces it (shim path included), and the saved case replays with `sideeye replay <case> --shim <lib> [--fresh-state]`. Hand the report to an agent — that loop has been closed end to end, twice (DESIGN §17). |
| 2 | UNKNOWN | **Fail the job by default.** Sideeye refused to judge and `unknown_reason` says why (see [report-schema.md](report-schema.md)). Treating UNKNOWN as green is how a target quietly leaves the tested set. |
| 3 | SETUP_ERROR | Fail the job; the define itself did not run. |

The workflow runs **both** directions, and the pair is the point: the lane you copy
([`sideeye-clean.toml`](ci-quickstart/release/sideeye-clean.toml)) has a correct target and
gates on `= 0`, and a second lane ([`sideeye-bug.toml`](ci-quickstart/release/sideeye-bug.toml))
has a target with a planted bug and gates on `= 1`. Without the second, a green run cannot be
told from a Sideeye that explored nothing; without the first, the example never shows the gate
you will actually write.

The four rows above are the verdicts a run can reach. Commands that produce no
verdict are not in the table and are not gates: `version` and `help` exit 0
because they did what was asked, and a `preflight` that accepts the recording
exits 0 without claiming PASS. `docs/contract-freeze.md` §3 states which
direction the promise runs.

`preflight --twice` uses one more code, and the same reading applies: exit 1
means the two observed runs left different state under `--state` (#199). It is
not a FAIL — no counterexample was found, and none was looked for — it is the
negative answer to the identity question the flag asked, with the differing
paths named. A script that *branches* on `preflight --twice` (it is still not a
gate, by the paragraph above) reads 0 as "go ahead and write the define", 1 as
"pin what differs first", and 2 as the detector refusals it already handled.

The caution runs the other way: a wrapper that shares one `rc == 1 → a
counterexample was found` branch across sideeye commands will mislabel a split.
Reading exit 1 from *this* command as a crash-consistency failure reports a
repeatability problem as a bug in the target's crash behaviour, which is a
different claim entirely. Give preflight its own branch, or read the headline.

## Notes

- The demo toy finds its state through `TOY_STATE`, which sideeye itself
  exports to its children pointed at the resolved `[world] state` — the
  workflow supplies nothing extra. Your target locates its state its own way
  (env, config, hardcoded path); the toml only tells *sideeye* where to watch,
  and sideeye's children inherit your CI environment.
- One operation per explore, by design: the report must name one command's
  crash window, not an average over several.
- Every field the report carries is documented in
  [report-schema.md](report-schema.md), and CI holds that page to the
  generated reports.
