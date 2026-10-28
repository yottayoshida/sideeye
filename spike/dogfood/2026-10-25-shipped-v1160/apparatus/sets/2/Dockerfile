# Set 2 of the 2026-10-25 shipped-v1160 run: developer tooling (transcripts/scout-2.txt).
# Each tool from its own latest release as GitHub, npm and nextcloud.com answered on 2026-10-25;
# PHP from Debian trixie. Network at build only: every project a define starts from is made here.
FROM sideeye-sv1025

RUN apt-get install -y --no-install-recommends php8.4-cli php8.4-xml php8.4-mbstring php8.4-sqlite3 \
      php8.4-zip php8.4-gd php8.4-curl php8.4-intl php8.4-bcmath php8.4-gmp composer sqlite3 \
      > /tmp/apt-php.log 2>&1 && echo "OK php composer" || { echo "MISSING php"; tail -5 /tmp/apt-php.log; }

# Node 24.22.1, the LTS line's latest on 2026-10-25, from nodejs.org.
RUN cd /tmp/dl && curl -fsSL -o node.txz https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-arm64.tar.xz && \
    mkdir -p /opt/node && tar xJf node.txz -C /opt/node --strip-components=1 && /opt/node/bin/node --version

# Gogs 0.14.3: its linux_arm64 release tarball.
RUN cd /tmp/dl && curl -fsSL -o gogs.tgz https://github.com/gogs/gogs/releases/download/v0.14.3/gogs_v0.14.3_linux_arm64.tar.gz && \
    tar xzf gogs.tgz -C /opt && ls /opt/gogs && ln -sf /opt/gogs/gogs /opt/bin/gogs

# A Gogs instance, made once here so the explore needs no network: `gogs web` started for a few seconds
# creates the tables (0.14.3's `admin create-user` on a fresh database creates only some of them and
# then says "user already exists": transcripts/build-set2.txt), alice is added and backed up (the
# archive the define restores), then bob and a changed avatar make the instance the restore replaces.
# Paths in app.ini are relative to GOGS_WORK_DIR, so the seed can copy the instance into the state.
COPY gogs-app.ini /opt/gogs-proto/custom/conf/app.ini
RUN set -eu; P=/opt/gogs-proto; mkdir -p $P/data/avatars $P/repositories /s/gogsaux/log; cd $P; \
    export GOGS_WORK_DIR=$P GOGS_CUSTOM=$P/custom; \
    (gogs web --config $P/custom/conf/app.ini > /tmp/gogs-web.log 2>&1 & echo $! > /tmp/gogs.pid; sleep 8; kill $(cat /tmp/gogs.pid)); sleep 1; \
    gogs admin create-user --config $P/custom/conf/app.ini --name alice --password 'correct-horse-9' --email alice@example.com --admin; \
    mkdir -p $P/repositories/alice/notes.git && git init -q --bare $P/repositories/alice/notes.git; \
    printf 'avatar-of-alice-v1' > $P/data/avatars/1; \
    mkdir -p /opt/gogs-backup && gogs backup --config $P/custom/conf/app.ini --target /opt/gogs-backup --archive-name gogs-backup.zip; \
    gogs admin create-user --config $P/custom/conf/app.ini --name bob --password 'battery-staple-7' --email bob@example.com; \
    printf 'avatar-of-alice-v2' > $P/data/avatars/1; printf 'avatar-of-bob' > $P/data/avatars/2; \
    sqlite3 $P/data/gogs.db 'select name from "user"'; ls -la /opt/gogs-backup $P $P/data; echo "OK gogs proto + backup"

# A Symfony 8.1 skeleton (composer create-project), its secrets vault made by the seed.
RUN set -eu; COMPOSER_ALLOW_SUPERUSER=1 composer create-project --no-interaction --no-progress symfony/skeleton:8.1.* /opt/symfony-app > /tmp/symfony.log 2>&1 || { tail -20 /tmp/symfony.log; exit 1; }; \
    cd /opt/symfony-app && php bin/console --version

# Nextcloud 33.0.10 from download.nextcloud.com, installed once on SQLite with its config directory
# outside the tree (NEXTCLOUD_CONFIG_DIR); the define's state is a copy of that directory.
RUN set -eu; cd /tmp/dl && curl -fsSL -o nc.tbz https://download.nextcloud.com/server/releases/nextcloud-33.0.10.tar.bz2 && \
    tar xjf nc.tbz -C /opt && mkdir -p /opt/nc-config-proto /opt/nc-data && \
    NEXTCLOUD_CONFIG_DIR=/opt/nc-config-proto/ php /opt/nextcloud/occ maintenance:install --database sqlite \
      --admin-user admin --admin-pass 'correct-horse-9' --data-dir /opt/nc-data > /tmp/nc-install.log 2>&1 || { tail -20 /tmp/nc-install.log; exit 1; }; \
    NEXTCLOUD_CONFIG_DIR=/opt/nc-config-proto/ php /opt/nextcloud/occ status; ls -la /opt/nc-config-proto

# Docusaurus 3.10.2: the classic template, installed; the seed copies it without node_modules.
RUN set -eu; cd /opt && npx --yes create-docusaurus@3.10.2 docusite classic --javascript --package-manager npm > /tmp/docu.log 2>&1 || { tail -20 /tmp/docu.log; exit 1; }; \
    cd /opt/docusite && npx docusaurus --version

# drizzle-kit 0.31.11 with drizzle-orm 0.45.4 and better-sqlite3 13.0.3, in one project.
RUN set -eu; mkdir -p /opt/drizzle-proj && cd /opt/drizzle-proj && npm init -y > /dev/null && \
    npm install --no-audit --no-fund drizzle-kit@0.31.11 drizzle-orm@0.45.4 better-sqlite3@13.0.3 > /tmp/drizzle.log 2>&1 || { tail -20 /tmp/drizzle.log; exit 1; }; \
    npx drizzle-kit --version

RUN { echo "gogs $(gogs --version 2>&1 | head -1)"; echo "php $(php -r 'echo PHP_VERSION;')"; \
      echo "symfony $(cd /opt/symfony-app && php bin/console --version 2>&1 | head -1)"; \
      echo "nextcloud $(NEXTCLOUD_CONFIG_DIR=/opt/nc-config-proto/ php /opt/nextcloud/occ --version 2>&1 | head -1)"; \
      echo "node $(node --version)"; echo "docusaurus $(cd /opt/docusite && npx docusaurus --version 2>&1 | tail -1)"; \
      echo "drizzle-kit $(cd /opt/drizzle-proj && npx drizzle-kit --version 2>&1 | tr '\n' ' ')"; \
      for b in /opt/gogs/gogs /usr/bin/php8.4 /opt/node/bin/node; do echo "link $b: $(file -bL $b | cut -c1-100)"; done; } | tee /versions.txt
