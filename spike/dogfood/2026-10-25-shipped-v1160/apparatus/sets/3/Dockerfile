# Set 3 of the 2026-10-25 shipped-v1160 run: system and ops tools (transcripts/scout-4.txt).
# Each tool from its own latest release for linux/arm64 as GitHub answered on 2026-10-25, unless a
# layer says otherwise.
FROM sideeye-sv1025

# Salt 3008.4: its onedir for linux/arm64 (the release asset; a relocatable Python with Salt in it).
RUN set -u; cd /tmp/dl; \
    curl -fsSL -o salt.txz https://github.com/saltstack/salt/releases/download/v3008.4/salt-3008.4-onedir-linux-arm64.tar.xz && echo "OK salt.txz"; \
    mkdir -p /opt/salt && tar xJf salt.txz -C /opt/salt && ls /opt/salt && \
    ln -sf "$(find /opt/salt -maxdepth 2 -name salt-call | head -1)" /opt/bin/salt-call && echo "OK salt-call"

# JuiceFS 1.4.2, the release asset.
RUN set -u; cd /tmp/dl; \
    curl -fsSL -o jfs.tgz https://github.com/juicedata/juicefs/releases/download/v1.4.2/juicefs-1.4.2-linux-arm64.tar.gz && \
    mkdir -p x-jfs && tar xzf jfs.tgz -C x-jfs && install -m 755 "$(find x-jfs -type f -name juicefs | head -1)" /opt/bin/juicefs && echo "OK juicefs"

# systemd-sysusers: Debian trixie's systemd (upstream is 262.1; trixie carries 257). pwck/grpck from
# Debian's passwd, the checker.
RUN apt-get install -y --no-install-recommends systemd passwd > /tmp/apt-systemd.log 2>&1 && echo "OK systemd" || { echo "FAILED systemd"; tail -5 /tmp/apt-systemd.log; }

# FreshRSS 1.30.4 from its tag (it publishes no assets), on Debian trixie's PHP.
RUN apt-get install -y --no-install-recommends php8.4-cli php8.4-sqlite3 php8.4-mbstring php8.4-xml php8.4-curl php8.4-intl php8.4-zip > /tmp/apt-php.log 2>&1 && echo "OK php" || { echo "FAILED php"; tail -5 /tmp/apt-php.log; }
RUN set -u; cd /tmp/dl; \
    curl -fsSL -o freshrss.tgz https://github.com/FreshRSS/FreshRSS/archive/refs/tags/1.30.4.tar.gz && \
    mkdir -p /opt/freshrss && tar xzf freshrss.tgz -C /opt/freshrss --strip-components=1 && echo "OK freshrss"

# Vagrant: upstream publishes no linux/arm64 build (2.4.9's assets are linux_amd64 only), so the gem is
# built from the v2.4.9 tag on trixie's Ruby; Debian's 2.3.7 is installed beside it as the fallback.
RUN apt-get install -y --no-install-recommends ruby ruby-dev libxml2-dev libxslt1-dev zlib1g-dev libffi-dev libssl-dev > /tmp/apt-ruby.log 2>&1 && echo "OK ruby" || { echo "FAILED ruby"; tail -5 /tmp/apt-ruby.log; }
RUN set -u; cd /tmp/dl; \
    git clone -q --depth 1 --branch v2.4.9 https://github.com/hashicorp/vagrant.git vagrant-src && cd vagrant-src && \
    gem build vagrant.gemspec > /tmp/gem-build.log 2>&1 && \
    gem install --no-document --install-dir /opt/vagrant-gems ./vagrant-2.4.9.gem > /tmp/gem-install.log 2>&1 && echo "OK vagrant 2.4.9 gem" || { echo "FAILED vagrant gem"; tail -15 /tmp/gem-build.log /tmp/gem-install.log; }
RUN printf '#!/bin/sh\nexport GEM_HOME=/opt/vagrant-gems GEM_PATH=/opt/vagrant-gems VAGRANT_CHECKPOINT_DISABLE=1 VAGRANT_DISABLE_VBOXSYMLINKCREATE=1\nexec ruby /opt/vagrant-gems/bin/vagrant "$@"\n' > /opt/bin/vagrant-upstream && chmod 755 /opt/bin/vagrant-upstream; \
    VAGRANT_HOME=/tmp/vh /opt/bin/vagrant-upstream --version 2>&1 | tail -3

RUN { echo "salt-call $(salt-call --version 2>&1 | head -1)"; echo "juicefs $(juicefs --version 2>&1 | head -1)"; \
      echo "systemd-sysusers $(systemd-sysusers --version 2>&1 | head -1)"; echo "php $(php --version 2>&1 | head -1)"; \
      echo "freshrss $(grep -o "FRESHRSS_VERSION', '[^']*" /opt/freshrss/constants.php)"; \
      echo "vagrant-upstream $(VAGRANT_HOME=/tmp/vh vagrant-upstream --version 2>&1 | tail -1)"; \
      for b in "$(readlink -f /opt/bin/salt-call)" /opt/bin/juicefs /usr/bin/systemd-sysusers /usr/bin/php8.4 /usr/bin/ruby3.3; do echo "link $b: $(file -bL $b | cut -c1-90)"; done; } | tee /versions.txt
