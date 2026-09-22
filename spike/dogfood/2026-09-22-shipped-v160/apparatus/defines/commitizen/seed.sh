set -eu
rm -rf /s/cz && mkdir -p /s/cz/repo && cd /s/cz/repo
git init -q . && git config user.email t@example.com && git config user.name t
printf "[tool.commitizen]\nname = \"cz_conventional_commits\"\nversion = \"0.1.0\"\ntag_format = \"v\$version\"\nupdate_changelog_on_bump = true\n" > pyproject.toml
git add . && git commit -qm "feat: first" && git tag v0.1.0
echo x > x && git add x && git commit -qm "feat: second"
