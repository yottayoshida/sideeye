# The image the hardened leg runs (spike/platforms/runner.sh): Rocky Linux 8.10 with strace,
# built before the run because the container it is started as has no network.
FROM rockylinux/rockylinux:8.10@sha256:e8a49c5403b687db05d4d67333fa45808fbe74f36e683cec7abb1f7d0f2338c6
RUN dnf -q -y install strace && dnf clean all
