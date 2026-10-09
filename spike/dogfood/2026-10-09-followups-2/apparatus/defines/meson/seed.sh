set -eu
rm -rf /s/meson && mkdir -p /s/meson/state /s/meson/aux/ms/src
printf "project('probe', 'c')\nexecutable('p', 'p.c')\n" > "/s/meson/aux/ms/src/meson.build"
printf 'int main(void){return 0;}\n' > "/s/meson/aux/ms/src/p.c"
mkdir -p "/s/meson/state"
python3 -c "
import shutil,sys,os,glob
for p in glob.glob(os.path.join(sys.argv[1],'*'))+glob.glob(os.path.join(sys.argv[1],'.*')):
    if os.path.basename(p) in ('.','..'): continue
    shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
" "/s/meson/state"
CC=gcc meson setup "/s/meson/state" /s/meson/aux/ms/src >/dev/null 2>&1
