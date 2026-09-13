# #558: joplin CLI alone, the way spike/dogfood/2026-09-11-past-walls/apparatus/Dockerfile
# installs it (same base, same four build fixes), without the other targets of that run.
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps \
      nodejs npm make g++ python3-dev python3-pip libsecret-1-dev pkg-config libnode-dev
RUN pip3 install --break-system-packages \
      --trusted-host pypi.org --trusted-host files.pythonhosted.org setuptools
ENV npm_config_nodedir=/usr
RUN npm config set registry https://registry.npmjs.org/ \
 && npm config set strict-ssl false \
 && npm install -g --unsafe-perm joplin@3.7.1
RUN joplin version > /dev/null 2>&1; echo "joplin version rc=$?"; node --version
WORKDIR /w
