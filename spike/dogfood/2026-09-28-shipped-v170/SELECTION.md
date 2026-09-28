# Selection — 2026-09-28 shipped-v170

The owner's question for this run, asked the day v1.7.0 was published: **point the released
v1.7.0, installed the way `docs/ci-quickstart.md` installs it, at fresh ordinary tools, and carry
the ones it can enter to a definitive PASS or FAIL** — the 2026-09-22 shipped-v160 campaign's
shape (`../2026-09-22-shipped-v160/SELECTION.md`), one release later. The owner chose this over
widening the supervised re-measurement and over re-meeting past refusals, and chose to publish
v1.7.0 first so the run measures the shipped build (`README.md`, "Which build a run measures").

What this run adds to that shape is one thing v1.7.0 made possible: **a statically linked
candidate is not turned away at the gate**. v1.7.0's `--observe supervised` counts a static
target from outside the process (ADR 0089), so the static question no longer ends a row; it
sends the row to supervised. Nine of the nineteen candidates below are static.

## The exclusion set, declared before the candidates

`apparatus/fresh.sh` — the 2026-09-22 run's copy, with its self-exclusion (`mine`) pointed at
this directory. Its selftest now asserts that the previous run's own target, `ast-grep`, reads
**seen** from here (it read fresh from 2026-09-22's own directory), and names this run's own
target once the slate is fixed (`OWN=`). Green: `transcripts/fresh-selftest.txt`.

## The screen

| pass | names | fresh | seen | transcript |
|---|---|---|---|---|
| 1 — in-place formatters, state-file CLIs, static Go/Rust release binaries | 75 | 23 | 52 | `transcripts/fresh-screen-1.txt` |
| 2 — languages pass 1 left thin | 44 | 35 | 9 | `transcripts/fresh-screen-2.txt` |

Rules 1 and 2 of `spike/cohort4/SCOUT-BRIEF.md` (≥1,000 stars; a push since 2026-03-28), measured
with `gh api` (`transcripts/stars.txt`), took out, on stars: blacken-docs (679),
bump-my-version (629), cargo-sort (293), markdownlint-cli2 (929), ufmt (110), usort (205),
cabal-fmt (125), dart_style (702), fourmolu (462), hindent (581), leptosfmt (361), ocamlformat
(733), perltidy (117), pyproject-fmt (219), rustywind (623), statix (947), topiary (869), zprint
(624), luacheck (460), purty (41); on activity: cruft (last push 2024-12-25), elm-format
(2025-06-19); golines is archived. Several fresh names are one project under two names (pint /
laravel-pint, pg_format / pgFormatter, pip-compile / pip-tools, oxfmt / oxlint).

Dropped before the gate, each for a reason that is not a star count:

| name | why it did not enter the gate |
|---|---|
| git-bug | its operations write new git objects; nothing it changes exists before the operation, which the built-in rule leaves unjudged (the 2026-09-27 run's finding about new files) |
| goimports, hclfmt | the same shape as gofumpt and `terraform fmt`, from the same two projects' toolchains |
| oxlint | the same project as oxfmt |
| tflint | `--fix` needs plugins fetched over the network |
| SwiftFormat, SwiftLint | a Swift toolchain on Linux, for one candidate each |
| zopfli | writes a new `.gz` beside the input; the input is never rewritten |
| refurb | reports; it has no fix mode (rule 8) |
| dstask | no aarch64-linux release asset, and this machine's Docker is arm64 |
| pip-tools, cljfmt, nixfmt | held in reserve, not needed: the gate's nineteen cleared more than a slate can use |

Nineteen went to the gate — the cap the owner fixed on 2026-09-22 was twenty.

## The box

`apparatus/Dockerfile`, built by `apparatus/build.sh` (`transcripts/build.txt`). Debian trixie,
linux/arm64, every release binary the aarch64-linux asset its project publishes, each version in
its URL. **Sideeye is installed by the page's installer**, `install-sideeye.sh v1.7.0`: exit 0,
stdout the binary's path and nothing else, `downloaded digest matches (796a47ce…)` — the
aarch64-linux asset, whose sha256 was also computed from the downloaded bytes on the host at the
release. The first build failed on one candidate only: `gem install standard` could not build
`prism`'s C extension without Ruby's headers (`transcripts/build-first.txt`); the second adds
`ruby-dev build-essential`, which that error names.

Every gate and explore runs `--network none`, **privileged with its own cgroup namespace**
(`--privileged --cgroupns=private`) — the containment `--observe supervised` needs (ADR 0089).
The 2026-09-22 run used `--cap-add SYS_PTRACE`, so the default-mode rows here ran where the
engine can make cgroups and that run's did not.

Before any engine ran, each candidate's operation ran once plainly from its seed
(`transcripts/plain-runs.txt`): 19 of 19 exit 0 and change the state.

## Linkage, measured before the table

`file -L` on each operation's image and on the interpreters the scripts name
(`transcripts/linkage.txt`). **Static: gofumpt, yamlfmt, helm, jsonnetfmt, terraform, kubectl
(Go); sqruff, tombi, alejandra (Rust — `file -L` does not name the libc; sqruff's, tombi's and
alejandra's asset names say musl).** Dynamic: biome, rumdl, scalafmt, and the
interpreters behind the rest (`php`, `java`, `node`, `perl`, `python3`, `ruby`). oxfmt's `oxfmt`
is a Node script that loads a native addon (`oxfmt.linux-arm64-gnu.node`, dynamically linked).

## The entry gate — two changes from 2026-09-22

`apparatus/entry.sh`. The mapping from preflight's answer to 0 / 1 / 2 / DEFINE is 2026-09-22's,
unchanged. Two things changed, both written into the script's header:

1. **No threads question.** ADR 0085's 2026-09-26 amendment drops it and says a run copying the
   file forward removes the block. `gate.sh` is not copied.
2. **A static image is asked twice.** First `preflight --twice --oracle` in the page's mode, kept
   as `transcripts/entry/<name>.preflight-default.txt` — what a user following the page is told.
   Then the same preflight with `--observe supervised`, which is the answer mapped, the row
   marked SUPERVISED.

The legs, one per mapping row a leg was written for (`transcripts/entry-legs.txt`): all ten
land on the row they were written for — `write2` 0, `one` 1 interior, `stamp` 1 byte-repeatability,
`rawwrite` 0 FOLLOW, `childwrite` and `twothreads` 1 wall, `badcwd` DEFINE, `joinedthreads` 0
(accepted, 4 operations — the answer the dropped threads question used to contradict), and two
static legs: busybox-static's `sed -i` **0 under supervised** (3 operations), and busybox-static's
`touch` of a new file **1, `state_changed_without_ops`, under supervised**. The second is not a
supervised miss: the dynamic coreutils `touch` gets the same refusal in the default mode and under
supervised, and under `--observe syscalls` too — preflight exit 2 in each (`apparatus/probe-touch.sh`,
`transcripts/probe-touch.txt`) — so creating an empty file is recorded as no mutating operation in
any of the three modes.

**The two "could not measure" rows**, run after the review asked for them
(`transcripts/entry-legs-gate2.txt`, 01:19Z): `write2` with `ORACLE` pointing at no file answers
**2** (`setup: --oracle is not an executable file`), as on 2026-09-22; and the static `sed -i` leg
in a box that is *not* privileged — no cgroup the engine can make — answers **2 SUPERVISED**
(`--observe supervised needs a cgroup v2 the engine can create cgroups in`), not 1. So the new
branch keeps "could not measure" apart from "walled". **Not seen on anything:** preflight 2 with a
"Change the define", environment, shim-pair or retry sentence; preflight 3 on the define's own
message other than the missing cwd; an unmapped answer.

**What the page's mode tells a static target.** All nine static candidates, and the two static
legs, refuse `no_shim_marker` in the default mode, and they are told two different things,
decided by how the operation names its image:

- **The nine candidates name it bare** (`terraform fmt`, found on `PATH`). Their detail reads
  *"the operation's first word names no path, so the OS resolved it through PATH and Sideeye did
  not"*, and the `next` line *"Check that --shim names the interposition library from this build
  and that nothing strips the preload from the target's environment."* Nothing names
  `--observe supervised` (`transcripts/entry/<name>.preflight-default.txt`, nine of nine).
- **The two legs name `/bin/busybox` by path.** Their detail says the image is statically linked
  and ends *"on Linux 5.19 or later, on aarch64 or x86_64, --observe supervised counts it from
  outside the process instead"*, while the `next` line reads *"This target does something Sideeye
  refuses by design…"* — two lines of one refusal pointing different ways.

This paragraph's first draft described only the second case and said it held for all nine; it was
corrected when the explores met the first (`RESULTS.md`, revision 1). The gate itself was not
affected: it asks supervised of every static image regardless of what the default mode says.

The candidates (`transcripts/entry-candidates.txt`, `transcripts/entry/`):

| candidate | version | language | linkage | gate | preflight |
|---|---|---|---|---|---|
| alejandra | 4.0.0 | Rust | static | 0 SUPERVISED | 2 operations |
| biome `format --write` | 2.5.14 | Rust | dynamic | 0 | 3 operations |
| gofumpt `-w` | 0.12.0 | Go | static | 0 SUPERVISED | 6 operations |
| helm `repo remove` | 4.3.0 | Go | static | 0 SUPERVISED | 4 operations |
| jsonnetfmt `-i` | 0.22.0 | Go | static | 0 SUPERVISED | 2 operations |
| ktfmt | 0.64 | Kotlin/JVM | dynamic (`java`) | 0 | 2 operations |
| kubectl `config use-context` | 1.37.1 | Go | static | 0 SUPERVISED | 4 operations |
| nbqa `black` | 1.9.1 (black 26.5.1) | Python | dynamic | 0 | 12 operations |
| oxfmt | 0.70.0 | Rust via Node | dynamic | 0 | 2 operations |
| pg_format `-i` | 5.6 (Debian) | Perl | dynamic | 0 | 2 operations |
| phpcbf | 4.0.4 | PHP | dynamic | 0 | 2 operations |
| pint | 1.32.1 | PHP | dynamic | 0 | 2 operations |
| rumdl `fmt` | 0.2.77 | Rust | dynamic | **1** | `--twice`: `.rumdl_cache/…json` differs |
| scalafmt | 3.11.5 | Scala (native) | dynamic | 0 | 3 operations |
| sqruff `fix` | 0.40.0 | Rust | static | 0 SUPERVISED | 2 operations |
| standardrb `--fix` | 1.56.0 | Ruby | dynamic | 0 | 2 operations |
| terraform `fmt` | 1.16.4 | Go | static | 0 SUPERVISED | 2 operations |
| tombi `format --offline` | 1.5.6 | Rust | static | 0 SUPERVISED | 3 operations |
| yamlfmt | 0.21.0 | Go | static | 0 SUPERVISED | 2 operations |

**Eighteen of nineteen cleared, all nine static ones through supervised.** The oracle agreed on
every operation it compared, in all eighteen; for seventeen that is every operation. nbqa's is
subject-only: 8 of its 12 are nbqa's own, compared one by one, and 4 are its awaited child
black's, which the oracle placed and ordered but did not compare (`oracle_verified_subject_only`,
contract v15). The one red is rumdl's own cache, written inside the state directory
with different bytes each run; `--no-cache` would likely clear it, and it was not tried — the
mapping sends a byte difference to 1, not to DEFINE.

## The shortlist, the receipts and the novelty pre-scan (rules 11 and 14)

Eighteen cleared, and a pre-scan is about fifty GitHub searches per tracker against a limit of
thirty a minute, so the candidates were shortlisted to six **before** the pre-scan: three static —
kubectl (a kubeconfig is state a user does not want to lose), terraform, sqruff — and three
dynamic in three more languages — nbqa, standardrb, pint. The other twelve are recorded in the
funnel as attempted, stopped by this run's choice; pint, once dropped (below), by rule 11.

Rule 11 (`transcripts/receipts/rule11-bug-reports.txt`, the last ten issues and the first reply
from a project member, collaborator or contributor): kubectl replied to 10 of its last 10 bug
reports, 7 the same day; terraform to 9 of 9, each the same or the next day; nbQA to 6 of its last
8 issues and standard to 2 of its last 4 (nbQA's `bug` label stops in 2024 and standard carries
none, so their receipts are the last issues of any label, as todo.txt-cli's
was on 2026-09-22). sqruff replied to 3 of its last 10 bug reports; tombi and alejandra, the other
static Rust candidates, were measured as alternatives and replied less. **pint was dropped**:
laravel/pint has issues turned off (`has_issues=false`), so rule 11 cannot be measured and a FAIL
could not be reported on its tracker. phpcbf — PHP_CodeSniffer, the same language — took its
place (a member replied to 4 of its last 9 issues, each within a day); its checker was seen red
before it entered.

The pre-scan (`spike/cohort4/novelty-prescan.sh`, 51 terms; `transcripts/receipts/*.prescan.txt`)
ran on all seven trackers from 00:17 to 00:51Z, **before any explore** — the order rule 14 asks
for and 2026-09-22 did not keep. Both controls are green in every receipt. No hit is a report of
an interrupted rewrite of the file these operations write; the veto fired on none.

## The slate — owner sign-off 2026-09-28

**All six: kubectl, terraform, sqruff, nbqa, standardrb, phpcbf** — Go, Go, Rust, Python, Ruby,
PHP; a kubeconfig, a Terraform source file, SQL, a notebook, Ruby and PHP source, each rewritten
in place. The owner chose all six over a slate of three. Each carries a checker written with the
tool itself (`apparatus/defines/<name>/check.sh`), seen green on the seed and after a plain run,
and red on an empty file and on one cut in half (`transcripts/checkers-seen-red.txt`).
