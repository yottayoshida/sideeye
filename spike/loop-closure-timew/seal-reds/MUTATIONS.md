# The mutations behind `mutations.txt`

The runner that produced `mutations.txt` is not committed — the `sed` programs below are,
and each one is reproducible by hand against a copy of the file. What the runner added on
top of them was one guard, described in the next paragraph.

Each is a one-line `sed` program applied to a copy of
`spike/loop-closure-timew/judge.sh`; the copy then runs `selftest` and the cases that
report `FAIL` are recorded. A copy that `cmp` finds identical to the original is a
**broken mutation**, not a passing one — the runner reports it as `BROKEN` rather than
letting a no-op edit read as "nothing detected it". That happened once while this record
was being built: the first attempt at `name-unsealed-blind` tried to delete a line by
matching across a newline, which `sed` does not do, and it printed `BROKEN` instead of a
green.

| label | sed program | branch it blinds |
|---|---|---|
| `name-unsealed-blind` | `s\|    elif name in UNSEALED:\|    elif False:\|` | the eleven listed tool names |
| `name-mcp-blind` | `s\|    if name.startswith("mcp__"):\|    if False:\|` | any `mcp__` server that is not the allowed one |
| `off-allowlist-blind` | `s\|if network_hits or context_hits or docker_hits or unsealed_hits or off_allowlist:\|if network_hits or context_hits or docker_hits or unsealed_hits:\|` | the #511 fix: a tool in neither set voids |
| `mcp-prefix-loose` | `s\|                and "__" not in name\[len(allow_prefix):]:\|                and True:\|` | the #514 fix: the trusted prefix names one segment (the `[` escaped since 2026-09-15; see below) |
| `mcp-allow-broken` | `s\|        if allow_prefix and name.startswith(allow_prefix) \\\|        if False and allow_prefix and name.startswith(allow_prefix) \\\|` | the granting side — kills the green, not a red |
| `network-blind` | `s\|^NETWORK = re.compile($\|NETWORK = re.compile(r"(?!x)x") or re.compile(\|` | the whole network regex |
| `path-blind` | `s\|    if REPO_TEXT\.search(text) or "/\.claude/" in text or "~/\.claude" in text:\|    if False:\|` | the three path markers as text (rewritten for #510, when `path-repo` and `path-tilde` began to resolve as well) |
| `docker-blind` | `s\|            escaped = "--network none" not in cmd\|            escaped = False\|` | the missing-`--network none` test |
| `mount-blind` | `s\|                elif all(p is not None and not under_stage(p) for p in landed):\|                elif False:\|` | the out-of-stage mount-source test (rewritten for #510, which resolves the source) |
| `unauditable-off` | `s\|    sys.exit("audit: the transcript holds no tool calls — nothing-to-see is not clean")\|    pass\|` | the no-tool-calls refusal |
| `restore-silent` | `s\|^if differs(after):$\|if False:\|` | the re-verify after the rebuild (#512, #513; until 2026-09-15 the program targeted the old restore's post-copy hash check, which went with it) |
| `always-clean` | `s\|^verdict = "clean"$\|verdict = "clean"\nnetwork_hits = context_hits = docker_hits = unsealed_hits = []\|` | the verdict itself |
| `case-deleted` | `/    audit_case net-url network_hits/d` | not a branch — the case list itself |
| `record-sha-blind` | `s\|    if want_sha == got_sha:\|    if True:\|` | the digest comparison (#515) |
| `record-torn-blind` | `s\|^        except (UnicodeDecodeError, json.JSONDecodeError) as e:$\|        except (UnicodeDecodeError, json.JSONDecodeError) as e:\n            continue\|` | the unreadable-line count (#515) — restores the `continue` this change removed |
| `finalize-blind` | `s\|if manifest\["audit"\].get("record_sha") != "verified":\|if False:\|` | finalize's demand for a verified digest (#515) |
| `inputs-absent-off` | `s\|^if not os.path.exists(inputs_path):$\|if False:\|` | finalize's demand for the launcher's inputs.json (#515's other half, ADR 0066) — the copy then opens a file that is not there, and the refusal stops naming `inputs.json absent` |
| `inputs-unattested-off` | `s\|^        if want is None:$\|        if False:\|` | a record finalize reads that inputs.json does not attest — the copy falls through to the digest comparison and says "changed" instead |
| `inputs-changed-off` | `s\|^        elif sha256(p) != want:$\|        elif False:\|` | a record that changed since the launcher recorded it |
| `record-audit-rehash-off` | `s\|^        if record_now != manifest\["audit"\].get("record_sha_value"):$\|        if False:\|` | the transcript hashed now against the audit's own digest — `finalize-record-changed` asserts both sentences, so blinding this one alone fails it |
| `record-launcher-rehash-off` | `s\|^        if record_now != launcher_record:$\|        if False:\|` | the transcript hashed now against the launcher's digest — the other sentence of the same case |
| `mode-compare-blind` | `s\|        if (stat.S_IMODE(st.st_mode) & 0o700) != want:\|        if False:\|` | the owner-bits comparison (#513) |
| `not-regular-blind` | `s\|            if stat.S_ISLNK(st.st_mode) or not want_type(st.st_mode):\|            if False:\|` | a symlink, or anything not a regular file, on a sealed file's path (#513) |
| `delete-blind` | `s\|        remove_tree(full)\|        pass\|` | the rebuild's removal of everything outside `repo/` (#512) |
| `pristine-off` | `s\|    if require == "pristine" and differs(first):\|    if False:\|` | the pristine check's refusal (#512) |
| `repo-guard-off` | `s\|^if len(tops) != 1:$\|if False:\|` | the rebuild's refusal when there is no single `repo/` directory to keep |
| `unlock-off` | `s\|^        unlock(path)$\|        pass\|` | opening each directory (owner's rwx, flags cleared) before the record is taken and the stage emptied |
| `unreadable-blind` | `s\|os.walk(stage, onerror=note_unreadable)\|os.walk(stage)\|` | a directory the record cannot list, counted as a difference |
| `stage-link-guard-off` | `s\|    if not stat.S_ISDIR(stage_st.st_mode):\|    if False:\|` | the rebuild's refusal of a stage that is a symlink |
| `history-off` | `s\|^    history.write(json.dumps(first) + "\\n")$\|    pass\|` | every rebuild's record appended to `<mode>-stage-diffs.jsonl` |
| `extra-descend-off` | five `-e` arguments: `/Recorded, and walked/{`, `n`, `n`, `s\|keep.append(name)\|pass\|`, `}` | walking into a directory the seal does not hold, so the files in it are named (the line is one of two identical ones, so the program finds it from the comment above it) |
| `stage-unlock-first-off` | `/^    unlock(stage)$/d` | opening the stage before `repo/` is looked up, so a stage without its x bit still has its `repo/` found (second review) |
| `finalize-union-off` | `s\|    return sorted(set(sd.get(key) or \[\]).union(\*(r.get(key) or \[\] for r in attempts)))\|    return sorted(set(sd.get(key) or []))\|` | finalize's lists across every rebuild attempt, not the last attempt's alone (second review) |
| `relative-off` | `s\|        path = cwd + "/" + word\|        return None\|` | resolving a relative word at all (#510) |
| `cd-off` | `s\|cwd, prev = new, cwd\|pass\|` | following `cd`, `pushd` and `popd` (#510) |
| `tilde-off` | `s\|        word = home + word\[1:\]\|        pass\|` | expanding `~` (#510) |
| `home-pwd-off` | `s\|^    return HOME_PWD\.sub(.*$\|    return word\|` | expanding `$HOME` and `$PWD` (#510) |
| `ln-off` | `s\|links\[link\] = dest\|pass\|` | the record's `ln -s` names (#510) |
| `identity-off` | `s\|    return by_identity(p)\|    return any(p.startswith(t) for t in TARGETS)\|` | comparing by identity, put back to an unbounded prefix (#510) |
| `string-compare-off` | `s\|    if any(p == t or p\.startswith(t + "/") for t in SPELLINGS):\|    if False:\|` | the bounded string comparison, the only way to meet a config dir that does not exist (#510) |
| `ancestor-off` | `s\|            for vs in votes\.values() if all(v for v, _ in vs)\]\|            for vs in votes.values() if False]\|` | the recursive read of an ancestor (#510) |
| `ancestor-any` | `s\|if all(v for v, _ in vs)\]\|if any(v for v, _ in vs)]\|` | that read voided from one candidate rather than all — against the owner's ruling (#510) |
| `glob-off` | `s\|            globbed\[p\] = list(itertools\.islice(glob\.iglob(p), 256)) or \[p\]\|            globbed[p] = [p]\|` | expanding a glob outside the stage (#510) |
| `carry-held` | `s\|finals\.append((cwd, prev))\|finals.extend((d, prev) for d in held)\|` | carrying only where each candidate ended, so the candidates grow by one a call (#510) |
| `text-boundary-off` | `s\|    if REPO_TEXT\.search(text) or\|    if repo in text or\|` | the name boundary on the repo's path as text (#510) |
| `mount-old-rule` | `s\|                elif all(p is not None and not under_stage(p) for p in landed):\|                elif src.startswith("/") and not src.startswith(stage):\|` | resolving a mount source, put back to the absolute-only test (#510's same class) |
| `mount-any` | `s\|                elif all(p is not None and not under_stage(p) for p in landed):\|                elif any(p is not None and not under_stage(p) for p in landed):\|` | a mount voided when only some candidates put it outside the stage |
| `mount-unresolved-off` | `s\|                elif any(p is None or not under_stage(p) for p in landed):\|                elif False:\|` | recording a mount the candidates disagree on |
| `basename-off` | `s\|word0 = os\.path\.basename(args\[0\]) if args else ""\|word0 = args[0] if args else ""\|` | a command word by its base name (#510, first review) |
| `env-prefix-off` | `s\|{"env": ("uCSP", 0), \|{\|` | `env` as a wrapper before the command word (#510, first review; rewritten after the second) |
| `find-options-off` | `s\|            rest = rest\[2:\] if rest\[0\] == "-D" else rest\[1:\]\|            break\|` | find's options before its paths (#510, first review; rewritten after the second) |
| `shell-string-off` | `s\|        if nested < 4 and word0 in SHELLS and flag is not None:\|        if False:\|` | following a string handed to `sh -c` or `bash -c` (#510, first review; rewritten after the second) |
| `subshell-restore-off` | `s\|            cwd, prev, maybe = saved\.pop()\|            saved.pop()\|` | undoing a subshell's `cd` at its closing parenthesis (#510, first review; rewritten after the second) |
| `held-off` | `s\|for d in held:\|for d in [cwd]:\|` | resolving a word against every directory held in the call, which covers a `cd` that may not run (#510, first review) |
| `pushd-off` | `s\|        if word0 in ("cd", "pushd", "popd"):\|        if word0 == "cd":\|` | `pushd` and `popd` (#510, first review) |
| `tool-path-off` | `s\|                hit = lands_in_target(inp\[key\], cwd)\|                hit = None\|` | the path keys of a call that is not Bash (#510, first review) |
| `glob-pattern-off` | `s\|        if name == "Glob" and isinstance(inp\.get("pattern"), str) and inp\["pattern"\] and base:\|        if False:\|` | a Glob's pattern (#510, first review) |
| `brace-var-off` | `s#\\{(HOME\|PWD)\\}\|#\\{(NOPE)\\}\|#` | the `${…}` spelling of the two variables (#510, first review) |
| `ancestor-identity-off` | `s\|    return p in ancestor_strs or ident(p) in ancestor_ids\|    return p in ancestor_strs\|` | an ancestor met under another name (#510, first review) |
| `host-link-off` | `s\|            if not under_stage(prefix) and os\.path\.islink(prefix):\|            if False:\|` | a `..` after a symlink outside the stage (#510, first review) |
| `pattern-drop-off` | `s\|            ops = ops\[1:\]\|            pass\|` | grep's pattern not taken for a place it reads (#510, first review) |
| `regexp-value-off` | `s\|                    skip = i == len(a) - 2\|                    skip = False\|` | the value of a short option (`-e /`, `-A 2`) not taken for a place (#510, first review; rewritten after the second) |
| `fastpath-links` | `s\|        if not any(lexical == k or lexical\.startswith(k + "/") for k in links):\|        if True:\|` | the lexical shortcut, passed over for a path that runs through an `ln -s` name (#510, first review — speed; rewritten after the second) |
| `fastpath-dotdot` | `s\|    if "\.\." not in path\.split("/"):\|    if True:\|` | the same shortcut, taken only for a word with no `..` (#510, first review — speed; rewritten after the second) |
| `may-leave-off-by-one` | `s\|    if climb > depth:\|    if climb > depth + 1:\|` | skipping a directory inside the stage deeper than a word climbs, at its exact bound (#510, first review — speed; rewritten after the second) |
| `may-leave-links-off` | `s\|    return any(k == top or k\.startswith(top + "/") for k in links)\|    return False\|` | an `ln -s` name under the highest directory a word reaches, which keeps the skip from applying (#510, second review — speed) |
| `wrapper-value-off` | `s\|            if len(opt) == 2 and opt\[1\] in valued and args:\|            if False:\|` | a wrapper option's value given as the next word (`sudo -u nobody`) (#510, second review) |
| `wrapper-operands-off` | `s\|        del args\[:operands\]\|        pass\|` | the operands before the command a wrapper runs (`timeout 10`) (#510, second review) |
| `eval-carry-off` | `s\|            cwd, prev = follow(" ".join(args)\|            follow(" ".join(args)\|` | eval's `cd` staying in the shell (#510, second review) |
| `find-exec-off` | `s\|                if a in ("-exec", "-execdir", "-ok", "-okdir"):\|                if False:\|` | following the command find's `-exec` runs (#510, second review) |
| `paren-restore-back` | `s\|^    return cwd, prev$\|    if saved:\n        cwd, prev, maybe = saved[0]\n    return cwd, prev\|` | the end-of-command restore of an unmatched parenthesis, put back (#510, second review) |
| `bsnl-off` | `/continues the line$/d` | a backslash-newline continuing the line (#510, second review) |
| `and-narrow-off` | `s\|        if last is not None and "&&" in sep:\|        if False:\|` | `cd x && …` running in x alone (#510, second review) |
| `maybe-off` | `s\|            seen = \[ancestor_vote(op, d) for d in maybe\]\|            seen = [ancestor_vote(op, cwd)]\|` | a recursive read judged from every place a `cd` that may not have run could have left the command (#510, second review) |
| `nested-votes-own` | `s\|follow(args\[flag + 1\], cwd, prev, held, votes,\|follow(args[flag + 1], cwd, prev, held, {},\|` | a nested command's recursive reads counted with the call's own (#510, second review) |
| `grep-given-off` | `s\|                    given = given or a\[1 + i\] in "ef"\|                    pass\|` | `-e` or `-f` with its value attached marking the pattern as given (#510, second review) |
| `rg-files-off` | `s\|ops, given, skip = \[\], name == "rg" and "--files" in args, False\|ops, given, skip = [], False, False\|` | rg's `--files`, which takes no pattern (#510, second review) |
| `find-HP-off` | `s\|("-H", "-L", "-P", "-D")\|("-L", "-D")\|` | find's `-H` and `-P` (#510, second review) |
| `du-off` | `s\|    if name in ("tree", "du"):\|    if False:\|` | `tree` and `du` as recursive readers (#510, second review) |
| `ls-recursive-off` | `s\|        return (ops or \["\."]) if ("R" in flags or "--recursive" in args) else None\|        return None\|` | `ls -R` as a recursive reader (#510, second review) |
| `grep-reader-off` | `s\|    if name in ("grep", "egrep", "fgrep", "rg"):\|    if False:\|` | grep and rg as recursive readers in a Bash command (#510, second review) |
| `spellings-realpath-off` | `s\|SPELLINGS = sorted({s for t in TARGETS for s in (t, os\.path\.realpath(t))})\|SPELLINGS = sorted(TARGETS)\|` | a target's resolved spelling in the string comparison (#510, second review) |
| `popd-off` | `s\|            if word0 == "popd" or ops\[:1\] == \["-"]:\|            if False:\|` | `popd` and `cd -` (#510, second review) |
| `tilde-guard-off` | `s\|pass  # no user can be called that\|raise  # no user can be called that\|` | a `~` name no user can have, left as written rather than stopping the audit (#510, second review) |
| `ln-into-dir-off` | `s\|                if made in (".", "..") or made\.endswith("/"):\|                if False:\|` | a link named `.`, `..` or with a trailing `/`, made inside that directory (#510, found while measuring the speed) |

## What the attribution says

**2026-09-16, #515's other half: eighty-five mutations, eighty-four killing exactly the recorded
or predicted set and `carry-held` its one case more, as before.** The five new rows blind
`finalize`'s five new lines one at a time — the demand for `inputs.json`, the unattested-record
branch, the changed-record branch, and the two comparisons of the transcript hashed now (to the
audit's digest, to the launcher's) — and each kills its own case alone; the two record
comparisons kill the same case, `finalize-record-changed`, which asserts both sentences so that
neither survives on its own. `inputs-unattested-off` is worth a sentence: with its `if` blinded
the copy falls through to the digest comparison against `None`, so the case is refused for the
wrong reason ("changed") and fails on the sentence it asserts — the assertion is on the reason,
not on the exit. The eighty-five were run by a script that read this table, four at a time,
and one row came back wrong that way twice: `record-torn-blind` was reported killing every
audit case. Applied by hand from the rendered table it killed `record-torn` alone, and the
difference was this file: the row's source held `\\n` — two backslashes — where `always-clean`'s
holds one, so a runner feeding the source text to `sed` put the two characters `\n` into the
copy on one line and every audit failed on a syntax error. The row is written with one
backslash now, like its neighbour, and `mutations.txt` carries the by-hand run. A table meant
to be applied as written has to be written as it is applied. `extra-descend-off` (five `-e`
arguments) was applied by hand too, the runner reading the table as one program per row.

**Eighty mutations; seventy-nine killed exactly the set written into the runner before it ran, and
one killed a case more** — seventy-nine of the judge, one of the selftest's own case list. The
twenty-eight rows above `relative-off` were measured on 2026-09-15 against the judge with #512 and
#513 in it, and again after each diff review's fixes added rows (four, then two); all eighty were
measured again that evening against the final judge for #510. The one that differed is
`carry-held`: besides `path-many-cd` it killed `path-ancestor-maybe`, and not on a verdict. That
green, like every path green, holds `cwd_candidates_max` to the calls plus one, and its single call
holds a `cd`, so carrying every directory the call held gives three candidates against a bound of
two; the prediction had counted only the green built for that bound. `relative-off` and `cd-off`
kill a mount case each beside the path cases, because the mount check resolves its source with the
same function; no other mutation killed a case outside its own channel, and every one of the sixty
refusals is killed by at least one.

**The fifty-two rows for #510, and three things they say.** Fifteen came with the change,
seventeen with its first review's fixes, nineteen with its second review's, and one with the speed
check that followed. `path-blind` kills `path-dotclaude` alone now: `path-repo`
and `path-tilde` void through the resolution as well as the text, so only a home that is not the
audit's own is left for the text test. The three rows marked "speed" are each the nearest wrong
form of a shortcut that, when right, changes no verdict and so cannot be seen by one: a lexical
shortcut that ignores an `ln -s` name, one that ignores a `..`, and a skip one directory too far
— which is why `path-alias` reaches its symlink with a single `..`. And one spelling is not
driven: `~user` expands to that user's home on the host, which the selftest does not read.

**One row in this table did not do what it said.** `mcp-prefix-loose` as first committed
changed nothing: `name[len(allow_prefix):]` is a bracket expression to `sed` — one character
from that set — and the line holds a `[` at that point, so the copy came back identical and the
runner reported it BROKEN (this Mac's `/usr/bin/sed`). With the bracket escaped it kills
`name-mcp-nested` alone, the set `mutations.txt` had carried for it; whatever produced that
earlier row was not the program printed here. It is the same class as `record-torn-blind`'s
first attempt below, which is the reason the runner compares before it believes a kill.

**The twelve rows for the rebuild and its record** kill what they were predicted to. Three are worth a sentence:

- **`not-regular-blind` kills `restore-symlink` and `restore-dirlink` on their records, not
  their disks.** With the link test blinded the rebuild still removes the link and copies the
  seal back, so the stage comes out right; what goes wrong is that the record calls the file
  `modified` instead of `not_regular`. That is why each rebuild case asserts its key after the
  disk, and why `check-pristine-link` points at a file with the seal's own bytes — so it can
  only refuse through this test.
- **`delete-blind` kills six: both link cases, the three removal cases and the rerun.** A
  rebuild that removes nothing copies the seal's bytes *through* a link, which is the old
  restore's defect, and the re-verify then refuses; the rerun fails because its second rebuild
  leaves the added file where it was.
- **`unlock-off` now blinds the directory opening, and kills both closed-directory rebuilds.**
  `restore-locked-extra` cannot unlink inside its read-only directory and
  `restore-unreadable-extra` cannot list its closed one, and the rebuild names the path and
  stops. `extra-descend-off` kills `restore-locked-extra` alone, because it is the only case
  whose added directory has a file in it for the record to name.

**The repo guard was two statements until these rows were designed**: one refusing a missing or
non-directory `repo/`, one refusing unless exactly one top-level entry is `repo/`. A missing
`repo/` tripped both, so blinding either alone killed nothing, and the row would have been a
guard measured by nothing. They are one statement now, and `repo-guard-off` kills
`restore-no-repo`. `unlock-off` was run as a user; as root the read-only bits are ignored, and
that row is not expected to hold there.

The two fixes shipped with `#511`/`#514` are falsified in **both** directions, which is
the part a one-sided mutation would miss. Reverting either fix kills exactly its own red
(`off-allowlist-blind` → `name-off-allowlist`, `mcp-prefix-loose` → `name-mcp-nested`),
and breaking the *granting* branch kills exactly the green (`mcp-allow-broken` →
`mcp-allowed`). Without that third one, tightening the prefix test could have closed the
surface the mcp variant actually runs on and every red here would still have passed.

Two more rows are worth reading twice:

- **`docker-blind` kills `docker-nonet` only.** `docker-mount` survives it, and that is
  correct: an absolute mount source outside the stage sets `escaped` through a different
  statement. It takes `mount-blind` to kill it. A test suite counted per *output field*
  would have had one docker case, and one of these two branches would never have been
  measured — which is why the count here is sixteen predicate branches and not seven
  fields.
- **Neither record case is among what `always-clean` kills (#515).** The two record
  channels exit before the assembled `verdict` variable is reached, for the same reason
  `unauditable` does. Measured rather than assumed: re-run on 2026-09-09 against the
  current judge, that mutation kills twelve and the standing cases are `unauditable`,
  `name-off-allowlist`, `record-sha`, `record-torn` and `restore-fail`. The row the original
  runner committed to `mutations.txt` listed thirteen, `name-off-allowlist` among them; the
  2026-09-15 morning run killed twelve again, and `mutations.txt` was rewritten from that run;
  the run on the final judge for #510 kills forty-six, the twelve and the thirty-four refusals
  #510 added, so the thirteen survives only here and in `RESULTS.md`, as a measurement no re-run reproduced. Each record
  case has its own mutation above, and each killed exactly its own case and nothing else.
  `record-torn-blind` was rewritten four times, and every failure was one class: a program
  that does not match the file it mutates comes back identical and reads as "nothing
  detected it". The first targeted the `append` line, whose `[:120]` is a bracket expression
  to `sed`. The second anchored eight leading spaces where the file had four. The third was
  correct until the loop moved back inside a `with` block during the cleanup pass and the
  indent changed again. A reviewer found the second; the rest were caught by running `cmp`
  before believing a kill, which is what this file's contract asks for and what the first
  two skipped. The committed version kills `record-torn` alone, and `cmp` says it changes
  the file.
  `finalize-blind` is the newest: `finalize`'s demand for a verified digest, blinded, kills
  `finalize-unverified` alone — the gate that carries the other half of the judge's promise,
  which shipped unmeasured until a reviewer showed that `finalize` can be driven after all.
  `unauditable` and the record cases are genuinely different code paths from the assembled
  verdict, and the selftest judges `unauditable` on its own terms (a few keys, not the
  per-field assertion) for the same reason.

- **`case-deleted` is not a mutation of the judge**, it is a mutation of the selftest, and
  it is here because the closing line used to be a constant: `selftest: thirteen refusals
  and three greens hold` printed whenever `fails` was 0, so deleting a case left the suite
  green with the same wording. The run now counts its own cases and demands `WANT_CASES`,
  and this row is that guard seen red — it reports one case short of the expected total
  rather than a channel failure. The number is not quoted here: it moves whenever a case is
  added, and a figure kept in prose beside the thing it counts is how this file went stale
  in the first place.

## Mutations of `spike/container_seals.py` (#597)

The seals on the eval container's channels live in a second file the judge executes from its
bytes, so these programs are applied to a copy of `spike/container_seals.py` and the copy is
placed where a selftest run finds it (`SIDEEYE_REPO=<dir holding only spike/container_seals.py>`,
the judge's own selftest then loads it as `cmd_eval` would). Each is meant to kill exactly one
`seal-*` case; the module's own `--selftest` goes red under every one of them as well.

| label | sed program | branch it blinds |
|---|---|---|
| `seal-count-blind` | `s\|    if n > 1:\|    if False:\|` | more than one token — a forgery beside the real one |
| `seal-missing-blind` | `s\|    if n == 0:\|    if n == 0 and False:\|` | no token at all — the copy then indexes a token that is not there, so the kill is a traceback rather than a wrong gate; there is no one-line edit that makes "missing" read as sealed, since there is no digest to compare |
| `seal-mismatch-blind` | `s\|    if got != want:\|    if False:\|` | the file's bytes against sideeye's digest |
| `not-regular-blind` | `s\|        if not stat.S_ISREG(st.st_mode):\|        if False:\|` | a FIFO / link / directory at the report's name — the copy reads EOF from the writerless FIFO and refuses as `seal_mismatch`, the wrong reason |
| `too-large-loose` | `s\|> max_bytes:\|> 10 ** 12:\|` | the size cap, both the `fstat` check and the one while reading (one program, because blinding either alone leaves the other to refuse) |
| `not-json-blind` | `s\|        return {"gate": "not_json", "channel": "report", "detail": "sealed bytes do not parse: %s" % e}\|        return {"gate": "sealed", "channel": "report", "sha256": want, "doc": {}}\|` | sealed bytes that do not parse — the copy calls them a sealed empty document |
| `seal-none-blind` | `s\|    if value == b"none":\|    if False:\|` | sideeye's own "the report was not written" token. **Kills no `seal-*` case**: the judge's selftest has no `none` case, and the module's `--selftest` is what goes red. Recorded rather than hidden — the judge sees this branch only through `acceptance.sh`'s check 11h |
| `seal-anchored` | `s\|    n = log.count(prefix)\|    n = sum(1 for l in log.split(b"\\n") if l.startswith(prefix))\|` | the rule itself: puts the line-anchored count back, so the hidden-then-forged stream reads as one token — the review's hole (R1 C1), killed by `seal-ambiguous` alone |
