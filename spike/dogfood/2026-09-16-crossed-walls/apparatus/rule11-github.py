"""Rule 11 on bug reports: first reply from somebody other than the reporter.

Copied from spike/dogfood/2026-09-16-userview-3/apparatus/ with two changes for this run:
repositories come from argv, and an issue younger than MIN_AGE_DAYS or filed by the
repository's own owner, member or collaborator is skipped. The copy as it was counted a
maintainer's self-filed tracking issue and a two-day-old report as "no response" (prettier's
#20070 and #20054, filed by a core member, were the first readings of this run).
"""
import json, subprocess, datetime, sys

MIN_AGE_DAYS = 7
NOW = datetime.datetime.utcnow()

REPOS = sys.argv[1:]


def gh(path):
    r = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return json.loads(r.stdout)


def parse(t):
    return datetime.datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ")


for repo in REPOS:
    print(f"=== {repo} ===")
    issues = gh(f"repos/{repo}/issues?state=all&per_page=60&sort=created&direction=desc")
    if issues is None:
        print("  API error")
        continue
    shown = 0
    for it in issues:
        if "pull_request" in it:
            continue
        if shown >= 4:
            break
        n, created, ncom = it["number"], it["created_at"], it["comments"]
        if (NOW - parse(created)).days < MIN_AGE_DAYS:
            continue
        if it.get("author_association") in ("OWNER", "MEMBER", "COLLABORATOR"):
            continue
        author = it["user"]["login"]
        if ncom == 0:
            print(f"  #{n} {created[:10]} by {author}: 0 comments  <- no response")
            shown += 1
            continue
        cs = gh(f"repos/{repo}/issues/{n}/comments?per_page=10")
        if not cs:
            print(f"  #{n} {created[:10]}: comments unreadable")
            shown += 1
            continue
        # 報告者自身のコメントは「反応」に数えない
        others = [c for c in cs if c["user"]["login"] != author]
        if not others:
            print(f"  #{n} {created[:10]} by {author}: {ncom} comments, all from the reporter  <- no response")
            shown += 1
            continue
        first = others[0]
        delta = parse(first["created_at"]) - parse(created)
        days = delta.total_seconds() / 86400
        mark = "OK" if days <= 7 else "SLOW"
        print(f"  #{n} {created[:10]} by {author}: first reply from {first['user']['login']} "
              f"after {days:.1f}d [{mark}]  {it['title'][:52]}")
        shown += 1
    print()
