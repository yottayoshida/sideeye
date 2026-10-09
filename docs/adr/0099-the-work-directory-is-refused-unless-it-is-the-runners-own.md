# 0099 — The work directory is refused unless it is the runner's own

Status: Accepted (2026-10-09)

Closes #692. The engine and the MCP server now ask one question of the work directory before
anything is written under it — is its last component a directory, not a symlink, owned by the
effective user — and refuse with the directory's name, the reason, and the way past it when
the answer is no. Like ADR 0044 for the shim, it is a mitigation on a path that has no
boundary to offer, and this record says what it does not close.

## Context

`--work` defaults to `/tmp/sideeye-work` and the MCP server's `SIDEEYE_MCP_WORK` to
`/tmp/sideeye-mcp`: fixed names in a directory every user can write. The engine ran `mkdir`,
adopted the name on `EEXIST`, and `realpath`ed it — which follows a link — and the only vet
was that it did not sit inside the state directory. The server did the same with mode 0700.

What lives there is not scratch in the harmless sense. A saved case carries the define's
setup, operation and check, and a replay runs them (ADR 0009); the server opens each child's
capture there and reads the report back from it as the call's verdict (ADR 0010). So whoever
made the default name first — as a directory of their own, or as a link to one — chose where
another user's cases went and could replace them before that user replayed one. ADR 0010
carried this as an operational precondition ("the work dir is user-owned and not
attacker-writable"), which a default in `/tmp` does not meet on a shared host and which
nothing checked.

The review that filed #692 also stated that case files are created `O_EXCL` `0o600` at
`main.zig:278`. That line is the fs_usage handshake's sentinel; cases are written by
`case.zig` with mode 0644. Nothing here depends on either mode — a directory somebody else
controls lets them rename a case away whatever its mode.

## Decision

**One verdict, from one `lstat`, in `src/mcp.zig` beside the shim search.** `workDirVerdict`
answers `ok`, `missing`, or `refused` with one of five reasons: a symlink, not a directory, an
owner other than the effective user, a kind or owner that could not be read, or a name whose
last component is `..`. The CLI asks it right after its `mkdir` and before `realpath`; the
server right after its own `mkdir` and before it opens anything — it cannot leave the question
to the engine it starts, because it writes the child's capture into the directory first.
**Neither asks about a directory its own `mkdir` just created**: that one is the runner's by
construction, whatever owner a filesystem reports for it (an NFS export squashing root would
otherwise refuse the directory Sideeye just made, under a sentence promising it creates one).
The CLI holds one answer back: `lstat` reports an earlier component it cannot pass — `ENOTDIR`
under a regular file, `EACCES` under a directory the runner cannot search — the same way as a
name it cannot read, so `unclassifiable` waits for `realpath`, whose failure names the errno as
it always did, and is raised only when the name resolves. The class follows
`docs/report-schema.md`'s placement rule: a name ending in `..` is refused on its text, and a
non-directory takes the class the same refusal of `--state` takes (#682), so both are
`define_invalid`; a link, another user's directory and an unreadable one are the machine's
answer, `environment`. Both
refuse with one sentence, `workDirRefusalMessage`, which takes the subject and the closing
sentence whole from the caller (the `absentMessage` lesson: a slot for the flag alone broke
the CLI's grammar once).

**The effective user is the only owner accepted.** The shim search also accepts root and the
binary's owner (ADR 0044), and the reason there is that the shim is *read*: whoever owns an
install directory could replace the binary itself. A work directory is *written*, and a
root-owned directory a stranger can write — `/tmp` itself, named as `--work /tmp` — would let
the stranger create `cases/` before the run does. Root is accepted when root is running.

**A link at the last component is refused whoever owns it and wherever it points.** Accepting
a link the runner owns to a directory the runner owns would be safe against the case #692
describes, and it would be a second rule with a second set of edges. One rule; the refusal
says to pass the directory itself.

**The name is trimmed before `lstat`, and before `mkdir`.** A trailing `/` or `/.` makes the
last component the directory inside it, reached through the link if it is one, so
`--work /tmp/sideeye-work/` would have walked past the link check. Both are removed,
repeatedly, and a name ending in `..` is refused outright. The `mkdir` that comes first takes
the trimmed name too (`mkdirWorkDir`): on macOS — measured — `mkdir("link/")` with `link` a
dangling symlink creates the link's target and succeeds, which would have made the directory
wherever somebody else's link pointed and then skipped the check as a directory Sideeye had
just created. Under the trimmed name it answers `EEXIST`, and the link is refused. Earlier components are followed, as ADR 0044 follows them: macOS's `/tmp`
is itself a link.

**Every work directory is checked, the default and a named one alike.** ADR 0044 leaves a
named `--shim` unchecked because naming the file is choosing it. Naming `--work /tmp/x` does
not make `/tmp/x` yours.

## Alternatives considered

**Make the default per-user** (`$TMPDIR`, `/tmp/sideeye-work-<uid>`, `$XDG_RUNTIME_DIR`).
Declined: every such name can be made first by somebody else, so the check is needed anyway;
`$TMPDIR` is per-user on macOS and usually unset on Linux, so the default would be safe on one
platform and not the other; and the default appears in `--help`, the README, `docs/cli.md`,
`docs/evidence.md` and every operator's notes. The check closes the exposure on its own.

**Check only the default.** Declined above: the exposure is the name, not who chose it.

**Also refuse a directory of the runner's own that others can write** (mode 0777). Declined
for the reason ADR 0044 declines a directory-mode check: whatever someone else plants is owned
by them, and opening one's own directory to everyone is the runner's choice.

**Create the work directory 0700.** Considered and left out: it is not what #692 promises,
and a root container that creates `/out/work` on a bind mount would hide it from the host
user who reads it back — the shape the dogfood runner uses.

## Consequences

- **A 1.x behaviour change**, recorded in CHANGELOG.md as one: a work directory that ran
  before can now refuse. The shapes known — a link of the runner's own at the name, to a
  directory elsewhere; another user made `/tmp/sideeye-work` first; `sudo sideeye` pointed at a
  directory the user made; a root container handed a bind mount the host user made; a
  Kubernetes `emptyDir` owned by root with an `fsGroup` — each get a sentence naming the
  reason, the uid where the owner is the reason, and the way past it.
- **A directory Sideeye created is not asked about, the first time.** On a filesystem that
  reports another owner for it — an NFS export squashing root, with Sideeye run as root — the
  next run with the same name finds it there and refuses it as someone else's. The way past is
  the same: a new name each run, or running as a user the filesystem reports as itself.
- **A mitigation, not a boundary.** What is inspected is a pathname, once; the engine opens
  names under it afterwards. Anyone who can write the directory's *parent* can swap it between
  the two, and a FUSE mount that other users may access can report whatever owner it likes.
  `docs/cli.md` and `docs/mcp.md` say so beside the rule.
- ADR 0010's operational precondition is amended: the work directory's ownership is now
  checked rather than assumed. What it says about the contents — predictable names, `O_EXCL`
  captures, the unlinks before each child — is unchanged.
- The owner predicate is a function of two uids, unit-tested directly; the refusing case needs
  `chown`, and `spike/acceptance.sh` check 2wd drives it where the host can, with the same
  command against the runner's own directory as its control, and counts it as not measured
  where it cannot. The same check drives the default name with no `--work` at all, and
  `spike/mcp-acceptance.sh` mcp 20 drives the server's, both through a link planted at the
  default.
