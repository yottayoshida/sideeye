#!/bin/sh
# CANDIDATES.md 2.2. The recovery a user runs is `dpkg --configure -a`, then the same `dpkg -i` when
# the package is left half-installed.
set -u
S=${SIDEEYE_STATE_DIR:?}
D="dpkg --admindir=$S/admin --instdir=$S/root --log=$S/dpkg.log --force-not-root --force-script-chrootless"
status() { dpkg-query --admindir="$S/admin" -W -f '${Status} ${Version}' demo 2>/dev/null; }
legs() {
    a=ok; b=ok
    out=$($D --audit 2>&1); [ $? = 0 ] && [ -z "$out" ] || a="FAIL(audit: $(echo "$out" | head -1))"
    st=$(status)
    case "$st" in
        "install ok installed 1.0"|"install ok installed 2.0")
            v=${st##* }
            [ -z "$($D --verify demo 2>&1)" ] || b="FAIL(verify)"
            for i in 1 2 3; do [ "$(cat "$S/root/usr/share/demo/data$i.txt" 2>/dev/null)" = "demo data $v part $i" ] || b="FAIL(data$i is not $v's)"; done ;;
        *) b="FAIL(status: $st)" ;;
    esac
    echo "a=$a b=$b"
}
echo "checker(dpkg-upgrade) before recovery: $(legs) [$(status)]"
timeout 120 $D --configure -a > /tmp/dk-recovery.txt 2>&1 || echo "checker(dpkg-upgrade) --configure -a exited $?: $(tail -c 200 /tmp/dk-recovery.txt)"
case "$(status)" in *half-installed*|*not-installed*|*unpacked*)
    timeout 120 $D -i /s/dk-aux/demo_2.0.deb >> /tmp/dk-recovery.txt 2>&1 || echo "checker(dpkg-upgrade) dpkg -i again exited $?: $(tail -c 200 /tmp/dk-recovery.txt)" ;;
esac
after=$(legs); echo "checker(dpkg-upgrade) after recovery: $after [$(status)]"
case "$after" in "a=ok b=ok") exit 0 ;; *) exit 1 ;; esac
