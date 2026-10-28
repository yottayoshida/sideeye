# A three-package workspace at version 1.0.0, committed, whose node_modules is the box's install
# (a symlink: Lerna reads the packages from the workspaces globs, not from node_modules).
set -eu
rm -rf /s/mono && mkdir -p /s/mono && cd /opt/lerna-proto && tar cf - --exclude=node_modules . | tar xf - -C /s/mono
cd /s/mono && ln -s /opt/lerna-proto/node_modules node_modules && printf 'node_modules\n' > .gitignore
git init -q && git add -A && git -c user.email=seed@example.invalid -c user.name=seed commit -q -m init
cat > /s/lerna-check.sh <<'CHK'
#!/bin/sh
# Every manifest Lerna rewrites still parses, and each says either the old version or the new one.
cd "$SIDEEYE_STATE_DIR" || exit 1
for f in lerna.json package-lock.json packages/a/package.json packages/b/package.json packages/c/package.json; do
  v=$(node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(j.version ?? "-")' "$f" 2>/dev/null) || { echo "falsify: $f does not parse ($(wc -c < "$f") bytes)"; exit 1; }
  case "$v" in 1.0.0|2.0.0|-) ;; *) echo "falsify: $f says version $v"; exit 1 ;; esac
done
exit 0
CHK
chmod 755 /s/lerna-check.sh
