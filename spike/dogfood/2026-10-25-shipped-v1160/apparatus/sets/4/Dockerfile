# Set 4 of the 2026-10-25 shipped-v1160 run: personal and creative data (transcripts/scout-3.txt).
# Each tool from its own latest release as GitHub answered on 2026-10-25. Luanti publishes no Linux
# binary (an apk, Windows zips, macOS zips), so its server is built here from the 5.17.0 tag: Debian
# trixie carries 5.10.0, seven releases behind.
FROM sideeye-sv1025

RUN apt-get update > /dev/null && apt-get install -y --no-install-recommends \
      php8.4-cli php8.4-sqlite3 php8.4-intl php8.4-bcmath php8.4-mbstring php8.4-xml php8.4-zip php8.4-curl php8.4-gd composer \
      cmake ninja-build libsqlite3-dev zlib1g-dev libzstd-dev libluajit-5.1-dev libgmp-dev libjsoncpp-dev libcurl4-openssl-dev \
      libfontconfig1 libtag2 sqlite3 file > /tmp/apt-s4.log 2>&1 && echo "OK apt" || { echo "FAILED apt"; tail -5 /tmp/apt-s4.log; }

# Godot 4.7.2 (the linux arm64 editor binary; --headless needs no display).
RUN set -u; cd /tmp/dl; curl -fsSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.arm64.zip && \
    mkdir -p x-godot && unzip -q godot.zip -d x-godot && install -m 755 "$(find x-godot -type f -name 'Godot_v4.7.2-stable_linux.arm64' | head -1)" /opt/bin/godot && echo "OK godot" || echo "FAILED godot"

# Navidrome 0.64.2.
RUN set -u; cd /tmp/dl; curl -fsSL -o nd.tgz https://github.com/navidrome/navidrome/releases/download/v0.64.2/navidrome_0.64.2_linux_arm64.tar.gz && \
    mkdir -p x-nd && tar xzf nd.tgz -C x-nd && install -m 755 x-nd/navidrome /opt/bin/navidrome && echo "OK navidrome" || echo "FAILED navidrome"

# Luanti 5.17.0, server only.
RUN set -u; cd /tmp/dl; curl -fsSL -o luanti.tgz https://github.com/luanti-org/luanti/archive/refs/tags/5.17.0.tar.gz && \
    tar xzf luanti.tgz && cd luanti-5.17.0 && \
    cmake -G Ninja -B build -DBUILD_CLIENT=FALSE -DBUILD_SERVER=TRUE -DRUN_IN_PLACE=FALSE -DCMAKE_BUILD_TYPE=Release \
          -DENABLE_CURL=FALSE -DENABLE_PROMETHEUS=FALSE -DENABLE_POSTGRESQL=FALSE -DENABLE_REDIS=FALSE -DENABLE_LEVELDB=FALSE -DCMAKE_INSTALL_PREFIX=/opt/luanti > /tmp/luanti-cmake.log 2>&1 && \
    ninja -C build > /tmp/luanti-build.log 2>&1 && ninja -C build install > /tmp/luanti-install.log 2>&1 && \
    ln -sf /opt/luanti/bin/luantiserver /opt/bin/luantiserver && echo "OK luanti" || { echo "FAILED luanti"; tail -15 /tmp/luanti-cmake.log /tmp/luanti-build.log; }

# Paperless-ngx 3.3.4, from its release tarball, with the pinned requirements it ships; the two
# database drivers this run does not use (MySQL, psycopg's C build) are left out, the state is SQLite.
RUN set -u; cd /opt && curl -fsSL -o /tmp/dl/p.txz https://github.com/paperless-ngx/paperless-ngx/releases/download/v3.3.4/paperless-ngx-v3.3.4.tar.xz && \
    tar xJf /tmp/dl/p.txz && python3 -m venv /opt/paperless-venv && \
    grep -v -E '^(mysqlclient|psycopg-c)' /opt/paperless-ngx/requirements.txt > /tmp/preq.txt && \
    /opt/paperless-venv/bin/pip install --no-cache-dir -r /tmp/preq.txt > /tmp/pip-paperless.log 2>&1 && echo "OK paperless deps" || { echo "FAILED paperless deps"; tail -15 /tmp/pip-paperless.log; }
RUN apt-get install -y --no-install-recommends libmagic1 > /dev/null 2>&1 && echo "OK libmagic"

# Firefly III 6.7.9, its release tarball (vendor included).
RUN set -u; mkdir -p /opt/firefly && cd /opt/firefly && curl -fsSL -o /tmp/dl/ff.tgz https://github.com/firefly-iii/firefly-iii/releases/download/v6.7.9/FireflyIII-v6.7.9.tar.gz && \
    tar xzf /tmp/dl/ff.tgz && ls vendor/autoload.php && echo "OK firefly" || echo "FAILED firefly"

# Firefly III 6.7.9 requires PHP 8.5 (vendor/composer/platform_check.php refuses 8.4.27, Debian
# trixie's); PHP 8.5 from packages.sury.org, the repository PHP's Debian maintainer publishes.
RUN set -u; curl -fsSL -o /usr/share/keyrings/sury-php.gpg https://packages.sury.org/php/apt.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ trixie main" > /etc/apt/sources.list.d/sury-php.list && \
    apt-get update > /dev/null && apt-get install -y --no-install-recommends php8.5-cli php8.5-sqlite3 php8.5-intl php8.5-bcmath \
      php8.5-mbstring php8.5-xml php8.5-zip php8.5-curl php8.5-gd > /tmp/apt-php85.log 2>&1 && echo "OK php8.5" || { echo "FAILED php8.5"; tail -5 /tmp/apt-php85.log; }

# Luanti's devtest game, from the same 5.17.0 source tree: a world needs a game to open.
RUN mkdir -p /opt/luanti/share/luanti/games && cp -a /tmp/dl/luanti-5.17.0/games/devtest /opt/luanti/share/luanti/games/ && echo "OK devtest"

RUN { echo "paperless-ngx $(cd /opt/paperless-ngx/src && /opt/paperless-venv/bin/python -c 'import paperless.version as v; print(".".join(map(str, v.__version__)))' 2>&1 | tail -1) (python $(/opt/paperless-venv/bin/python -V 2>&1 | cut -d' ' -f2))"; \
      echo "godot $(godot --version 2>&1 | tail -1)"; echo "luantiserver $(luantiserver --version 2>&1 | head -1)"; \
      echo "navidrome $(navidrome --version 2>&1 | tail -1)"; \
      echo "firefly-iii $(grep -m1 "'version'" /opt/firefly/config/firefly.php | tr -d " ,'") (php $(php8.5 -r 'echo PHP_VERSION;'))"; \
      for b in /opt/paperless-venv/bin/python /opt/bin/godot /opt/bin/luantiserver /opt/bin/navidrome /usr/bin/php8.5; do echo "link $b: $(file -bL $b | cut -c1-90)"; done; } | tee /versions.txt
