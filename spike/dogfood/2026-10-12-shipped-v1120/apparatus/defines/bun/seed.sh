set -eu
# The 2026-09-16 define's dependency (crossed-walls screen.sh), a local tarball so `bun add` needs
# no network; the manifest is longer than that run's, a project's own fields and no dependency to
# resolve.
rm -rf /s/bun /s/bunaux /s/aux/bun-cache && mkdir -p /s/bun /s/bunaux/deppkg/package /s/aux/bun-cache
printf '{ "name": "probe-dep", "version": "1.0.0", "main": "index.js" }\n' > /s/bunaux/deppkg/package/package.json
printf 'module.exports = "probe-dep";\n' > /s/bunaux/deppkg/package/index.js
touch -t 202601010000 /s/bunaux/deppkg/package/package.json /s/bunaux/deppkg/package/index.js /s/bunaux/deppkg/package
tar -czf /s/bunaux/dep-1.0.0.tgz -C /s/bunaux/deppkg package && touch -t 202601010000 /s/bunaux/dep-1.0.0.tgz
cat > /s/bun/package.json <<'EOF'
{
  "name": "probe-proj",
  "version": "1.4.0",
  "description": "A project whose manifest its owner wrote by hand",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "bun run --watch src/index.ts",
    "build": "bun build src/index.ts --outdir dist",
    "test": "bun test"
  },
  "engines": { "bun": ">=1.4" },
  "license": "MIT"
}
EOF
install -m 755 /ap/defines/bun/check.sh /s/bun-check.sh
