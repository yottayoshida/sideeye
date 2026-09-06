import json, subprocess, datetime, sys

REPOS = ["xiph/flac", "quodlibet/mutagen", "fontforge/fontforge", "pimutils/vdirsyncer"]


def gh(path):
    r = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return json.loads(r.stdout)


def parse(t):
    return datetime.datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ")


for repo in REPOS:
    print(f"=== {repo} ===")
    issues = gh(f"repos/{repo}/issues?state=all&per_page=25&sort=created&direction=desc")
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
