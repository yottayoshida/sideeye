set -eu
rm -rf /s/glt /s/glt-in && mkdir -p /s/glt /s/glt-in
set -- /s/glt/terrain.glb
python3 - "$1" <<'P'
import json, struct, sys
pos=[]; idx=[]; n=12
for i in range(n):
    for j in range(n):
        pos += [i*0.1, j*0.1, ((i*j)%5)*0.05]
for i in range(n-1):
    for j in range(n-1):
        a=i*n+j; idx += [a, a+1, a+n, a+1, a+n+1, a+n]
pb=struct.pack('<%df'%len(pos),*pos); ib=struct.pack('<%dH'%len(idx),*idx)
while len(ib)%4: ib+=b'\0'
binb=pb+ib; xs=pos[0::3]; ys=pos[1::3]; zs=pos[2::3]
g={"asset":{"version":"2.0","generator":"seed"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0,"name":"terrain"}],
 "meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}],"buffers":[{"byteLength":len(binb)}],
 "bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":len(pb)},{"buffer":0,"byteOffset":len(pb),"byteLength":len(idx)*2}],
 "accessors":[{"bufferView":0,"componentType":5126,"count":n*n,"type":"VEC3","min":[min(xs),min(ys),min(zs)],"max":[max(xs),max(ys),max(zs)]},
              {"bufferView":1,"componentType":5123,"count":len(idx),"type":"SCALAR"}]}
j=json.dumps(g).encode()
while len(j)%4: j+=b' '
out=struct.pack('<III',0x46546C67,2,12+8+len(j)+8+len(binb))+struct.pack('<II',len(j),0x4E4F534A)+j+struct.pack('<II',len(binb),0x004E4942)+binb
open(sys.argv[1],'wb').write(out)
P
