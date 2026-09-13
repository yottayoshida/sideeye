#!/bin/sh
# spike/in-delegated-cgroup.sh — run a command as this user inside a cgroup v2 delegated to it,
# so an engine started under it contains its runs (contract v17, #559).
#
# The engine contains a run only where it can move a process within its own cgroup and make a
# child cgroup that carries `cgroup.kill` (`posix.cgroupHome`). A CI runner's shell sits in a
# cgroup root owns, so there the engine contains nothing, and an acceptance suite run from it
# measures every leg uncontained and is green all the same. This wraps the command in a
# transient systemd scope with `Delegate=yes`, gives the scope's cgroup to the invoking user,
# drops back to that user, and then asks the engine's probe by hand — as that user, in that
# cgroup — before anything runs. A scope that was not delegated fails here, by name, rather
# than producing an uncontained suite that reads like a contained one.
#
# Three stages in one file, so they cannot drift apart:
#   in-delegated-cgroup.sh <cmd> [args...]               the user: re-enter under sudo and a scope
#   in-delegated-cgroup.sh --scoped <uid> <gid> <cmd>... root, in the scope: hand it over, drop
#   in-delegated-cgroup.sh --dropped <cmd>...            the user, in the scope: probe, then exec
#
# Needs systemd as PID 1, passwordless sudo that honours -E, and setpriv (util-linux): what
# GitHub's ubuntu runners have. All three stages ran on the runner on #559's pull request — the
# suite as uid 1001 in a delegated `system.slice/run-*.scope` — and the last two were also run by
# hand in a privileged container, root handing over to an unprivileged user. Acceptance check 2cg
# is what goes red if the suite this wraps contains nothing.
set -eu

self=$0
stage=${1:-}

# The cgroup this process is in, as a path under the cgroup2 mount.
cgroup_dir() {
    rel=$(sed -n 's/^0:://p' /proc/self/cgroup)
    if [ -z "$rel" ]; then
        echo "in-delegated-cgroup: /proc/self/cgroup has no cgroup v2 line" >&2
        exit 1
    fi
    printf '/sys/fs/cgroup%s\n' "$rel"
}

case "$stage" in
--scoped)
    shift
    uid=$1
    gid=$2
    shift 2
    cg=$(cgroup_dir)
    # `Delegate=yes` lets the scope be subdivided; owning the directory and these three files
    # is what lets an unprivileged process do it (the kernel's "Delegation Containment": a move
    # needs write access to the common ancestor's cgroup.procs, which is this one).
    chown "$uid:$gid" "$cg" "$cg/cgroup.procs" "$cg/cgroup.threads" "$cg/cgroup.subtree_control"
    exec setpriv --reuid="$uid" --regid="$gid" --init-groups sh "$self" --dropped "$@"
    ;;
--dropped)
    shift
    cg=$(cgroup_dir)
    # The engine's probe, asked by hand: move this process within its own cgroup, and make a
    # child cgroup that carries cgroup.kill.
    echo $$ >"$cg/cgroup.procs"
    probe="$cg/in-delegated-cgroup-probe-$$"
    mkdir "$probe"
    if [ ! -e "$probe/cgroup.kill" ]; then
        rmdir "$probe"
        echo "in-delegated-cgroup: a child of $cg has no cgroup.kill (a kernel before 5.14)" >&2
        exit 1
    fi
    rmdir "$probe"
    echo "in-delegated-cgroup: running as $(id -u):$(id -g) in $cg, delegated"
    exec "$@"
    ;;
*)
    if [ $# -eq 0 ]; then
        echo "usage: in-delegated-cgroup.sh <command> [args...]" >&2
        exit 2
    fi
    # sudo resets PATH through secure_path and may reset HOME; the command is the invoking
    # user's and needs both, and -E keeps the rest (SIDEEYE_ROOT among them).
    exec sudo -E env "PATH=$PATH" "HOME=$HOME" \
        systemd-run --scope --quiet -p Delegate=yes -- sh "$self" --scoped "$(id -u)" "$(id -g)" "$@"
    ;;
esac
