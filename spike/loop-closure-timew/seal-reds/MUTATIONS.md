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
| `mcp-prefix-loose` | `s\|                and "__" not in name[len(allow_prefix):]:\|                and True:\|` | the #514 fix: the trusted prefix names one segment |
| `mcp-allow-broken` | `s\|        if allow_prefix and name.startswith(allow_prefix) \\\|        if False and allow_prefix and name.startswith(allow_prefix) \\\|` | the granting side — kills the green, not a red |
| `network-blind` | `s\|^NETWORK = re.compile($\|NETWORK = re.compile(r"(?!x)x") or re.compile(\|` | the whole network regex |
| `path-blind` | `s\|    if repo in text or "/.claude/" in text or "~/.claude" in text:\|    if False:\|` | all three path markers |
| `docker-blind` | `s\|            escaped = "--network none" not in cmd\|            escaped = False\|` | the missing-`--network none` test |
| `mount-blind` | `s\|                if src.startswith("/") and not src.startswith(stage):\|                if False:\|` | the out-of-stage mount-source test |
| `unauditable-off` | `s\|    sys.exit("audit: the transcript holds no tool calls — nothing-to-see is not clean")\|    pass\|` | the no-tool-calls refusal |
| `restore-silent` | `s\|        sys.exit("restore failed for %s: hash still differs from the seal" % rel)\|        pass\|` | the post-restore hash check |
| `always-clean` | `s\|^verdict = "clean"$\|verdict = "clean"\nnetwork_hits = context_hits = docker_hits = unsealed_hits = []\|` | the verdict itself |
| `case-deleted` | `/    audit_case net-url network_hits/d` | not a branch — the case list itself |
| `record-sha-blind` | `s\|    if want_sha == got_sha:\|    if True:\|` | the digest comparison (#515) |
| `record-torn-blind` | `s\|^        except (UnicodeDecodeError, json.JSONDecodeError) as e:$\|        except (UnicodeDecodeError, json.JSONDecodeError) as e:\\n            continue\|` | the unreadable-line count (#515) — restores the `continue` this change removed |
| `finalize-blind` | `s\|if manifest\["audit"\].get("record_sha") != "verified":\|if False:\|` | finalize's demand for a verified digest (#515) |

## What the attribution says

**Sixteen mutations, sixteen exact sets** — fifteen of the judge, one of the selftest's
own case list. No mutation killed a case outside its own channel,
and none of the eighteen refusals survived the mutation aimed at it.

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
  `name-off-allowlist`, `record-sha`, `record-torn` and `restore-fail`. The committed row
  in `mutations.txt` lists thirteen, `name-off-allowlist` among them; the disagreement
  between the original runner and this re-run is recorded rather than resolved. Each record
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
