set -eu
rm -rf /s/phpcbf && mkdir -p /s/phpcbf/proj && cd /s/phpcbf/proj
printf '<?php\nfunction f( $x ){\nreturn $x+1;\n}\n' > a.php
