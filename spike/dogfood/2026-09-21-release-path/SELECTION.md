# 2026-09-21 — selection

A run against the **adoption path**, not the mounted tarball every earlier dogfood used. Sideeye
arrives here the way `docs/ci-quickstart.md` tells a project to get it: the vendored
`install-sideeye.sh`, a pinned version, a digest checked against the one GitHub publishes, no Zig
and no source checkout. `quickstart-release.yml` already runs that script — against two toys this
repository wrote for the page. Nothing had run it against a real project.

Rules 1–17 are `spike/cohort4/SCOUT-BRIEF.md`'s, unchanged. The ordering rule the 2026-09-05 run
paid for is followed: **linkage and threads were measured before the candidate table was
written**, not after.

## What was excluded before any candidate was measured

`apparatus/fresh.sh` searches six ledgers and exits 1 on any hit. Five was not enough: an earlier
draft of this run checked the outcome funnel and three pages, and review found that the funnel
holds *encounters*, not the candidates a run screened away — those live only in each run's
`SELECTION.md`, and #618's own target selection was in none of them.

| ledger | size |
|---|---|
| `spike/outcome-funnel.tsv` | 111 lines, 68 distinct targets (112 and 69 once this run's own row is in; `fresh.sh` excludes it) |
| `docs/target-classes.md` | 199 lines (200 with this run's row) |
| `spike/unknown-rate/b-exclusions.txt` | 31 lines |
| `spike/blind-hunt3/candidates.md` | 58 lines |
| `spike/authoring-cost/selection.tsv` | 5 lines |
| `spike/dogfood/*/SELECTION.md` + `spike/authoring-cost/pool-*.txt` | 14 files |

`fresh.sh --selftest` holds four cases and is green: a target the funnel names comes back seen,
**a target only #618 names comes back seen** (`dos2unix` — the case the last two ledgers exist
for), **this campaign's own slate still reads fresh after this campaign has written its records**,
and an invented name comes back fresh. Each is seen red by a mutation: deleting the two ledgers
review added reds the second, and removing the self-exclusion reds the third.

That third case is a defect this run found in its own tool. The first version searched every
ledger including the ones this campaign was about to write, so re-running the check after the run
returned `SEEN lefthook` against **the funnel row, the target-classes row and the SELECTION.md
this very run had added** — which would have made the freshness of this selection impossible to
check again afterwards. The campaign's own records are excluded now, and the evidence is
reproducible at any time:

```
$ sh apparatus/fresh.sh lefthook
fresh lefthook
```

**53 names screened, 27 already met, 26 fresh** — the run's output is
`transcripts/freshness-screen.txt`, and every figure here is read from it rather than from the
screening session's scrollback. Two earlier drafts of this page got it wrong in different ways:
the first said "50 names, 12 already met" (three batches counted by eye), and the second said 23
because the list it screened contained `abook2`, which does not exist — the tool measured was
`abook`, and `abook` is already met in six places. `go` and `npm` were measured against the rules
without being screened at all; they are in the list now and both are already met.

The already-met names: `abook age buku bun dasel deno direnv dvc go hledger jq jrnl just khard
ledger mise nb node npm par2 pass pipx sops taskwarrior todoman vdirsyncer yq`.

**Only 9 of the 27 are in the funnel** (`age buku bun go ledger nb node npm pass`). The other 18
are in earlier runs' `SELECTION.md` files or in `target-classes.md` — `mise` in five
`SELECTION.md` files, `direnv` and `dasel` in three each. A freshness check reading the funnel
alone would have taken those 18 for new.

Some hits are the loose matching working as designed rather than a real encounter —
`SEEN mise target-classes:54` is the word "opt**imise**r" in the oxipng row — which is the
direction this gate is deliberately wrong in: a false `SEEN` costs a candidate, a false `fresh`
publishes as new a target this project has already measured. `abook2` is what a false `fresh`
looks like, and it is in this run's own screen.

The funnel's `candidates` column for this campaign is **10**, not 50: the earlier campaigns count
the candidates they measured against the rules, and 50 is the number of names put through a
freshness grep — a different and much cheaper act. Adding the two units together would have made
the generated total on `docs/outcome-funnel.md` mean nothing.

## Rule 10, measured before the table

`file -bL` and `strace -f -e trace=clone,clone3` on the real binaries, in the run image.

| candidate | linkage | threads in its mutating command | writes state? | disposition |
|---|---|---|---|---|
| `lefthook install` | **static** | 5 | yes — `.git/hooks/pre-commit`, `.git/info/lefthook.checksum` | **slate** |
| `go mod init` | **static** | 8 | yes — `go.mod` | rule 10 |
| `npm init -y` | dynamic | 11 | yes — `package.json` | rule 10 |
| `volta pin node@20` | dynamic | 3 | **no** — `error: Not in a node package` | rule 8 |
| `rustup toolchain link` | dynamic | 9 | **no** — `error: not a file: '/usr/bin/rustc'` | rule 8 |
| `jenv local 17.0` | script | 0 | **no** — `version '17.0' not installed` | rule 8 |
| `nodenv local 20.0.0` | script | 0 | **no** — `version '20.0.0' not installed` | rule 8 |
| `rbenv local 3.2.0` | script | — | **no** — `version '3.2.0' not installed` | rule 8 |
| `remind -n` | dynamic | 0 | no — reads only | rule 5/8 |
| `bibtool -s -i -o` | dynamic | **0** | yes — `out.bib` | rule 1 (not a GitHub-star project) |

Stars, measured with `gh api repos/<r> --jq .stargazers_count` on 2026-09-21 and recorded in
`transcripts/stars.txt`: lefthook **8,833**, volta 13,068, rustup 7,048, jenv 6,661,
nodenv 2,415. All clear rule 1. (An earlier draft wrote 8,832 from memory.)

**The sunset clause in `spike/dogfood/README.md` does not fire here.** It says the ordering rule
goes if a screen calls a target measurable and the engine then refuses it. This screen did not:
`file -bL` said `statically linked` in the output it produced, before the table was written. What
failed was the reading, not the rule — which is the opposite of the case the clause is watching
for, and the reason the rule is kept.

**Five of the ten fell the same way**, and it is worth naming: the version managers
(`rbenv` `jenv` `nodenv` `volta` `rustup`) all refuse to write anything until the language they
manage is installed. That prerequisite is heavier than the adoption step under test and sits
entirely outside it, so the whole family is out of reach of a container built for this run —
not because Sideeye cannot judge them.

## The slate: one target

`lefthook` alone. Rules 1–9 and 12–17 clear; rule 10 is the interesting one and is discussed
below. **The owner signed off on a slate of one** (2026-09-21) after the screening above
exhausted the candidates that survive a probe.

## What the probe should have caught, and did not

`lefthook` is **statically linked**, and this table says so — but the run went ahead anyway,
because the first reading of `file -bL` stopped at `ELF 64-bit LSB executable` and did not reach
`statically linked` on the same line. Rule 10 asks for dynamic linking *verified by probe*; the
probe was run and its output was not read to the end.

The run then refused with `oracle_missed_operation`: the oracle saw the `openat` that creates
`pre-commit`, and the shim's account ended after **0 operations** — which is what interposition
looks like when there is no dynamic linker to interpose through.

It is kept in the slate rather than swapped out, because the refusal is a correct and specific
one and because a run that ends this way is a result about Sideeye's reach, not a failed run
(`spike/dogfood/RUNS.md`'s own words). What changed is `transcripts/linkage-verdicts.txt`: linkage is now
classified by a `case` on the whole `file` line rather than by eye, and
`transcripts/linkage-full.txt` carries those lines untruncated.
