# The box for 2026-10-10 uv-threadpool (#686): the released Sideeye v1.10.0 beside the thirteen Node
# targets #686 lists, at the versions 2026-10-09 follow-ups 3 measured with one libuv thread. Copied
# from follow-ups 3's Dockerfile, keeping only what those thirteen need.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps bash git curl xz-utils

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

RUN for p in nodejs npm libfaketime faketime; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p /opt/bin /tmp/dl

COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.10.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

RUN for p in bibtex-tidy@1.15.1 @dotenvx/dotenvx@2.32.4 @google/gemini-cli@0.62.0 @gltf-transform/cli@4.5.1 vercel@62.2.0 \
      eslint@10.11.0 prettier@3.9.7 stylelint@17.15.0 svgo@4.1.0 joplin@3.7.1 @bitwarden/cli@2026.8.0; do \
      npm install -g --no-fund --no-audit "$p" > /tmp/npm-$(echo $p | tr /@ __).log 2>&1 && echo "OK $p" || { echo "FAILED $p"; tail -2 /tmp/npm-$(echo $p | tr /@ __).log; }; \
    done
RUN mkdir -p /opt/lingui-proj && cd /opt/lingui-proj && printf '{"name":"seed","private":true,"type":"module"}\n' > package.json \
    && npm install --no-fund --no-audit @lingui/cli@6.9.0 @lingui/core@6.9.0 @lingui/babel-plugin-lingui-macro@6.9.0 > /tmp/npm-lingui.log 2>&1; echo "npm lingui exit: $?"
RUN set -u; cd /tmp/dl; curl -fsSL -o node22.txz https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-arm64.tar.xz && \
    echo "a44aeb94849a299b22df10b9e622ec2f605c2183501bc40590705131de7c740f  node22.txz" | sha256sum -c && \
    mkdir -p /opt/node22 && tar xJf node22.txz -C /opt/node22 --strip-components=1 && /opt/node22/bin/node --version
RUN { echo "node $(node --version)"; for c in "bibtex-tidy --version" "dotenvx --version" "gemini --version" "gltf-transform --version" "vercel --version" "eslint --version" "prettier --version" "stylelint --version" "svgo --version" "joplin version" "bw --version" "npm --version"; do printf '%s: ' "$c"; sh -c "$c" < /dev/null 2>&1 | head -1; done; echo "node22 $(/opt/node22/bin/node --version)"; echo "lingui $(cd /opt/lingui-proj && npm ls @lingui/cli 2>/dev/null | grep lingui/cli)"; } | tee /versions.txt
