# 2026-09-06 — results

Four targets, one verdict, three named walls — and the three walls are the
finding. Two of them are the same wall, and it is one this project has already
written down and decided about: **stdio, past the flush boundary**.

| Target | Outcome | Where |
|---|---|---|
| **mid3v2** (mutagen) | **PASS 10/10** — 9 crash points + baseline, `oracle_verified` | `transcripts/explore/mid3v2.txt`, `.json` |
| metaflac (flac) | UNKNOWN `oracle_missed_operation` | `transcripts/explore/metaflac.txt` |
| fontforge | UNKNOWN `oracle_missed_operation` | `transcripts/explore/fontforge.txt` |
| mutool (mupdf) | UNKNOWN `unresolvable_path`, at preflight | `transcripts/preflight/mutool.txt` |

## The wall: stdio writes that overflow the buffer

Both C targets that reached `explore` were refused for the same reason, and the
refusal quotes the divergence:

- **metaflac** — *"divergence at operation 3: the oracle saw:
  `write(3</work/st/fl/a.flac>, "\0\0…", 4096) = 4096`; the shim recorded:
  `open("/work/st/fl/b.flac")`"*
- **fontforge** — *"divergence at operation 4: the oracle saw:
  `write(4</work/st/ff/f.ttf>, "\10y\0\311…", 4096) = 4096`; the shim's account
  ends after 3 operation(s)"*

In both, the shim recorded the `open` and no `write` at all, and in both the
write the oracle saw is **exactly 4096 bytes** — a full buffer, not a flush.

ADR 0005 named this boundary and measured where it sits. It records that stdio is
observed at flush granularity because *"a stdio buffer cannot hold more than its
own size, so the flush of pending data normally issues exactly one `write(2)`"* —
and, in the same paragraph, the case that breaks it: *"a 10 KB `fwrite` = 2
writes **inside the `fwrite`**"*. taskwarrior and git's `COMMIT_EDITMSG` sit
inside the flush boundary, which is why the decision was worth taking. metaflac
writing a padding block and fontforge writing 743 KB of font do not.

So this is not a new wall; it is the first measurement of the **other side** of a
boundary that was chosen on targets that happened to sit on the near side of it.
What the run adds is that the near side is not where ordinary C tools live: two
of two C candidates that reached the engine fell off it, while the four C and C++
targets the 2026-09-05 run reached verdicts on (`mogrify`, `qpdf`, `exiv2`) write
through raw `open`/`write` rather than through stdio. The distinguishing property
is not the language — it is whether the tool's write path goes through `FILE*`.

**This is a limit, not a defect, and nothing is filed.** The refusal is honest
(`oracle_missed_operation` is exactly what happened: the second witness saw a
state-directory operation the shim did not record), it is fail-closed, and
`README`'s "What the target has to be" plus DESIGN.md carry the reason. Measured
against the issue threshold in `rules/orchestrator.md` §2.5: no hang, no crash,
no data loss, no silently wrong result — a named UNKNOWN is the opposite of a
silent one — and no documented promise is violated, because ADR 0005 documents
this boundary rather than promising past it.

## mutool: `unresolvable_path`, and what was ruled out

`mutool clean a.pdf a.pdf` is four syscalls and one `write`:

```
openat(AT_FDCWD, "/work/dbg/a.pdf", O_RDONLY)                        = 3
unlinkat(AT_FDCWD, "/work/dbg/a.pdf", 0)                             = 0
openat(AT_FDCWD, "/work/dbg/a.pdf", O_RDWR|O_CREAT|O_EXCL|O_TRUNC)   = 4
```

Preflight refuses with *"an operation was observed whose path could not be
determined, so it cannot be placed among the crash points"*. Every path strace
shows is absolute, so the obvious explanation is not the explanation.

What was measured and ruled out: **mmap is not involved in the file's data
path** — all 43 `mmap` calls against fds 3 and 4 carry `MAP_DENYWRITE` and
`PROT_EXEC`, which is the loader mapping shared objects, and the PDF itself is
read and written through the descriptors above.

What was not measured: which recorded operation the engine could not place.
Naming it needs the shim's trace read back rather than the refusal's summary, and
that is a `trace-ops` reading this run did not do. The honest statement is that
mutool is refused, that the refusal is not about mmap, and that the cause is
unattributed. Nothing about the cause belongs in `docs/target-classes.md` beyond
the refusal itself.

## The one verdict: mid3v2 PASS 10/10

```
PASS  10/10 explored worlds satisfied the built-in atomicity invariant
      explored 10 worlds (crash points 9 + 1 baseline)
      oracle: agreed on 9 operations (2019 syscall lines examined,
              123 in scope of the judged state), witness strace
      checker: falsified before the run (corrupted state -> check failed);
              ran in 10 world(s)
      processes: single process
```

The checker is the part worth stating, because a weaker one would have made this
PASS meaningless. mutagen writes ID3 through `openat(O_RDWR)` with no temporary
file and no backup, so **the file is still readable after a crash** — a checker
asserting only "`mid3v2 -l` succeeds" would pass in every world without
examining anything. The declared checker
(`apparatus/declared/check-mp3.sh`) therefore asserts two things: that
`mid3v2 -l` reads the file, and that the `ORIG:keep` tag the setup wrote before
the operation is **still there**. The engine's own falsification ran it against
deliberately corrupted state first and it failed, as the transcript's
`falsify: a.mp3 から元のタグ ORIG:keep が消えた` line records.

With that checker, all nine crash points hold. mutagen's in-place rewrite of the
tag region does not leave a window where the previous tag is gone and the new one
is not yet there — at process-kill granularity, on this file size, in these nine
points.

## Novelty, and what was filed

Nothing was filed. The only verdict is a PASS, and a wall is a fact about
Sideeye rather than about the target, so no tracker was searched beyond the rule
11 receipts in `SELECTION.md`. `spike/upstream-report-template.md` describes the
shape a report takes when there is one; this run produced none.

## What the run cost, and the three apparatus errors inside it

The screening cost about 15 minutes and four `docker build`s and removed five
candidates. The engine phase cost three preflight rounds, and every retry was an
apparatus error rather than a target property:

1. **`--state` and `--work` must exist before the engine is called**, not be
   created by `--setup`. Both refused with `SETUP ERROR … could not be resolved
   to an absolute path`, which names the consequence (the shim and the engine
   would filter on different spellings) rather than the cause.
2. **`exec fontforge …` in a wrapper script produced `child_process_detected`**
   — the subject replaced its own image and the chain of observation broke. It
   read exactly like the wall #123 describes, and it was mine: passing the same
   command to `--operation` directly, with the spaces removed from the
   FontForge script argument so it stays one word, is accepted, and the target
   then records 3 state-changing operations. **A wall reported at the first
   attempt is a claim about the apparatus until the apparatus is varied.**
3. **`nm` is not in the image**, and `nm -D … 2>/dev/null | grep …` printed
   nothing for all five binaries — which reads identically to "these binaries
   reference no write functions". The wall's cause was established from the
   engine's own divergence lines and ADR 0005 instead, not from that empty
   output. Twice in one run, an empty result came from an instrument that never
   ran; the Bugzilla filter in `SELECTION.md` was the other.

## What moves upward

- `docs/target-classes.md`: one refusal row for the stdio-overflow wall naming
  metaflac and fontforge, one for mutool's `unresolvable_path`, and one verdict
  row for mid3v2.
- `spike/dogfood/RUNS.md`: one row.
- Nothing for `spike/upstream-reports.tsv` — nothing was filed.
