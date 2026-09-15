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
| `path-blind` | `s\|    if repo in text or "/.claude/" in text or "~/.claude" in text:\|    if False:\|` | all three path markers |
| `docker-blind` | `s\|            escaped = "--network none" not in cmd\|            escaped = False\|` | the missing-`--network none` test |
| `mount-blind` | `s\|                if src.startswith("/") and not src.startswith(stage):\|                if False:\|` | the out-of-stage mount-source test |
| `unauditable-off` | `s\|    sys.exit("audit: the transcript holds no tool calls — nothing-to-see is not clean")\|    pass\|` | the no-tool-calls refusal |
| `restore-silent` | `s\|^if differs(after):$\|if False:\|` | the re-verify after the rebuild (#512, #513; until 2026-09-15 the program targeted the old restore's post-copy hash check, which went with it) |
| `always-clean` | `s\|^verdict = "clean"$\|verdict = "clean"\nnetwork_hits = context_hits = docker_hits = unsealed_hits = []\|` | the verdict itself |
| `case-deleted` | `/    audit_case net-url network_hits/d` | not a branch — the case list itself |
| `record-sha-blind` | `s\|    if want_sha == got_sha:\|    if True:\|` | the digest comparison (#515) |
| `record-torn-blind` | `s\|^        except (UnicodeDecodeError, json.JSONDecodeError) as e:$\|        except (UnicodeDecodeError, json.JSONDecodeError) as e:\\n            continue\|` | the unreadable-line count (#515) — restores the `continue` this change removed |
| `finalize-blind` | `s\|if manifest\["audit"\].get("record_sha") != "verified":\|if False:\|` | finalize's demand for a verified digest (#515) |
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

## What the attribution says

**Twenty-eight mutations, twenty-eight exact sets** — twenty-seven of the judge, one of the
selftest's own case list — measured on 2026-09-15 against the judge with #512 and #513 in it,
and again after each diff review's fixes added rows (four, then two), and every killed set is the
one written into the runner before it ran. No mutation killed a case outside its own channel, and none of the
twenty-six refusals survived the mutation aimed at it.

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
  2026-09-15 run killed twelve again, and `mutations.txt` was rewritten from that run, so the
  thirteen survives only here and in `RESULTS.md`, as a measurement neither re-run reproduced. Each record
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
