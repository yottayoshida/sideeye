# Set 3's fifth after JuiceFS (walled) and Dokku (not installable in this box): wallabag 2.6.14, its
# latest release (2025-10-07; the repository was pushed 2026-10-23), the release tarball with its
# vendor tree, on trixie's PHP 8.4 and SQLite.
FROM sideeye-sv1025-s3
RUN apt-get install -y --no-install-recommends php8.4-gd php8.4-bcmath php8.4-tidy php8.4-zip php8.4-intl php8.4-xml php8.4-mbstring php8.4-curl php8.4-sqlite3 > /tmp/apt-wb.log 2>&1 && echo "OK php ext"
RUN set -u; cd /tmp/dl && curl -fsSL -o wb.tgz https://github.com/wallabag/wallabag/releases/download/2.6.14/wallabag-2.6.14.tar.gz && \
    mkdir -p /opt/wallabag && tar xzf wb.tgz -C /opt/wallabag --strip-components=1 && ls /opt/wallabag | tr '\n' ' ' && echo && \
    sed -n '1,40p' /opt/wallabag/app/config/parameters.yml 2>/dev/null | grep -E "database_driver|database_path|secret" || true
RUN cd /opt/wallabag && \
    sed -i -e 's/database_driver: .*/database_driver: pdo_sqlite/' -e 's#database_path: .*#database_path: "%kernel.project_dir%/data/db/wallabag.sqlite"#' app/config/parameters.yml && \
    php bin/console wallabag:install --env=prod -n > /tmp/wb-install.log 2>&1 && echo "OK wallabag install" || { echo "FAILED wallabag install"; tail -20 /tmp/wb-install.log; }; \
    ls -la /opt/wallabag/data/db; php bin/console list wallabag --env=prod 2>&1 | grep -E "^ +wallabag:" | head -30
RUN { echo "wallabag $(cd /opt/wallabag && php bin/console --version --env=prod 2>&1 | tail -1)"; } | tee -a /versions.txt
