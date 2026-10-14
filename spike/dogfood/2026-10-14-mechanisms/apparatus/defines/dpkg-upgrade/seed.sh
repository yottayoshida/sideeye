set -eu
S=/s/dk; X=/s/dk-aux
rm -rf $S $X && mkdir -p $S/admin/info $S/admin/updates $S/admin/triggers $S/root $X/b
: > $S/admin/status; : > $S/admin/available
for v in 1.0 2.0; do
    P=$X/b/demo-$v
    mkdir -p $P/DEBIAN $P/usr/share/demo $P/usr/bin
    printf 'Package: demo\nVersion: %s\nArchitecture: all\nMaintainer: x <x@example.invalid>\nDescription: demo\n' $v > $P/DEBIAN/control
    for i in 1 2 3; do printf 'demo data %s part %s\n' $v $i > $P/usr/share/demo/data$i.txt; done
    printf '#!/bin/sh\necho demo %s\n' $v > $P/usr/bin/demo; chmod 755 $P/usr/bin/demo
    SOURCE_DATE_EPOCH=1767225600 dpkg-deb --root-owner-group --build $P $X/demo_$v.deb > /dev/null
done
dpkg --admindir=$S/admin --instdir=$S/root --log=$S/dpkg.log --force-not-root --force-script-chrootless -i $X/demo_1.0.deb > $X/install-1.0.log 2>&1
install -m 755 /ap/defines/dpkg-upgrade/check.sh $X/check.sh
