# Set 3's replacement for JuiceFS (walled, SELECTION.md): Dokku 0.38.32, the reserve scout 4 ranked
# first. Dokku publishes no release assets on GitHub; its .deb is on packagecloud, whose trixie
# distribution carries the latest release. Installed with no service started (a policy-rc.d that
# refuses), since the box has no docker daemon and the commands measured do not deploy.
FROM sideeye-sv1025-s3
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d && \
    apt-get install -y --no-install-recommends gnupg debconf-utils > /tmp/apt-gpg.log 2>&1 && \
    curl -fsSL https://packagecloud.io/dokku/dokku/gpgkey | gpg --dearmor -o /usr/share/keyrings/dokku.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/dokku.gpg] https://packagecloud.io/dokku/dokku/debian/ trixie main" > /etc/apt/sources.list.d/dokku.list && \
    apt-get update > /tmp/apt-upd.log 2>&1 && echo "OK dokku repo"
RUN printf 'dokku dokku/vhost_enable boolean true\ndokku dokku/hostname string dokku.home.example\ndokku dokku/skip_key_file boolean true\ndokku dokku/key_file string /dev/null\ndokku dokku/nginx_enable boolean true\n' | debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y dokku=0.38.32 > /tmp/apt-dokku.log 2>&1 && echo "OK dokku" || { echo "FAILED dokku"; tail -25 /tmp/apt-dokku.log; }
RUN dokku version 2>&1 | tail -2; ls /var/lib/dokku/core-plugins/available | head -50 | tr '\n' ' '; echo; \
    echo "dokku $(dokku version 2>&1 | tail -1)" >> /versions.txt; echo "link /usr/bin/dokku: $(file -bL /usr/bin/dokku | cut -c1-60)" >> /versions.txt; tail -2 /versions.txt
