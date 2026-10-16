# Invariant: `quilt push -a` (quilt 0.68-1), two patches, two files

## The tree

`setup.sh` builds it in `$SIDEEYE_STATE_DIR` (`/home/user/qtree`), which is also the
command's cwd, because quilt finds `patches/` and `.pc/` from where it runs:

| file | pristine | after `p1.diff` / `p2.diff` |
|---|---|---|
| `a.txt` | `alpha one / alpha two / alpha three` | line 2 is `alpha TWO patched` (p1.diff) |
| `b.txt` | `beta one / beta two / beta three` | line 2 is `beta TWO patched` (p2.diff) |
| `patches/series` | `p1.diff`, `p2.diff`, in that order | unchanged |
| `patches/p1.diff`, `patches/p2.diff` | a one-line description, then the diff | unchanged |

quilt's own records live in `.pc/`: `applied-patches` (the applied list, appended one
line per patch), `.version`, `.quilt_patches`, `.quilt_series`, and per applied patch a
directory `.pc/<patch>/` holding the original of every file the patch changes (what
`quilt pop` puts back) and a `.timestamp`.

The related files whose records must agree: the series, quilt's applied list, the
working files, and the backups. Each patch changes a different file, so whether a file
is pristine or patched is decided by one patch alone.

## Before (valid)

No `.pc/`. `quilt applied` says "No patches applied"; `a.txt` and `b.txt` pristine.

## After (valid)

`quilt applied` lists `p1.diff`, `p2.diff`; both files patched; `.pc/p1.diff/a.txt` and
`.pc/p2.diff/b.txt` hold the pristine bytes; the operation prints
`Now at patch patches/p2.diff` (the define's `marker`) and exits 0.

## The legs (what `check.sh` judges, after running `recover.sh`)

Every quilt command except the recovery runs in a copy of the state, because quilt
touches `.pc/applied-patches` even when it only reads.

- **A, order** — quilt reads its own records (`quilt series` and `quilt applied` do not
  refuse) and what `quilt applied` lists is a prefix of what `quilt series` lists.
- **B, applied** — for every patch quilt lists as applied, its file holds that patch's
  result (the bytes `quilt push -a` produces from the setup's tree).
- **C, unapplied** — for every patch quilt does not list as applied, its file holds the
  pristine bytes.
- **D, backup** — quilt can take back what it lists as applied: in a copy,
  `quilt pop -a -f` exits 0, quilt then lists nothing applied, and every file of every
  patch that was listed is pristine.
- **E, records** — `patches/series`, `patches/p1.diff`, `patches/p2.diff` are the bytes
  the setup wrote.

When quilt refuses to read its records, leg A fails and legs B–D read the record
itself, `.pc/applied-patches`, so that one broken record does not turn every leg red.

## Crash states that are acceptable

After `recover.sh`, exactly the states that look like "the first k patches of the
series were pushed and nothing else happened", k = 0, 1 or 2: the applied list is the
first k of the series; their files patched with backups that restore the originals;
the rest pristine; the records untouched. Things the legs deliberately leave alone, so
a crash may leave them: a `.pc/` with no applied list, a `.pc/<patch>/` directory or a
`.timestamp` for a patch that is not listed as applied, a leftover temporary file of
patch(1) beside a working file, and file timestamps.

## Recovery

quilt has no crash recovery. The one repair it names itself is `quilt upgrade`, which it
asks for when `.pc/` exists without a readable `.pc/.version` ("The working tree was
created by an older version of quilt. Please run 'quilt upgrade'") — the state a kill
between `mkdir .pc` and the write of `.version` leaves (`create_db` in
`/usr/share/quilt/scripts/patchfns`). `recover.sh` runs `quilt upgrade` in the state; on
any other tree it says "nothing to do" and writes nothing. Without it that crash state
fails leg A (`norecover.txt`: the same state, judged with a `recover.sh` that does
nothing, is rejected; `controls.txt`'s `recovered` case, with it, is accepted).

Re-running `quilt push -a` is the operation itself, not a recovery, and is not run.

## What the checker deliberately does not claim

- Nothing about a crash between patch(1) replacing a working file and quilt appending
  the patch to `.pc/applied-patches`: such a state is **not** acceptable here (leg C),
  but sideeye never explored it (see below); `controls.txt`'s `crash-window` case is a
  hand-built state from reading `push`, not an observed one.
- Nothing about stray backups or `.timestamp` files of patches that are not listed as
  applied, nor whether a later `quilt push -a` goes through from a crash state (it
  did not from the hand-built crash window: it failed "can be reverse-applied" twice in
  a row, `a.txt` still patched — recorded as an observation, not a leg).
- Nothing about timestamps (quilt sets them with `touch -r`; sideeye does not restore
  them), `~refresh` markers, rejects, fuzz, or `.pc/.quilt_patches` / `.quilt_series`
  contents.
- Nothing about trees, series or patches other than this fixture: two patches, each
  changing one different existing file, applied cleanly with no fuzz.
- Nothing about power loss, torn writes or concurrent quilt runs.
- `quilt push -a` runs with the system `/etc/quilt.quiltrc` (it adds the `patches/`
  prefix to quilt's listings, which the checker strips); no `~/.quiltrc` exists.

## Result of the exploration

UNKNOWN (exit 2), `child_touched_state_dir`, the same in `--observe wrappers` and
`--observe syscalls`; `--observe supervised` is a SETUP ERROR (exit 3) here, no writable
cgroup v2. quilt's `push` runs its patch loop in a pipeline
(`for patch … done | cleanup_patch_output | colorize`), so the loop is a forked subshell:
it runs patch(1), which writes `a.txt` and the backup, reaps it, then appends to
`.pc/applied-patches` itself. sideeye refuses any run in which a process other than the
subject writes after a child of its own wrote, even when that child was reaped first
(`probe.txt`: `( touch x; echo hi >> y ); echo z >> y` is refused the same way). The
operation cannot be changed without changing quilt, so no crash world was explored and
sideeye's own checker gates (falsification, starting state) never ran; the checker's
ability to fail rests on the controls only.
