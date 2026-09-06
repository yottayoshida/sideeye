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

## What the attribution says

**Thirteen mutations, thirteen exact sets** — twelve of the judge, one of the selftest's
own case list. No mutation killed a case outside its own channel,
and none of the fifteen refusals survived the mutation aimed at it.

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
  measured — which is why the count here is thirteen predicate branches and not seven
  fields.
- **`always-clean` kills eleven, not twelve.** `unauditable` survives, because the
  no-tool-calls path writes its verdict and exits before the assembled `verdict` variable
  is reached. The two refusals are genuinely different code paths, and the selftest judges
  the `unauditable` case on its own terms (two keys, not the per-field assertion) for the
  same reason.

- **`case-deleted` is not a mutation of the judge**, it is a mutation of the selftest, and
  it is here because the closing line used to be a constant: `selftest: thirteen refusals
  and three greens hold` printed whenever `fails` was 0, so deleting a case left the suite
  green with the same wording. The run now counts its own cases and demands 17, and this
  row is that guard seen red — it reports `ran 16 case(s), expected 17` rather than a
  channel failure.
