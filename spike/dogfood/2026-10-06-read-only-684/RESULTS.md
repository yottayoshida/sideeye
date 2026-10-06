# 2026-10-06 — the four targets #684 named, past the calls that change nothing

vim, fish, dotdrop and firewalld were each refused `unsupported_syscall_observed` on a call
that changes nothing on disk: vim on `getxattr` (2026-09-16, 2026-10-02), fish on
`inotify_add_watch` (2026-09-16, 2026-10-02), dotdrop on `listxattr` (2026-10-03), firewalld on
`listxattr` (2026-10-05). #684 adds those calls — and the rest of the "still refused" list in
`docs/report-schema.md` — to the strace oracle's reads. This run measures where each target
gets to once they are reads.

## How

- **Image** (`apparatus/Dockerfile`): `debian:trixie-slim`, the base all three earlier campaigns
  used, with the four packages and nothing else. Versions (`transcripts/versions.txt`) match what
  those campaigns recorded: vim `2:9.1.1230-2`, fish `4.0.2-1`, firewalld `2.3.1-1+deb13u1` (recorded
  as "2.3.1 (Debian)"), dotdrop `1.17.0`. The earlier images were not rebuilt: they carry dozens of
  other tools whose versions a rebuild would move.
- **Defines** (`apparatus/defines/`): copied unchanged from the campaigns that recorded each wall —
  vim and fish from `2026-10-02-unjudged-on-v170`, dotdrop from `2026-10-03-user-data`, firewalld
  from `2026-10-05-user-data-2`. vim and fish carry their checkers; dotdrop and firewalld have none,
  so they are judged by the built-in invariants alone.
- **Step 1, before the engine changed** (`apparatus/survey.sh`, `transcripts/survey/`): each operation
  once under `strace -f -y` alone, no engine, listing every syscall name on a line that mentions the
  state directory and is in none of the oracle's lists — read from `src/oracle.zig` at `7b9d1fd`, 81
  names. The oracle keeps only the first unnamed call it meets, so the walls on record said nothing
  about the calls behind them.
- **Step 2** (`apparatus/measure.sh`, `transcripts/measure/`): the engine built from `7b9d1fd` plus
  this pull request's `src/oracle.zig` change, cross-built for `aarch64-linux-gnu` and mounted —
  `sideeye version` prints `1.8.0` for any build of this tree, so `transcripts/measure/engine.txt`
  records the binary's and the shim's sha256 instead. Each target in all three observation modes
  with the strace oracle, `docker run --privileged --cgroupns=private --network none` as the earlier
  campaigns ran.

## The prediction (step 1, written before step 2 ran)

| Target | Unnamed calls on the state | Predicted next answer |
|---|---|---|
| vim | `getxattr`, **`setxattr`** (`system.posix_acl_access`, writing the ACL back after the save) | `unsupported_syscall_observed` on `setxattr` |
| fish | `inotify_add_watch` | no wall of this kind left |
| dotdrop | `listxattr` | no wall of this kind left |
| firewalld | `listxattr` | no wall of this kind left |

The vim line is the one the plan's first review predicted from vim's source (`mch_set_acl` after
`set nobackup nowritebackup`) before anything was run.

## Results (step 2)

| Target | wrappers | syscalls | supervised |
|---|---|---|---|
| vim | UNKNOWN `unsupported_syscall_observed` (`setxattr`) | same | same |
| fish | **PASS** 6/6, oracle agreed on 5 operations | PASS 6/6, 5 | PASS 6/6, 5 |
| dotdrop | **FAIL** 2/15, oracle agreed on 14 | FAIL 2/15, 14 | FAIL 2/15, 14 |
| firewalld | **FAIL** 1/6, oracle agreed on 5 | FAIL 1/6, 5 | FAIL 1/6, 5 |

None stopped on the call #684 named, and the prediction held for all four. fish, dotdrop and
firewalld reached the oracle comparison and a verdict; vim stopped on `setxattr` before it — an
unnamed call is refused before the comparison is made — which is the wall step 1 predicted, not
the plan's "past the comparison" for that one target.

- **vim** meets the writing side of the same family: `setxattr` on `a.txt`. The oracle has no class
  for it and the restore does not put attributes back, so it is a wall, not a read — this pull
  request leaves it refusing on purpose.
- **fish** `set -U` writes `fish_variables` through a temporary file and a rename. Its checker
  (the variable set before the run is still readable) was falsified and held in every world.
- **dotdrop** `install -f` with `backup: true`: two worlds violate. The report, the case and the
  evidence describe the earliest only, so every world was measured by a script
  (`apparatus/worlds.sh`, its output copied to `transcripts/measure/dotdrop/worlds.tsv`: the operation
  killed at each of its 14 crash points with the `reproduce` line's own variables, each backup
  compared byte for byte with the dotfile the seed wrote). k=6 is after the truncating `open` of
  `home/.bashrc` and before its `write` — `.bashrc` empty, `.bashrc.dotdropbak` identical to the old
  59 bytes; k=13 is the same for `home/.gitconfig` — empty, `.gitconfig.dotdropbak` identical to the
  old 19 bytes. **In both the old bytes are elsewhere.** A built-in-invariant FAIL whose content is not lost, the shape
  `docs/target-classes.md` already records for doing. (k=3 and k=10 leave an empty backup beside an
  intact original: the backup is a file the operation creates, which the built-in invariant does
  not judge.)
- **firewalld** `firewall-offline-cmd --add-port`: crash point 5 of 5 is after the truncating `open`
  of `zones/public.xml` and before its `write`. The old bytes are in `zones/public.xml.old`. The same
  shape.

## What this does not say

- Whether either FAIL is worth reporting upstream: both keep a backup a user can restore by hand,
  and that judgement — and reading each project's contribution and AI policy first — is outside a
  re-measurement. Recorded as `no_content_lost`, not as a finding to file.
- vim's next step past `setxattr` (it would need a class for attribute writes, or a define that
  keeps vim from writing the ACL); not attempted.
- Linux x86_64: not measured here; CI's acceptance runs there. Whether glibc issues `poll` and
  `select` as themselves or as `ppoll` and `pselect6` there was not checked; the unit test holds
  all four spellings.
- The macOS fs_usage oracle, which keeps its own list of reads.
- The raw straces are not kept — dotdrop's and firewalld's are about 700 KB each, and every one
  carries the host's own paths where the target's stdout pointed. Their unnamed lines are in
  `transcripts/survey/*.unnamed.txt`; the unit test in `src/oracle.zig` quotes four of them.
