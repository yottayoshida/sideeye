set -eu
rm -rf /s/pint && mkdir -p /s/pint/proj && cd /s/pint/proj
printf '<?php\nfunction f( $x ){\nreturn $x+1;\n}\n' > a.php
