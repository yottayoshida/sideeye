set -eu
rm -rf /s/php-cs-fixer && mkdir -p /s/php-cs-fixer/proj && cd /s/php-cs-fixer/proj
printf '<?php\nfunction f( $x ){\nreturn $x+1;\n}\n' > a.php
