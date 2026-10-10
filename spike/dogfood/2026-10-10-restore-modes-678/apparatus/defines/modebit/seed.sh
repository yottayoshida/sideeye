set -eu
mkdir -p /s/modebit && cd /s/modebit && rm -f log prog
printf "#!/bin/sh\necho x >> /s/modebit/log\necho y >> /s/modebit/log\n" > prog && chmod 755 prog
