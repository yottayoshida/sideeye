set -eu
rm -rf /s/useradd /s/useradd-aux && mkdir -p /s/useradd/root/etc /s/useradd-aux
R=/s/useradd/root/etc
printf 'root:x:0:0:root:/:/bin/sh\ncarol:x:1001:1001::/:/bin/sh\n' > $R/passwd
printf 'root:*:20000:0:99999:7:::\ncarol:*:20000:0:99999:7:::\n' > $R/shadow
printf 'root:x:0:\ncarol:x:1001:\nstaff:x:50:carol\n' > $R/group
printf 'root:*::\ncarol:!::\nstaff:!::carol\n' > $R/gshadow
cp /etc/login.defs $R/login.defs
chmod 640 $R/shadow $R/gshadow
install -m 755 /ap/defines/useradd/check.sh /s/useradd-aux/check.sh
