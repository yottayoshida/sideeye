#!/bin/sh
# spike/platforms/wsl2-inner.sh — the WSL legs of the platform probe (#697, ADR 0105), run as root
# inside the Ubuntu 24.04 distribution that .github/workflows/spike-platforms.yml imports on a
# Windows runner. The checkout is reached through /mnt (the Windows drive); the engine goes on the
# distribution's own filesystem. SIDEEYE_VERSION, LEGS, LABEL and GH_TOKEN arrive through WSLENV.
#
#   SIDEEYE_VERSION=v1.10.0 LEGS=base|extra|systemd [LABEL=<name>] sh spike/platforms/wsl2-inner.sh <out dir>
#
#   base     root, the state in /s on the distribution's filesystem; labelled LABEL (default wsl2,
#            the 2026-10-10 record's leg). On WSL1, when the engine refuses the shim it found as
#            unclassifiable, LABEL-shim follows that refusal's next step once and names it with --shim
#   extra    (RUNS-RULE-2026-10-10b.md: x86_64 WSL2's base leg is not measured again)
#            wsl2-mnt   root, the state under /mnt/c — the Windows drive, through WSL's 9P mount
#            wsl2-user  an ordinary user `probe`, its own install of the engine, the state in its home
#   systemd  after the workflow has turned systemd on and restarted the distribution:
#            wsl2-systemd-root   root, /s
#            wsl2-systemd-user   `probe`, inside a cgroup delegated to it (spike/in-delegated-cgroup.sh)
set -u

out=${1:?usage: SIDEEYE_VERSION=<tag> LEGS=base|extra|systemd wsl2-inner.sh <out dir>}
V=${SIDEEYE_VERSION:?set SIDEEYE_VERSION to the release tag to measure}
LEGS=${LEGS:-base}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
installer=$root/docs/ci-quickstart/release/install-sideeye.sh

{ uname -r; cat /proc/version; } > "$out/wsl-kernel-$LEGS.txt"
export DEBIAN_FRONTEND=noninteractive
# The systemd legs run in a second session of the same distribution: install once.
if [ ! -s /opt/sideeye-bin ]; then
    { apt-get update -qq && apt-get install -y -qq strace python3 curl ca-certificates sudo util-linux; } > "$out/wsl-apt.txt" 2>&1 || {
        echo "wsl: packages could not be installed"; tail -5 "$out/wsl-apt.txt"; exit 1
    }
    sh "$installer" "$V" /opt/sideeye > /opt/sideeye-bin 2> "$out/wsl-install.txt" || {
        echo "wsl: the engine could not be installed"; cat "$out/wsl-install.txt"; exit 1
    }
fi
bin=$(cat /opt/sideeye-bin)

# The user leg's engine is its own install: the shim search declines a shim someone else owns.
user_install() {
    id probe > /dev/null 2>&1 || useradd -m probe
    # The token reaches the user's shell through its environment (su -w), not its command line.
    su -w GH_TOKEN probe -c "sh '$installer' '$V' /home/probe/sideeye" > /home/probe-bin 2>> "$out/wsl-install-user.txt"
    cat /home/probe-bin
}
# A user leg writes in /tmp and root copies it into the record: the Windows drive's permissions
# are not the user's to rely on.
user_leg() { # <label> <measure prefix…>
    label=$1; shift
    ubin=$(user_install)
    rm -rf "/tmp/$label-out" && su probe -c "mkdir -p /tmp/$label-out && S=/home/probe/s $* sh '$here/measure.sh' '$ubin' /tmp/$label-out $label"
    cp -r "/tmp/$label-out/$label" "$out/"
}
# A leg's result is its summary with a verdict for every mode; one without is an apparatus fault.
complete() { for l in "$@"; do [ "$(grep -cE "$(printf '\t')(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$out/$l/summary.txt" 2>/dev/null)" = 3 ] || { echo "wsl: no complete record from $l"; return 1; }; done; }

case $LEGS in
base)
    mkdir -p /s
    sh "$here/measure.sh" "$bin" "$out" "${LABEL:-wsl2}"
    complete "${LABEL:-wsl2}"; rc=$?
    # The refusal's own next step, followed once, on WSL1 only: an engine that cannot classify the
    # shim it found (WSL1, run 38031881569) says to name it with --shim (RUNS-RULE-2026-10-10b.md, a
    # leg added after the first dispatch).
    if [ "${LABEL:-}" = wsl1 ] && grep -q 'the shim the search found could not be classified' "$out/wsl1/summary.txt"; then
        SHIM=$(dirname "$bin")/libsideeye_shim.so sh "$here/measure.sh" "$bin" "$out" wsl1-shim
        complete wsl1-shim || rc=1
    fi
    exit $rc ;;
extra)
    mkdir -p /mnt/c/probe-s
    S=/mnt/c/probe-s sh "$here/measure.sh" "$bin" "$out" wsl2-mnt
    user_leg wsl2-user
    complete wsl2-mnt wsl2-user ;;
systemd)
    { echo "PID 1: $(ps -p 1 -o comm=)"; systemctl is-system-running 2>&1; } > "$out/wsl-systemd.txt"
    mkdir -p /s
    sh "$here/measure.sh" "$bin" "$out" wsl2-systemd-root
    echo "probe ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/probe && chmod 440 /etc/sudoers.d/probe
    user_leg wsl2-systemd-user "sh '$root/spike/in-delegated-cgroup.sh'"
    complete wsl2-systemd-root wsl2-systemd-user ;;
*) echo "wsl: unknown LEGS $LEGS"; exit 2 ;;
esac
