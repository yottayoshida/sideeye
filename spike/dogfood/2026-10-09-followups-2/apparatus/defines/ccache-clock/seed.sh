set -eu
rm -rf /s/ccache && mkdir -p /s/ccache/state /s/ccache/aux/src
mkdir -p "/s/ccache/state" /s/ccache/aux/src
printf 'int main(void){return 0;}\n' > /s/ccache/aux/src/a.c
printf 'int f(void){return 1;}\n' > /s/ccache/aux/src/b.c
CCACHE_DIR="/s/ccache/state" ccache gcc -c /s/ccache/aux/src/a.c -o /s/ccache/aux/src/a.o >/dev/null 2>&1
cp /s/ccache/aux/src/a.o /s/ccache/aux/src/a.o.golden
