#!/bin/sh
# #559's second half, measured on ansible. The shipped engine and `sideeye-testnocgroup` — the
# same tree built never to contain a run — explore the define the 2026-09-11 run was refused on,
# under both observation modes. Run once in a `--privileged` container as root, where the engine
# can make cgroups, and once in a default one, where it cannot.
#
# Mounts: a repo copy with the aarch64 Linux build at /work, this directory at /ap, output at /out.
set -u
label=${LABEL:?LABEL names the container this ran in}
echo "label=$label uid=$(id -u) cgroupfs=$(awk '$2 == "/sys/fs/cgroup" { split($4, o, ","); print o[1] }' /proc/mounts) self=$(cat /proc/self/cgroup)"
ansible --version | head -1
strace -V | head -1
for engine in sideeye sideeye-testnocgroup; do
    SE=/work/zig-out/bin/$engine
    echo "== $engine: $("$SE" version 2>&1 | head -1)"
    for mode in wrappers syscalls; do
        SD=/localrun/st/$engine-$mode; export SD
        rm -rf "$SD" "/localrun/wk/$engine-$mode"; mkdir -p /localrun/wk /localrun/st
        op="ansible localhost -c local -i localhost, -e ansible_python_interpreter=/usr/bin/python3 -m lineinfile -a {\"path\":\"$SD/f.txt\",\"line\":\"gamma\"}"
        t0=$(date +%s)
        timeout 1200 "$SE" explore --state "$SD" --setup /ap/setup-ansible.sh --operation "$op" \
            --shim /work/zig-out/lib/libsideeye_shim.so --oracle /usr/bin/strace --observe "$mode" \
            --work "/localrun/wk/$engine-$mode" --json "/out/$label.$engine.$mode.json" \
            > "/out/$label.$engine.$mode.txt" 2>&1
        rc=$?
        echo "$engine $mode: rc=$rc in $(( $(date +%s) - t0 ))s — $(head -1 "/out/$label.$engine.$mode.txt")"
        echo "    f.txt after: $(tr '\n' '|' < "$SD/f.txt" 2>/dev/null)"
        # What the recording run's shims wrote, one `<op> <path>` line per record (no pid).
        wk=/localrun/wk/$engine-$mode
        if [ -f "$wk/trace-record.bin" ] && [ -x /work/zig-out/bin/trace-ops ]; then
            /work/zig-out/bin/trace-ops "$wk/trace-record.bin" > "/out/$label.$engine.$mode.trace-record.txt" 2>&1
            echo "    recording trace records: $(awk '{ print $1 }' "/out/$label.$engine.$mode.trace-record.txt" | sort | uniq -c | awk '{ printf "%s=%s ", $2, $1 }')"
        fi
    done
done
echo "leftover sideeye cgroups: $(ls -d /sys/fs/cgroup/sideeye-* 2>/dev/null | wc -l)"
