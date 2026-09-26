# The box for the 2026-09-26 threads-gate run: the 2026-09-22 shipped-v160 box, unchanged,
# plus Debian's python3-virtualenv — the package the 2026-09-16 threads-take-turns run
# measured (`Dockerfile.probe-venv`), not the PyPI one.
#
# FROM the existing image rather than a rebuild of its Dockerfile: a rebuild re-fetches
# Sideeye and every candidate over the network, and nothing guarantees the same bytes. The
# base is `sideeye-sv` as `spike/dogfood/2026-09-22-shipped-v160/apparatus/build.sh` built it
# (image sha256:5cbbc4c9…, created 2026-09-22T03:46:59Z; v1.6.0, installer digest
# 86622c84…); `run.sh` prints both again from inside the box.
FROM sideeye-sv
RUN apt-get update && apt-get install -y --no-install-recommends python3-virtualenv > /tmp/apt-venv.log 2>&1 \
    && /usr/bin/virtualenv --version
