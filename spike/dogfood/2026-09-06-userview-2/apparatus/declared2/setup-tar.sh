#!/bin/sh
mkdir -p /work/st2/ar /tmp/tsrc
printf 'one\n'   > /tmp/tsrc/f1.txt
printf 'two\n'   > /tmp/tsrc/f2.txt
printf 'three\n' > /tmp/tsrc/f3.txt
bsdtar -cf /work/st2/ar/a.tar -C /tmp/tsrc f1.txt f2.txt
