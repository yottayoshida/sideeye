#!/bin/sh
# Seeds and operations, plain runs: dokuwiki and basic-memory again, and the second build's tools.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 90 "$@" </dev/null 2>&1 | tail -${TAILN:-8}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }

echo "##### dokuwiki"
cp -a /opt/dokuwiki /lab/dw
printf '====== Start ======\nOur household wiki.\n' > /lab/page.txt
x php /lab/dw/bin/dwpage.php commit -m "first" /lab/page.txt wiki:start
printf '====== Start ======\nOur household wiki, edited.\n' > /lab/page.txt
x php /lab/dw/bin/dwpage.php commit -m "second" /lab/page.txt wiki:start
sum /lab/dw/data | grep -v -E '/cache/|/index/|_dummy|/media/|dont-panic|\.htaccess' | head -20
cat /lab/dw/data/pages/start.txt 2>/dev/null; cat /lab/dw/data/meta/start.changes 2>/dev/null | cut -c1-120

echo "##### basic-memory"
mkdir -p /lab/bm
TAILN=20 x basic-memory project list
x basic-memory project add notes /lab/bm --default
TAILN=20 x basic-memory project list
x basic-memory tool write-note --project notes --title "Plans" --folder notes --content "# Plans
- renew passport"
sum /lab/bm
x basic-memory tool edit-note --project notes plans --operation append --content "- call the bank"
sum /lab/bm; cat /lab/bm/notes/*.md 2>/dev/null | head -14; sum /s/aux/home/.basic-memory

echo "##### wrangler"
x wrangler telemetry disable
sum /s/aux/home/.config/.wrangler 2>/dev/null; sum /s/aux/home/.wrangler 2>/dev/null; find /s/aux -name 'metrics.json' 2>/dev/null

echo "##### gemini"
mkdir -p /s/aux/home/.gemini; printf '{\n  "theme": "Default",\n  "mcpServers": {\n    "docs": {"command": "docs-server"}\n  }\n}\n' > /s/aux/home/.gemini/settings.json
x gemini mcp add -s user notes /usr/bin/true --flag
sum /s/aux/home/.gemini; cat /s/aux/home/.gemini/settings.json

echo "##### oh-my-posh"
mkdir -p /lab/omp
cat > /lab/omp/theme.omp.json <<'J'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 1,
  "blocks": [
    {"type": "prompt", "alignment": "left",
     "segments": [
       {"type": "path", "style": "plain", "foreground": "#ffffff", "properties": {"prefix": "", "style": "folder"}},
       {"type": "git", "style": "plain", "foreground": "#ff0000", "properties": {"prefix": " "}}
     ]}
  ]
}
J
x oh-my-posh config migrate --config /lab/omp/theme.omp.json --write
sum /lab/omp; head -c 600 /lab/omp/theme.omp.json; echo

echo "##### opam"
mkdir -p /lab/repo/packages; printf 'opam-version: "2.0"\n' > /lab/repo/repo; export OPAMROOT=/lab/opam
x opam init --bare -n --disable-sandboxing default /lab/repo
sum /lab/opam | head
x opam option jobs=3 --global
sum /lab/opam | head; grep -n jobs /lab/opam/config
unset OPAMROOT

echo "##### stack"
export STACK_ROOT=/lab/stack; mkdir -p /lab/stack; printf '# my stack settings\ninstall-ghc: true\nsystem-ghc: false\n' > /lab/stack/config.yaml
x stack config set install-ghc false --global
sum /lab/stack; cat /lab/stack/config.yaml
unset STACK_ROOT

echo "##### juliaup"
export JULIAUP_DEPOT_PATH=/lab/jd; mkdir -p /lab/jd
x juliaup config versionsdbupdateinterval 0
x juliaup config modifypath false
sum /lab/jd; find /lab/jd -name 'juliaup.json' -exec cat {} \;
unset JULIAUP_DEPOT_PATH

echo "##### goi18n"
mkdir -p /lab/gi; cd /lab/gi
printf '[Greeting]\nother = "Hello"\n\n[Farewell]\nother = "Goodbye"\n\n[Cart]\nother = "Cart"\n' > active.en.toml
printf '[Greeting]\nhash = "sha1-f7ff9e8b7bb2e09b70935a5d785e0cc5d9d0abf0"\nother = "こんにちは"\n' > active.ja.toml
x goi18n merge active.en.toml active.ja.toml
sum /lab/gi; cat translate.ja.toml 2>/dev/null | head
printf '[Farewell]\nhash = "x"\nother = "さようなら"\n' >> translate.ja.toml 2>/dev/null
x goi18n merge active.en.toml active.ja.toml translate.ja.toml
sum /lab/gi; cat active.ja.toml
cd /

echo "##### toybox sed"
mkdir -p /lab/tb; printf 'alpha foo\nbeta foo\n' > /lab/tb/a.txt; printf 'gamma foo\n' > /lab/tb/b.txt
x toybox sed -i s/foo/bar/ /lab/tb/a.txt /lab/tb/b.txt
sum /lab/tb; cat /lab/tb/a.txt

echo "##### solvespace"
f=$(find /tmp/src/solvespace -name '*.slvs' | head -3); echo "$f"
mkdir -p /lab/ss; cp $(echo "$f" | head -1) /lab/ss/part.slvs
sum /lab/ss
x solvespace-cli regenerate /lab/ss/part.slvs
sum /lab/ss; ls -la /lab/ss

echo "##### glTF"
mkdir -p /lab/gl
python3 - <<'P'
import json, struct
pos=[]; idx=[]
n=12
for i in range(n):
    for j in range(n):
        pos += [i*0.1, j*0.1, ((i*j)%5)*0.05]
for i in range(n-1):
    for j in range(n-1):
        a=i*n+j; idx += [a, a+1, a+n, a+1, a+n+1, a+n]
pb=struct.pack('<%df'%len(pos),*pos); ib=struct.pack('<%dH'%len(idx),*idx)
while len(ib)%4: ib+=b'\0'
binb=pb+ib
xs=pos[0::3]; ys=pos[1::3]; zs=pos[2::3]
g={"asset":{"version":"2.0","generator":"seed"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0,"name":"terrain"}],
 "meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}],
 "buffers":[{"byteLength":len(binb)}],
 "bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":len(pb)},{"buffer":0,"byteOffset":len(pb),"byteLength":len(idx)*2}],
 "accessors":[{"bufferView":0,"componentType":5126,"count":n*n,"type":"VEC3","min":[min(xs),min(ys),min(zs)],"max":[max(xs),max(ys),max(zs)]},
              {"bufferView":1,"componentType":5123,"count":len(idx),"type":"SCALAR"}]}
j=json.dumps(g).encode()
while len(j)%4: j+=b' '
out=struct.pack('<III',0x46546C67,2,12+8+len(j)+8+len(binb))+struct.pack('<II',len(j),0x4E4F534A)+j+struct.pack('<II',len(binb),0x004E4942)+binb
open('/lab/gl/terrain.glb','wb').write(out); open('/lab/gl/t2.glb','wb').write(out)
P
sum /lab/gl
x gltfpack -i /lab/gl/terrain.glb -o /lab/gl/terrain.glb
x gltf-transform weld /lab/gl/t2.glb /lab/gl/t2.glb
sum /lab/gl; ls -la /lab/gl

echo "##### wandb"
mkdir -p /lab/wb; cd /lab/wb
x wandb offline
sum /lab/wb; sum /s/aux/home/.config/wandb 2>/dev/null; find /lab/wb /s/aux/home -name settings -path '*wandb*' -exec sh -c 'echo {}; cat {}' \;
cd /
