#!/usr/bin/env python3
"""rule 11/17 receipts: first-response time on recent issues (PRs excluded).
REST only (/issues, /issues/N/comments) - does not touch the Search API."""
import subprocess, json, sys, datetime as dt

def gh(path):
    r = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  BROKEN gh api {path} rc={r.returncode}: {r.stderr.strip()[:200]}")
        return None
    return json.loads(r.stdout)

def iso(s): return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))

repo, n = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 10
print(f"== rule 11/17 receipts: {repo}")
print(f"== gh api repos/{repo}/issues?state=all&sort=created&direction=desc&per_page=60  (pull_request filtered out)")
print(f"== gh api repos/{repo}/issues/<N>/comments?per_page=100  per issue")
print(f"== run at {dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
print()

items = gh(f"repos/{repo}/issues?state=all&sort=created&direction=desc&per_page=60")
issues = [i for i in items if "pull_request" not in i][:n]
print(f"== {len(items)} items fetched, {len([i for i in items if 'pull_request' not in i])} are issues, showing the {len(issues)} most recent")
print()
within = 0
for i in issues:
    author, num, created = i["user"]["login"], i["number"], iso(i["created_at"])
    labels = ",".join(l["name"] for l in i["labels"]) or "-"
    comments = gh(f"repos/{repo}/issues/{num}/comments?per_page=100") or []
    other = [c for c in comments if c["user"]["login"] != author]
    print(f"#{num}  {i['created_at']}  by={author}  labels=[{labels}]  state={i['state']}")
    print(f"    title: {i['title'][:95]}")
    if not other:
        print("    FIRST RESPONSE: none (no comment from anyone other than the author)")
    else:
        c = other[0]
        d = (iso(c["created_at"]) - created).total_seconds()
        human = f"{d/3600:.1f}h" if d < 172800 else f"{d/86400:.1f}d"
        ok = "WITHIN-1-WEEK" if d <= 7*86400 else "OVER-1-WEEK"
        if d <= 7*86400: within += 1
        print(f"    FIRST RESPONSE: +{human} [{ok}] by {c['user']['login']} ({c['author_association']}) at {c['created_at']}")
    print()
print(f"== {within} of {len(issues)} recent issues answered within 1 week by someone other than the author")
print("== author_association is what distinguishes a maintainer reply from a passer-by; both are listed above")
