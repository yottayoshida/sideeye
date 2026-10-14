set -eu
rm -rf /s/ua /s/ua-aux && mkdir -p /s/ua/alt /s/ua/admin /s/ua/bin /s/ua/opt /s/ua-aux
for e in ed1 ed2; do printf '#!/bin/sh\necho %s\n' $e > /s/ua/opt/$e; chmod 755 /s/ua/opt/$e; done
update-alternatives --altdir /s/ua/alt --admindir /s/ua/admin --log /s/ua/log --install /s/ua/bin/editor editor /s/ua/opt/ed1 40 > /dev/null
install -m 755 /ap/defines/alternatives/check.sh /s/ua-aux/check.sh
