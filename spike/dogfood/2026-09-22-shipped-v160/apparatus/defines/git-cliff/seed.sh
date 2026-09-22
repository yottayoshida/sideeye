set -eu
rm -rf /s/cliff && mkdir -p /s/cliff/repo && cd /s/cliff/repo
git init -q . && git config user.email t@example.com && git config user.name t
echo a > a && git add a && git commit -qm "feat: first" && git tag v0.1.0
git-cliff -o CHANGELOG.md >/dev/null 2>&1
git add CHANGELOG.md && git commit -qm "chore: changelog"
echo b > b && git add b && git commit -qm "fix: second"
