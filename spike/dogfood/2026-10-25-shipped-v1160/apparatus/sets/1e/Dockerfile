# Set 1's fifth target (set 1 used up scout 1's ten; set 2's unused reserves, in order: Lerna,
# Prisma, knex). Each from npm as it answered on 2026-10-25. Node 24.22.1 as set 2 took it.
# Network at build only: the projects a define starts from are installed here.
FROM sideeye-sv1025
RUN cd /tmp/dl && curl -fsSL -o node.txz https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-arm64.tar.xz && \
    mkdir -p /opt/node && tar xJf node.txz -C /opt/node --strip-components=1 && /opt/node/bin/node --version
# Lerna 10.1.1: a three-package workspace, installed once; the seed copies it (node_modules included).
RUN set -e; P=/opt/lerna-proto; mkdir -p $P/packages/a $P/packages/b $P/packages/c && cd $P && \
    printf '{\n  "name": "mono",\n  "private": true,\n  "workspaces": ["packages/*"],\n  "devDependencies": {"lerna": "10.1.1"}\n}\n' > package.json && \
    printf '{\n  "$schema": "node_modules/lerna/schemas/lerna-schema.json",\n  "version": "1.0.0"\n}\n' > lerna.json && \
    for p in a b c; do printf '{\n  "name": "@mono/%s",\n  "version": "1.0.0",\n  "dependencies": {%s}\n}\n' $p "$( [ $p = a ] || echo '"@mono/a": "^1.0.0"' )" > packages/$p/package.json; done && \
    npm install --no-audit --no-fund > /tmp/npm-lerna.log 2>&1 && npx lerna --version && echo "OK lerna proto"
# Prisma 7.10.1 (GitHub's latest release; npm's `latest` tag points at 8.0.0-rc.27, a release candidate) on SQLite: a project whose schema.prisma db pull rewrites, and the database it reads.
RUN set -e; P=/opt/prisma-proto; mkdir -p $P/prisma && cd $P && npm init -y > /dev/null && \
    npm install --no-audit --no-fund prisma@7.10.1 > /tmp/npm-prisma.log 2>&1 && npx prisma --version | head -3 && echo "OK prisma"
# knex 3.3.0 with better-sqlite3 13.0.3.
RUN set -e; P=/opt/knex-proto; mkdir -p $P && cd $P && npm init -y > /dev/null && \
    npm install --no-audit --no-fund knex@3.3.0 better-sqlite3@13.0.3 > /tmp/npm-knex.log 2>&1 && npx knex --version && echo "OK knex"
RUN apt-get install -y --no-install-recommends sqlite3 > /dev/null 2>&1; \
    { echo "node $(node --version)"; echo "lerna $(cd /opt/lerna-proto && npx lerna --version)"; \
      echo "prisma $(cd /opt/prisma-proto && npx prisma --version 2>&1 | head -1)"; echo "knex $(cd /opt/knex-proto && npx knex --version 2>&1 | head -1)"; \
      echo "link node: $(file -bL /opt/node/bin/node | cut -c1-100)"; } | tee /versions.txt
