# Disclosure — prior knowledge noticed in injected context

I am running with a standard Claude Code harness injection (project CLAUDE.md +
a persistent cross-session MEMORY.md). Both contain material relevant to this task
that I did **not** derive from reading the target checkouts. Recorded verbatim /
paraphrased below, exactly as I noticed it, before doing any target reading.

## 1. "sideeye" itself

My injected CLAUDE.md (project↔repo mapping table) contains this row:

> `sideeye` | `~/claude_workspace/sideeye` | `crash-consistency 反例探索 OSS（Zig、公開、PR必須）`
> ("crash-consistency counter-example search OSS, Zig, public, PR required")

So I know, independent of anything in this task's targets/ directory, that a project
named sideeye exists, is written in Zig, is public, and is specifically about
crash-consistency counter-example search — i.e. almost certainly the exact
engine this scouting task is feeding. I did not open the sideeye repo (it is
outside the allowed read path and I was told not to), so I have no knowledge of
its actual source code, only this one-line description plus what follows.

## 2. sideeye project-status notes in MEMORY.md

My injected MEMORY.md carries a long running index entry under a
`project_sideeye` heading (I only saw the MEMORY.md index text, not the linked
`project_sideeye.md` file itself — I did not open it). From that index text I
noticed, and am disclosing:

- **Vocabulary that matches this task's framing almost exactly**: "crash world",
  "checker", "verify", "recover N/N", "L0-only", "checker-red", "define freeze",
  "probe" (with a "7 conditions" gate), "verdict", "criterion 1..5", "v1.0",
  "TAM", "mini-seal", "verify-assisted", "target-dir", "revision". This close
  vocabulary match is itself information: it makes it very likely the tool this
  task's engine belongs to is sideeye, even though the task prompt never names it.
- **Two of the five assigned targets are named explicitly** in that memory as
  already-touched sideeye subjects:
  - `calcurse` — "upstream watch 継続（calcurse `#529`/... =08-21 コメント0）",
    i.e. sideeye has an open upstream issue/watch against calcurse (issue #529,
    no comments as of 2026-08-21).
  - `stow` — same sentence, "stow `#139`=08-21 コメント0" — an open upstream
    watch against stow, issue #139, no comments as of 2026-08-21.
  I do **not** have the content of those issues, what defect (if any) they
  describe, or any technical detail about calcurse/stow's state handling beyond
  this bare "an issue exists" fact.
- **Other tools named in that same memory as sideeye cohort subjects** (none of
  which overlap this task's five targets, but disclosing for completeness since
  they establish the shape of what sideeye has been testing): hg (Mercurial),
  jj (Jujutsu), bun, cargo/rustc, papis, kpxc (KeePassXC). Specific technical
  claims I noticed about these (not applicable to my assigned targets, not used):
  hg's `checkisexec` / wcache pattern interacting with exec-bit restoration;
  hg reaching a verdict via "L0-only" FAIL classifications across dirstate
  mid-states; cargo/rustc having a raw-syscall visibility problem with Cargo.lock
  renames defeating a shim.
  This tells me nothing about buku/devtodo/pass specifically, only that a
  similar engine has previously found these classes of finding in other tools.
- **Methodology/feedback notes** I noticed and am explicitly setting aside:
  a standing instruction that "small / effectively inactive OSS should not even
  be used as an experiment measurement target" (threshold ≥500 stars, multiple
  contributors, updated within the last month) with a note that project
  selection must be human-confirmed; and a standing instruction that claims
  with numbers/counts/universal quantifiers must be verified against a primary
  source before being written down, not reconstructed from memory. I am
  following the second one as a general writing discipline in these proposals
  (verifying every citation against the actual checkout) but it did not
  originate from reading the targets.

## 3. General (non-injected, pretrained) familiarity

Independent of any injected context, I have ordinary pretrained/background
familiarity with what these five tools are, as any generally-informed engineer
would: buku is a Python/SQLite command-line bookmark manager; calcurse is a
C-based text-mode calendar/scheduler; devtodo is a C++ command-line todo-list
manager; pass (password-store) is the standard POSIX password manager built as
a shell script wrapping GPG and (optionally) git; stow is GNU Stow, a Perl
symlink-farm manager. This is generic public knowledge, not something injected
by this session's memory/project files, and it did not surface any specific
state-file names, formats, or defects — those were all determined below by
actually reading the checkouts.

## What I did with this

I did not use any of the above to choose proposals, targets, or phrasing below.
In particular: I did not treat calcurse or stow differently because they
already have open sideeye watches, did not import the "checkisexec"/wcache
pattern from hg into my calcurse or pass proposals even where structurally
tempting, and every "where from" citation below is a fresh path+line/section
from this task's own targets/ checkout, re-derived by reading, not recalled.
