set -eu
rm -rf /s/php-cs-fixer-r1 && mkdir -p /s/php-cs-fixer-r1/proj && cd /s/php-cs-fixer-r1/proj
printf '<?php\nfunction f( $x ){\nreturn $x+1;\n}\n' > a.php
