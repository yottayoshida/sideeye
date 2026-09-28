set -eu
rm -rf /s/standardrb && mkdir -p /s/standardrb/proj && cd /s/standardrb/proj
printf 'def f( x )\n  return x+1\nend\nputs f( 2 )\n' > a.rb
