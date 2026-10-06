# The four targets #684 names, and nothing else (2026-10-06).
#
# vim, fish, dotdrop and firewalld were refused `unsupported_syscall_observed` on a call that
# changes nothing — getxattr, inotify_add_watch, listxattr, listxattr — in three earlier
# campaigns, each in an image built for dozens of other tools (2026-10-02-unjudged-on-v170,
# 2026-10-03-user-data, 2026-10-05-user-data-2). Re-measuring four targets does not need
# those images, and rebuilding them would move the other tools' versions too. This one has
# the same base as all three (debian:trixie-slim) and the four packages; `/versions.txt`
# is compared against the versions those campaigns recorded (RESULTS.md says how).
#
# No engine is installed: the engine under test is mounted at /eng by host.sh, the build of
# the commit RESULTS.md names, and its digest is recorded beside every run.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv ca-certificates procps vim fish firewalld

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
RUN python3 -m venv /opt/py && /opt/py/bin/pip install --no-cache-dir dotdrop==1.17.0 > /tmp/pip.log 2>&1; \
    echo "pip dotdrop exit: $?"; ln -sf /opt/py/bin/dotdrop /usr/local/bin/dotdrop

RUN { dpkg-query -W vim fish firewalld; \
      printf 'vim => %s\n' "$(vim --version | head -1)"; \
      printf 'fish => %s\n' "$(fish --version)"; \
      printf 'firewall-offline-cmd => %s\n' "$(firewall-offline-cmd --version 2>&1 | head -1)"; \
      printf 'dotdrop => %s\n' "$(dotdrop --version 2>&1 | head -1)"; } > /versions.txt; cat /versions.txt
