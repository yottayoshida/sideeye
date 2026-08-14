# pass — scout proposals (assisted, #118)

T0: 20260814T140706Z. Sources: `pass --help` (pinned v1.7.4), DeepWiki Q&A
on zx2c4/password-store, behavior probes.

## P1 — `pass mv <entry> <subdir>/<entry>` (IMPLEMENTED)

- argv: `pass mv ada moved/ada` (same gpg-id throughout; store is NOT a git
  repo, so all git operations are documented to be silently skipped)
- **why**: the move is a multi-step dance — `mkdir -p` for the new parent,
  `mv` of the .gpg file, `rmdir -p` of emptied old directories — and an
  interrupted move is where a password manager could lose the only copy of
  a secret.
- **what property**: *an interrupted move never loses the secret*: the
  moved entry's ciphertext exists at exactly one of {old path, new path},
  byte-equal to the recorded ciphertext, and still decrypts to the known
  content; the bystander entry and `.gpg-id` are byte-conserved.
- **where from**: DeepWiki-cited `cmd_copy_move` flow (mv + mkdir -p +
  rmdir -p; re-encryption only when the gpg-id changes — same-id moves the
  bytes unchanged); the tool's stated purpose ("the standard unix password
  manager"). Determinism measured: mv over the same pre-state is
  tree-byte-identical (probe).

## P2 — `pass rm -f <entry>` (recorded, not implemented first)

- **why**: rm + rmdir -p of emptied parents. **what property**: deleting
  one entry must not damage the others. **where from**: the help text
  (`pass rm`) and the DeepWiki-cited cmd_delete flow. Deferred — P1 covers the same store with the
  richer window.

## P3 — cross-gpg-id move / generate / insert (recorded: refusal-shaped)

- **why**: a move across a `.gpg-id` boundary re-encrypts through a temp
  file (`passfile_temp`) — the richest window (decrypt/re-encrypt/replace).
- **excluded because**: gpg encryption is randomized (fresh session key per
  run), so every such operation is baseline-irreproducible — the khard
  shape. Same for `generate` (random password) and `insert` (fresh
  encryption). Recorded as the second target in a row whose richest window
  is out of the engine's deterministic reach.
