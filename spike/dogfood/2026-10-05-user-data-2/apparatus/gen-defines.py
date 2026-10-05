#!/usr/bin/env python3
"""Write every candidate's define for the 2026-10-05 user-data-2 rounds: defines/<name>/{seed.sh,sideeye.toml}.

Copied in shape from 2026-10-03 user-data's gen-defines.py. One file holds them so the whole slate's
state roots, operations and seeds read side by side. A seed rebuilds the state root and anything the
operation reads from outside it (`<name>-in`), because `--twice` and replay put back only `--state`.
Paths under /s/aux are env.sh's HOME and XDG dirs.

Each operation was first run plainly by hand in the box (transcripts/lab-*.txt) and its arguments
are the ones that run took. A command string splits on spaces with no quoting (docs/cli.md), so no
argument carries a space.

Statically linked images are named BARE, as a user writes them: since v1.8.0 the default mode's
`no_shim_marker` names `--observe supervised` for a bare name too (ADR 0090), which 2026-10-03 had
to work around by naming them by path.

    python3 gen-defines.py            # (re)writes defines/ next to this file
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent

PIN = """# The clock pin docs/apparatus.md gives: libfaketime through /etc/ld.so.preload (never LD_PRELOAD,
# which Sideeye replaces), the time frozen. Written when this file is sourced, so a pinned define
# runs in a box of its own — the preload is global and would ride on every later target.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'"""
PIN_APPARATUS = '["env:FAKETIME=2026-10-01 00:00:00", "preload:libfaketime"]'

AUTH = ('{"auths":{"registry.example.com":{"auth":"YWxpY2U6c2VjcmV0"},'
        '"ghcr.io":{"auth":"Ym9iOnRva2Vu"},"quay.io":{"auth":"Y2Fyb2w6cHc="}}}')

GLB = r"""python3 - "$1" <<'P'
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
P"""

D = {}

D["monero"] = dict(
    state="/s/xmr", cwd="/s/xmr-in",
    # Pinned after the first gate: --twice found different bytes unpinned (transcripts/entry-candidates.txt).
    env=PIN, apparatus=PIN_APPARATUS,
    op="monero-wallet-cli --offline --wallet-file /s/xmr/w --password pw --log-file /s/xmr-in/log set_description rent-and-savings",
    seed=r"""
rm -rf /s/xmr /s/xmr-in && mkdir -p /s/xmr /s/xmr-in
monero-wallet-cli --offline --generate-new-wallet /s/xmr/w --password pw --mnemonic-language English --log-file /s/xmr-in/log exit > /s/xmr-in/gen.log 2>&1 || true
test -s /s/xmr/w.keys && test -s /s/xmr/w
""")

D["steamguard"] = dict(
    state="/s/sg", cwd="/s/sg-in",
    op="steamguard -m /s/sg -p correcthorse decrypt",
    seed=r"""
rm -rf /s/sg /s/sg-in && mkdir -p /s/sg /s/sg-in
printf '%s\n' '{"version":1,"entries":[{"filename":"alice.maFile","steam_id":76561198000000001,"account_name":"alice","encryption":null}],"keyring_id":null,"auto_confirm_market_transactions":false,"auto_confirm_trades":false}' > /s/sg/manifest.json
printf '%s\n' '{"shared_secret":"zvIayp3JPvtvX/QGHqsqKBk/44s=","serial_number":"12345678901234567890","revocation_code":"R12345","uri":"otpauth://totp/Steam:alice?secret=ZZZZ&issuer=Steam","server_time":1700000000,"account_name":"alice","token_gid":"abcdef0123456789","identity_secret":"Q2lkZW50aXR5LXNlY3JldC1leGFtcGxlPT0=","secret_1":"c2VjcmV0MS1leGFtcGxl","status":1,"device_id":"android:00000000-0000-0000-0000-000000000000","fully_enrolled":true,"steam_id":76561198000000001}' > /s/sg/alice.maFile
steamguard -m /s/sg -p correcthorse encrypt > /s/sg-in/encrypt.log 2>&1
grep -q Argon2id /s/sg/manifest.json
""")

D["lighthouse"] = dict(
    state="/s/lh", cwd="/s/lh-in",
    op="lighthouse account validator modify --datadir /s/lh disable --pubkey 0xa99a76ed7796f7be22d5b7e85deeb7c5677e88e511e0b337618f8c4eb61349b4bf2d153f649f7b53359fe8b94a38e44c",
    seed=r"""
rm -rf /s/lh /s/lh-in && mkdir -p /s/lh/validators /s/lh-in
cat > /s/lh/validators/validator_definitions.yml <<'J'
---
- enabled: true
  voting_public_key: "0xa99a76ed7796f7be22d5b7e85deeb7c5677e88e511e0b337618f8c4eb61349b4bf2d153f649f7b53359fe8b94a38e44c"
  type: local_keystore
  voting_keystore_path: /s/lh/validators/0xa99a/voting-keystore.json
  voting_keystore_password: "pw1"
- enabled: true
  voting_public_key: "0xb89bebc699769726a318c8e9971bd3171297c61aea4a6578a7a4f94b547dcba5bac16a89108b6b6a1fe3695d1a874a0b"
  type: local_keystore
  voting_keystore_path: /s/lh/validators/0xb89b/voting-keystore.json
  voting_keystore_password: "pw2"
J
""")

D["jump"] = dict(
    state="/s/jump", cwd="/s/jump-dirs",
    env="export JUMP_HOME=/s/jump",
    op="jump clean",
    seed=r"""
rm -rf /s/jump /s/jump-dirs && mkdir -p /s/jump /s/jump-dirs/notes /s/jump-dirs/photos /s/jump-dirs/old-project
export JUMP_HOME=/s/jump
for d in notes photos old-project notes photos notes; do (cd /s/jump-dirs/$d && jump chdir); done
jump pin pics /s/jump-dirs/photos
rmdir /s/jump-dirs/old-project
""")

D["dokuwiki"] = dict(
    state="/s/dw/data", cwd="/s/dw-in",
    env=PIN, apparatus=PIN_APPARATUS,
    op="php /s/dw/bin/dwpage.php commit -m second /s/dw-in/page.txt wiki:start",
    seed=r"""
rm -rf /s/dw /s/dw-in && cp -a /opt/dokuwiki /s/dw && mkdir -p /s/dw-in
printf '====== Start ======\nOur household wiki: the boiler is serviced in March.\n' > /s/dw-in/first.txt
php /s/dw/bin/dwpage.php commit -m first /s/dw-in/first.txt wiki:start > /s/dw-in/seed.log 2>&1
printf '====== Start ======\nOur household wiki: the boiler is serviced in March and October.\n' > /s/dw-in/page.txt
""")

D["basic-memory"] = dict(
    state="/s/bm", cwd="/s/bm-in",
    op="basic-memory tool edit-note --project notes plans --operation append --content renew-insurance",
    seed=r"""
rm -rf /s/bm /s/bm-in /s/aux/home/.basic-memory && mkdir -p /s/bm /s/bm-in
basic-memory project add notes /s/bm --default > /s/bm-in/seed.log 2>&1
basic-memory tool write-note --project notes --title Plans --folder notes --content '# Plans
- renew passport
- book the dentist' >> /s/bm-in/seed.log 2>&1
test -s /s/bm/notes/Plans.md
""")

D["ffsubsync"] = dict(
    state="/s/sub", cwd="/s/sub-in",
    op="ffsubsync /s/sub-in/ref.srt -i /s/sub/movie.srt --overwrite-input",
    seed=r"""
rm -rf /s/sub /s/sub-in && mkdir -p /s/sub /s/sub-in
python3 - <<'P'
def ts(s): h=int(s//3600); m=int(s%3600//60); sec=s%60; return f"{h:02}:{m:02}:{int(sec):02},{int((sec%1)*1000):03}"
ref=[]; sub=[]
for i in range(60):
    a=5+i*7.3; b=a+2.5
    ref.append(f"{i+1}\n{ts(a)} --> {ts(b)}\nline {i}\n")
    sub.append(f"{i+1}\n{ts(a+3.2)} --> {ts(b+3.2)}\nline {i}\n")
open('/s/sub-in/ref.srt','w').write("\n".join(ref)); open('/s/sub/movie.srt','w').write("\n".join(sub))
P
""")

D["rasterio"] = dict(
    state="/s/rio", cwd="/s/rio-in",
    op="rio edit-info --crs EPSG:4326 --tag survey=2026 /s/rio/a.tif",
    seed=r"""
rm -rf /s/rio /s/rio-in && mkdir -p /s/rio /s/rio-in
python3 -c "import numpy as np, rasterio; from rasterio.transform import from_origin; a=np.arange(10000,dtype='uint16').reshape(100,100); d=rasterio.open('/s/rio/a.tif','w',driver='GTiff',height=100,width=100,count=1,dtype='uint16',transform=from_origin(139.0,36.0,0.01,0.01)); d.write(a,1); d.close()"
""")

D["solvespace"] = dict(
    state="/s/ss", cwd="/s/ss-in",
    op="solvespace-cli regenerate /s/ss/part.slvs",
    seed=r"""
rm -rf /s/ss /s/ss-in && mkdir -p /s/ss /s/ss-in
cp /tmp/src/solvespace/test/group/translate_asy/normal_v22.slvs /s/ss/part.slvs
""")

D["ntfslabel"] = dict(
    state="/s/ntfs", cwd="/s/ntfs-in",
    op="ntfslabel /s/ntfs/vol.img NEWLABEL",
    seed=r"""
rm -rf /s/ntfs /s/ntfs-in && mkdir -p /s/ntfs /s/ntfs-in
truncate -s 16M /s/ntfs/vol.img
mkntfs -F -Q -L OLDLABEL /s/ntfs/vol.img > /s/ntfs-in/mkntfs.log 2>&1
""")

D["yt-dlp"] = dict(
    state="/s/yt", cwd="/s/yt-in",
    op="yt-dlp --enable-file-urls --download-archive /s/yt/archive.txt -o /s/yt-out/%(title)s.%(ext)s file:///s/yt-in/clip.mp4",
    seed=r"""
rm -rf /s/yt /s/yt-in /s/yt-out && mkdir -p /s/yt /s/yt-in
python3 -c "import random; random.seed(7); open('/s/yt-in/clip.mp4','wb').write(bytes(random.getrandbits(8) for _ in range(200000)))"
printf 'youtube dQw4w9WgXcQ\nvimeo 76979871\ngeneric holiday-2025\n' > /s/yt/archive.txt
""")

D["gltfpack"] = dict(
    state="/s/glp", cwd="/s/glp-in",
    op="gltfpack -i /s/glp/terrain.glb -o /s/glp/terrain.glb",
    seed="rm -rf /s/glp /s/glp-in && mkdir -p /s/glp /s/glp-in\nset -- /s/glp/terrain.glb\n" + GLB + "\n")

D["gltf-transform"] = dict(
    state="/s/glt", cwd="/s/glt-in",
    op="gltf-transform weld /s/glt/terrain.glb /s/glt/terrain.glb",
    seed="rm -rf /s/glt /s/glt-in && mkdir -p /s/glt /s/glt-in\nset -- /s/glt/terrain.glb\n" + GLB + "\n")

D["toybox"] = dict(
    state="/s/tb", cwd="/s/tb",
    op="toybox sed -i s/foo/bar/ a.txt b.txt",
    seed=r"""
rm -rf /s/tb && mkdir -p /s/tb && cd /s/tb
printf 'alpha foo\nbeta foo\ngamma\n' > a.txt
printf 'delta foo\nepsilon\n' > b.txt
""")

D["i18n-tasks"] = dict(
    state="/s/i18n/config/locales", cwd="/s/i18n",
    op="i18n-tasks add-missing",
    seed=r"""
rm -rf /s/i18n && mkdir -p /s/i18n/config/locales /s/i18n/app/views/home && cd /s/i18n
printf 'en:\n  home:\n    index:\n      title: Welcome\n' > config/locales/en.yml
printf 'ja:\n  home:\n    index:\n      title: ようこそ\n' > config/locales/ja.yml
printf "<h1><%%= t('.title') %%></h1>\n<p><%%= t('.intro') %%></p>\n<p><%%= t('home.index.footer') %%></p>\n" > app/views/home/index.html.erb
""")

D["goi18n"] = dict(
    state="/s/gi", cwd="/s/gi",
    op="goi18n merge active.en.toml active.ja.toml translate.ja.toml",
    seed=r"""
rm -rf /s/gi && mkdir -p /s/gi && cd /s/gi
printf '[Greeting]\nother = "Hello"\n\n[Farewell]\nother = "Goodbye"\n\n[Cart]\nother = "Cart"\n' > active.en.toml
printf '[Greeting]\nhash = "sha1-f7ff9e8b7bb2e09b70935a5d785e0cc5d9d0abf0"\nother = "こんにちは"\n' > active.ja.toml
goi18n merge active.en.toml active.ja.toml
sed -i 's/other = "Goodbye"/other = "さようなら"/; s/other = "Cart"/other = "カート"/' translate.ja.toml
grep -q さようなら translate.ja.toml
""")

D["firewalld"] = dict(
    state="/s/fw", cwd="/s/fw-in",
    op="firewall-offline-cmd --system-config /s/fw --zone=public --add-port=8080/tcp",
    seed=r"""
rm -rf /s/fw /s/fw-in && mkdir -p /s/fw /s/fw-in
cp /etc/firewalld/firewalld.conf /s/fw/
firewall-offline-cmd --system-config /s/fw --zone=public --add-service=ssh > /s/fw-in/seed.log 2>&1
test -s /s/fw/zones/public.xml
""")

D["kaggle"] = dict(
    state="/s/kg", cwd="/s/kg-in",
    env="export KAGGLE_CONFIG_DIR=/s/kg",
    op="kaggle config set -n path -v /data/kaggle",
    seed=r"""
rm -rf /s/kg /s/kg-in && mkdir -p /s/kg /s/kg-in
printf '{"username":"alice","key":"0123456789abcdef0123456789abcdef"}\n' > /s/kg/kaggle.json && chmod 600 /s/kg/kaggle.json
""")

D["hf"] = dict(
    state="/s/hf", cwd="/s/hf-in",
    env="export HF_HOME=/s/hf",
    op="hf auth logout --token-name hf_a",
    seed=r"""
rm -rf /s/hf /s/hf-in && mkdir -p /s/hf /s/hf-in
printf '[hf_a]\nhf_token = hf_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n\n[hf_b]\nhf_token = hf_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > /s/hf/stored_tokens
printf 'hf_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' > /s/hf/token
""")

D["skopeo"] = dict(
    state="/s/sk", cwd="/s/sk-in",
    op="skopeo logout --authfile /s/sk/auth.json registry.example.com",
    seed=f"""
rm -rf /s/sk /s/sk-in && mkdir -p /s/sk /s/sk-in
printf '%s\\n' '{AUTH}' > /s/sk/auth.json
""")

D["oras"] = dict(
    state="/s/oras", cwd="/s/oras-in",
    op="oras logout --registry-config /s/oras/config.json registry.example.com",
    seed=f"""
rm -rf /s/oras /s/oras-in && mkdir -p /s/oras /s/oras-in
printf '%s\\n' '{AUTH}' > /s/oras/config.json
""")

D["nerdctl"] = dict(
    state="/s/dc", cwd="/s/dc-in",
    env="export DOCKER_CONFIG=/s/dc",
    op="nerdctl logout registry.example.com",
    seed=f"""
rm -rf /s/dc /s/dc-in && mkdir -p /s/dc /s/dc-in
printf '%s\\n' '{AUTH}' > /s/dc/config.json
""")

D["regctl"] = dict(
    state="/s/aux/home/.regctl", cwd="/s/regctl-in",
    op="regctl registry set registry.example.com --tls disabled",
    # Exits 1 after writing: it pings the registry, which --network none cannot reach, and says the
    # configuration was still updated (transcripts/lab-3.txt, plain-runs.txt).
    expect=1,
    seed=r"""
rm -rf /s/aux/home/.regctl /s/regctl-in && mkdir -p /s/aux/home/.regctl /s/regctl-in
printf '{\n  "hosts": {\n    "ghcr.io": {\n      "tls": "enabled",\n      "hostname": "ghcr.io",\n      "reqPerSec": 5,\n      "reqConcurrent": 3\n    }\n  }\n}\n' > /s/aux/home/.regctl/config.json
""")

D["velero"] = dict(
    state="/s/aux/home/.config/velero", cwd="/s/velero-in",
    op="velero client config set namespace=backups",
    seed=r"""
rm -rf /s/aux/home/.config/velero /s/velero-in && mkdir -p /s/aux/home/.config/velero /s/velero-in
printf '{"features":"EnableCSI","namespace":"velero","colorized":"false"}\n' > /s/aux/home/.config/velero/config.json
""")

D["codex"] = dict(
    state="/s/codex", cwd="/s/codex-in",
    env="export CODEX_HOME=/s/codex",
    op="codex mcp add notes -- /usr/bin/true --flag",
    seed=r"""
rm -rf /s/codex /s/codex-in && mkdir -p /s/codex /s/codex-in
printf 'model = "o3"\n\n[mcp_servers.docs]\ncommand = "docs-server"\n' > /s/codex/config.toml
""")

D["gemini"] = dict(
    state="/s/aux/home/.gemini", cwd="/s/gemini-in",
    op="gemini mcp add -s user notes /usr/bin/true --flag",
    seed=r"""
rm -rf /s/aux/home/.gemini /s/gemini-in && mkdir -p /s/aux/home/.gemini /s/gemini-in
printf '{\n  "theme": "Default",\n  "mcpServers": {\n    "docs": {"command": "docs-server"}\n  }\n}\n' > /s/aux/home/.gemini/settings.json
""")

D["sheldon"] = dict(
    state="/s/sheldon", cwd="/s/sheldon-in",
    env="export SHELDON_CONFIG_DIR=/s/sheldon SHELDON_DATA_DIR=/s/sheldon-data",
    op="sheldon add autosugg --github zsh-users/zsh-autosuggestions",
    seed=r"""
rm -rf /s/sheldon /s/sheldon-data /s/sheldon-in && mkdir -p /s/sheldon /s/sheldon-in
printf 'shell = "zsh"\n\n[plugins.base16]\ngithub = "chriskempson/base16-shell"\n' > /s/sheldon/plugins.toml
""")

D["vercel"] = dict(
    state="/s/vercel", cwd="/s/vercel-in",
    op="vercel telemetry disable --global-config /s/vercel",
    seed=r"""
rm -rf /s/vercel /s/vercel-in && mkdir -p /s/vercel /s/vercel-in
printf '{\n  "// Note": "This is your Vercel config file.",\n  "telemetry": {\n    "enabled": true\n  }\n}\n' > /s/vercel/config.json
""")

D["wrangler"] = dict(
    state="/s/aux/home/.config/.wrangler", cwd="/s/wrangler-in",
    # Pinned after the first gate: --twice found different bytes unpinned; metrics.json carries a date.
    env="export WRANGLER_LOG_PATH=/s/wrangler-in/logs\n" + PIN, apparatus=PIN_APPARATUS,
    op="wrangler telemetry disable",
    seed=r"""
rm -rf /s/aux/home/.config/.wrangler /s/wrangler-in && mkdir -p /s/aux/home/.config/.wrangler /s/wrangler-in
printf '{\n  "permission": {\n    "enabled": true,\n    "date": "2026-09-01T00:00:00.000Z"\n  }\n}\n' > /s/aux/home/.config/.wrangler/metrics.json
""")

D["opam"] = dict(
    state="/s/opam", cwd="/s/opam-in",
    env="export OPAMROOT=/s/opam",
    op="opam option jobs=3 --global",
    seed=r"""
rm -rf /s/opam /s/opam-in /s/opam-repo && mkdir -p /s/opam-in /s/opam-repo/packages
printf 'opam-version: "2.0"\n' > /s/opam-repo/repo
OPAMROOT=/s/opam opam init --bare -n --disable-sandboxing default /s/opam-repo > /s/opam-in/init.log 2>&1
test -s /s/opam/config
""")

D["juliaup"] = dict(
    state="/s/jd", cwd="/s/jd-in",
    env="export JULIAUP_DEPOT_PATH=/s/jd",
    op="juliaup config versionsdbupdateinterval 0",
    seed=r"""
rm -rf /s/jd /s/jd-in && mkdir -p /s/jd /s/jd-in
JULIAUP_DEPOT_PATH=/s/jd juliaup config versionsdbupdateinterval 1440 > /s/jd-in/seed.log 2>&1
test -s /s/jd/juliaup/juliaup.json
""")

D["wandb"] = dict(
    state="/s/wb/wandb", cwd="/s/wb",
    op="wandb offline",
    seed=r"""
rm -rf /s/wb && mkdir -p /s/wb/wandb
printf '[default]\nmode = online\nproject = soil-survey\nentity = fieldlab\n' > /s/wb/wandb/settings
""")

D["stripe"] = dict(
    state="/s/aux/home/.config/stripe", cwd="/s/stripe-in",
    op="stripe config --set color off",
    # machine_uuid is in the seed: the first run without one writes a random one (transcripts/lab-6.txt).
    seed=r"""
rm -rf /s/aux/home/.config/stripe /s/stripe-in && mkdir -p /s/aux/home/.config/stripe /s/stripe-in
printf "color = ''\nmachine_uuid = '0b6f2c1e-1d2a-4c3b-9e8f-7a6b5c4d3e2f'\nproject-name = 'default'\n\n[default]\n  color = 'on'\n  device_name = 'laptop'\n  test_mode_api_key = 'sk_test_aaaa'\n  test_mode_pub_key = 'pk_test_aaaa'\n\n[work]\n  test_mode_api_key = 'sk_test_bbbb'\n" > /s/aux/home/.config/stripe/config.toml
""")

D["infracost"] = dict(
    state="/s/aux/home/.config/infracost", cwd="/s/infracost-in",
    op="infracost configure set api_key ico-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    seed=r"""
rm -rf /s/aux/home/.config/infracost /s/infracost-in && mkdir -p /s/aux/home/.config/infracost /s/infracost-in
printf 'version: "0.1"\ncurrency: EUR\nenable_cloud: null\nenable_cloud_upload: null\n' > /s/aux/home/.config/infracost/configuration.yml
printf 'version: "0.1"\napi_key: ico-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\npricing_api_endpoint: https://pricing.example.internal\n' > /s/aux/home/.config/infracost/credentials.yml
""")

D["fitscheck"] = dict(
    state="/s/fits", cwd="/s/fits-in",
    env=PIN, apparatus=PIN_APPARATUS,
    op="fitscheck -k standard -w -i /s/fits/obs.fits",
    seed=r"""
rm -rf /s/fits /s/fits-in && mkdir -p /s/fits /s/fits-in
python3 -c "import numpy as np; from astropy.io import fits; h=fits.PrimaryHDU(np.arange(4096,dtype='int16').reshape(64,64)); h.header['OBSERVER']='night-1'; t=fits.ImageHDU(np.ones((32,32),dtype='float32'),name='FLAT'); fits.HDUList([h,t]).writeto('/s/fits/obs.fits')"
""")

D["pymol"] = dict(
    state="/s/pm", cwd="/s/pm-in",
    # Debian's `pymol` wrapper runs the first python3 on PATH, which in this box is the candidates' venv
    # without pymol in it (transcripts/lab-6.txt); the package's own interpreter is named instead.
    op="/usr/bin/python3 -m pymol -cq /s/pm/model.pse /s/pm-in/edit.pml",
    seed=r"""
rm -rf /s/pm /s/pm-in && mkdir -p /s/pm /s/pm-in
printf 'fragment ala\nfragment gly\nsave /s/pm/model.pse\n' > /s/pm-in/make.pml
/usr/bin/python3 -m pymol -cq /s/pm-in/make.pml > /s/pm-in/make.log 2>&1
printf 'set bg_rgb, white\ncolor red, ala\nsave /s/pm/model.pse\n' > /s/pm-in/edit.pml
""")

D["azure-cli"] = dict(
    state="/s/az", cwd="/s/az-in",
    # AZURE_LOGGING_ENABLE_LOG_FILE=no after the second gate: each run wrote commands/<time>.config_set.<pid>.log,
    # which the pin cannot hold still (transcripts/entry-candidates-2.txt) — preflight's "relocate what differs".
    env="export AZURE_CONFIG_DIR=/s/az AZURE_CORE_COLLECT_TELEMETRY=0 AZURE_LOGGING_ENABLE_LOG_FILE=no\n" + PIN, apparatus=PIN_APPARATUS,
    op="az config set core.output=table",
    seed=r"""
rm -rf /s/az /s/az-in && mkdir -p /s/az /s/az-in
printf '[core]\noutput = json\ncollect_telemetry = false\n\n[defaults]\nlocation = japaneast\ngroup = rg-home\n' > /s/az/config
""")

D["dotenv"] = dict(
    state="/s/env", cwd="/s/env",
    op="dotenv -f /s/env/.env set DEBUG true",
    seed=r"""
rm -rf /s/env && mkdir -p /s/env
printf '# production secrets\nDATABASE_URL=postgres://app:pw@db/app\nSTRIPE_KEY=sk_live_aaaa\nDEBUG=false\n' > /s/env/.env
""")

D["gita"] = dict(
    state="/s/gita/gita", cwd="/s/gita-in",
    env="export XDG_CONFIG_HOME=/s/gita",
    op="gita rename a alpha",
    seed=r"""
rm -rf /s/gita /s/gita-in /s/repos && mkdir -p /s/gita/gita /s/gita-in /s/repos/a/.git /s/repos/b/.git
printf '/s/repos/a,a,,\n/s/repos/b,b,,\n' > /s/gita/gita/repos.csv
printf 'work:a b:\n' > /s/gita/gita/groups.csv
""")

D["homeassistant"] = dict(
    state="/s/ha", cwd="/s/ha-in",
    op="hass --script auth -c /s/ha change_password alice pw-three",
    seed=r"""
rm -rf /s/ha /s/ha-in && mkdir -p /s/ha /s/ha-in
hass --script auth -c /s/ha add alice pw-one > /s/ha-in/seed.log 2>&1
hass --script auth -c /s/ha add bob pw-two >> /s/ha-in/seed.log 2>&1
test -s /s/ha/.storage/auth_provider.homeassistant
""")

D["wp-cli"] = dict(
    state="/s/wp", cwd="/s/wp-in",
    # The phar is a `#!/usr/bin/env php` script, which v1.8.0 refuses by name (operation_not_an_image),
    # so the interpreter is named the way a user runs a phar without its exec bit.
    op="php /opt/bin/wp config set DB_PASSWORD new-secret --path=/s/wp --allow-root",
    seed=r"""
rm -rf /s/wp /s/wp-in && mkdir -p /s/wp /s/wp-in
cat > /s/wp/wp-config.php <<'P'
<?php
define( 'DB_NAME', 'household' );
define( 'DB_USER', 'wpuser' );
define( 'DB_PASSWORD', 'old-secret' );
define( 'DB_HOST', 'localhost' );
define( 'AUTH_KEY', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' );
$table_prefix = 'wp_';
if ( ! defined( 'ABSPATH' ) ) { define( 'ABSPATH', __DIR__ . '/' ); }
require_once ABSPATH . 'wp-settings.php';
P
""")

D["dynaconf"] = dict(
    state="/s/dyn", cwd="/s/dyn",
    # -y: without it the command asks on stdin whether to overwrite .secrets.toml and, given EOF, aborts
    # (transcripts/lab-11.txt).
    op="dynaconf write toml -y -s DB_PASSWORD=new-secret -p /s/dyn/",
    seed=r"""
rm -rf /s/dyn && mkdir -p /s/dyn
printf '[default]\nDB_HOST = "db.internal"\nDB_PASSWORD = "old-secret"\nAPI_TOKEN = "tok-aaaa"\n' > /s/dyn/.secrets.toml
printf '[default]\nNAME = "household"\n' > /s/dyn/settings.toml
""")

D["lingui"] = dict(
    state="/s/lg/locales", cwd="/s/lg",
    env=PIN, apparatus=PIN_APPARATUS,
    op="node /opt/lingui-proj/node_modules/@lingui/cli/dist/lingui.js extract",
    seed=r"""
rm -rf /s/lg && mkdir -p /s/lg/src /s/lg/locales/en /s/lg/locales/ja && cd /s/lg && ln -s /opt/lingui-proj/node_modules node_modules
printf '{"name":"site","private":true,"type":"module"}\n' > package.json
printf 'import { defineConfig } from "@lingui/cli";\nexport default defineConfig({ sourceLocale: "en", locales: ["en", "ja"], catalogs: [{ path: "<rootDir>/locales/{locale}/messages", include: ["src"] }] });\n' > lingui.config.js
printf 'import { t } from "@lingui/core/macro";\nexport const a = t`Welcome home`;\nexport const b = t`Your basket`;\n' > src/app.js
node /opt/lingui-proj/node_modules/@lingui/cli/dist/lingui.js extract > /s/lg-seed.log 2>&1
sed -i 's/^msgstr ""$/msgstr "XX"/; 1,3s/^msgstr "XX"$/msgstr ""/' locales/ja/messages.po
sed -i 's/msgid "Welcome home"/&/' locales/ja/messages.po
printf 'export const c = t`Checkout now`;\n' >> src/app.js
""")

D["conan"] = dict(
    state="/s/conan", cwd="/s/conan-in",
    env="export CONAN_HOME=/s/conan",
    op="conan remote disable conancenter",
    seed=r"""
rm -rf /s/conan /s/conan-in && mkdir -p /s/conan-in
CONAN_HOME=/s/conan conan remote add internal https://artifacts.example.internal/conan > /s/conan-in/seed.log 2>&1
test -s /s/conan/remotes.json
""")

D["platformio"] = dict(
    state="/s/pio", cwd="/s/pio-in",
    # Pinned: each run stamps last_check into appstate.json (transcripts/lab-12.txt).
    env="export PLATFORMIO_CORE_DIR=/s/pio\n" + PIN, apparatus=PIN_APPARATUS,
    op="pio settings set check_platformio_interval 30",
    seed=r"""
rm -rf /s/pio /s/pio-in && mkdir -p /s/pio /s/pio-in
printf '{"last_version": "6.2.0", "last_check": {"platformio_upgrade": 1790000000, "prune_system": 1790000000}, "settings": {"enable_telemetry": false, "projects_dir": "/home/me/firmware"}}' > /s/pio/appstate.json
""")

D["tenv"] = dict(
    state="/s/tenv", cwd="/s/tenv-in",
    env="export TENV_ROOT=/s/tenv",
    # The constraint file's directory has to exist: tenv does not make it (transcripts/lab-13.txt).
    op="tenv tf constraint ~>1.6",
    seed=r"""
rm -rf /s/tenv /s/tenv-in && mkdir -p /s/tenv/Terraform /s/tenv-in
printf '>=1.5.0' > /s/tenv/Terraform/constraint
""")

D["xmake"] = dict(
    state="/s/xm/.xmake", cwd="/s/xm-in",
    env="export XMAKE_ROOT=y XMAKE_GLOBALDIR=/s/xm",
    op="xmake g --theme=plain",
    seed=r"""
rm -rf /s/xm /s/xm-in && mkdir -p /s/xm /s/xm-in
XMAKE_ROOT=y XMAKE_GLOBALDIR=/s/xm xmake g --network=private > /s/xm-in/seed.log 2>&1
test -s /s/xm/.xmake/xmake.conf
""")

D["crictl"] = dict(
    state="/s/cri", cwd="/s/cri-in",
    op="crictl --config /s/cri/crictl.yaml config --set timeout=10",
    seed=r"""
rm -rf /s/cri /s/cri-in && mkdir -p /s/cri /s/cri-in
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 2\ndebug: false\n' > /s/cri/crictl.yaml
""")

D["k8sgpt"] = dict(
    state="/s/aux/home/.config/k8sgpt", cwd="/s/k8sgpt-in",
    op="k8sgpt auth remove --backends openai",
    seed=r"""
rm -rf /s/aux/home/.config/k8sgpt /s/k8sgpt-in && mkdir -p /s/k8sgpt-in
k8sgpt auth add --backend openai --model gpt-4o --password sk-test-aaaa > /s/k8sgpt-in/seed.log 2>&1
k8sgpt auth add --backend localai --model llama --baseurl http://localhost:8080/v1 >> /s/k8sgpt-in/seed.log 2>&1
test -s /s/aux/home/.config/k8sgpt/k8sgpt.yaml
""")

D["ggshield"] = dict(
    state="/s/gg", cwd="/s/gg-in",
    # The user configuration is $HOME/.gitguardian.yaml, so HOME is a directory of its own here.
    env="export HOME=/s/gg",
    op="ggshield config set default_token_lifetime 30",
    seed=r"""
rm -rf /s/gg /s/gg-in && mkdir -p /s/gg /s/gg-in
printf 'version: 2\ninstance: https://dashboard.gitguardian.example\nexit_zero: false\n' > /s/gg/.gitguardian.yaml
""")

D["uv"] = dict(
    state="/s/uvd/uv/credentials", cwd="/s/uv-in",
    env="export XDG_DATA_HOME=/s/uvd",
    op="/opt/py/bin/uv auth logout https://pkgs.example.internal/simple --username alice",
    seed=r"""
rm -rf /s/uvd /s/uv-in && mkdir -p /s/uvd /s/uv-in
XDG_DATA_HOME=/s/uvd /opt/py/bin/uv auth login https://pkgs.example.internal/simple --username alice --password pw1 > /s/uv-in/seed.log 2>&1
XDG_DATA_HOME=/s/uvd /opt/py/bin/uv auth login https://mirror.example.org/simple --username bob --password pw2 >> /s/uv-in/seed.log 2>&1
test -s /s/uvd/uv/credentials/credentials.toml
""")

D["juju"] = dict(
    state="/s/juju", cwd="/s/juju-in",
    env="export JUJU_DATA=/s/juju",
    op="juju remove-credential aws home --client",
    # The seed's add-credential is juju's first run: it also makes the client's SSH key pair and tries to
    # fetch public cloud data (no network: it says so and goes on, transcripts/lab-17.txt).
    seed=r"""
rm -rf /s/juju /s/juju-in && mkdir -p /s/juju-in
printf 'credentials:\n  aws:\n    work:\n      auth-type: access-key\n      access-key: FAKE-ACCESS-ID-00001\n      secret-key: example-secret-1\n    home:\n      auth-type: access-key\n      access-key: FAKE-ACCESS-ID-00002\n      secret-key: example-secret-2\n' > /s/juju-in/creds.yaml
JUJU_DATA=/s/juju juju add-credential aws -f /s/juju-in/creds.yaml --client > /s/juju-in/seed.log 2>&1
test -s /s/juju/credentials.yaml
""")

D["aliyun"] = dict(
    state="/s/aux/home/.aliyun", cwd="/s/aliyun-in",
    op="aliyun configure delete --profile home",
    seed=r"""
rm -rf /s/aux/home/.aliyun /s/aliyun-in && mkdir -p /s/aliyun-in
aliyun configure set --profile work --mode AK --access-key-id FAKE-ALI-ID-00001 --access-key-secret examplesecret0001 --region cn-hangzhou > /s/aliyun-in/seed.log 2>&1
aliyun configure set --profile home --mode AK --access-key-id FAKE-ALI-ID-00002 --access-key-secret examplesecret0002 --region ap-northeast-1 >> /s/aliyun-in/seed.log 2>&1
test -s /s/aux/home/.aliyun/config.json
""")

D["firebase"] = dict(
    state="/s/aux/home/.config/configstore", cwd="/s/firebase-in",
    op="firebase experiments:disable webframeworks",
    seed=r"""
rm -rf /s/aux/home/.config/configstore /s/firebase-in && mkdir -p /s/aux/home/.config/configstore /s/firebase-in
printf '{\n\t"user": {\n\t\t"email": "alice@example.com"\n\t},\n\t"tokens": {\n\t\t"refresh_token": "1//example-refresh-token"\n\t},\n\t"previews": {\n\t\t"webframeworks": true\n\t}\n}' > /s/aux/home/.config/configstore/firebase-tools.json
printf '{\n\t"optOut": false,\n\t"lastUpdateCheck": 1790000000000\n}' > /s/aux/home/.config/configstore/update-notifier-firebase-tools.json
""")

D["turbo"] = dict(
    state="/s/aux/home/.config/turborepo", cwd="/s/turbo-in",
    # The npm package's bin/turbo is a Node wrapper that spawns the native binary; the binary is named,
    # as the wrapper itself runs it (transcripts/lab-20.txt).
    op="/opt/node22/lib/node_modules/turbo/node_modules/@turbo/linux-arm64/bin/turbo telemetry disable",
    seed=r"""
rm -rf /s/aux/home/.config/turborepo /s/turbo-in && mkdir -p /s/aux/home/.config/turborepo /s/turbo-in
printf '{\n  "telemetry_enabled": true,\n  "telemetry_id": "3691f04b0746bce5f7edb6d219ee133c1d6b8346f2c92e408b22b379c9ef5c68",\n  "telemetry_salt": "ee1371b9-85a0-458a-97d2-b7f54c29f2b9",\n  "telemetry_alerted": "2026-09-01T00:00:00Z"\n}' > /s/aux/home/.config/turborepo/telemetry.json
""")

D["kubeadm"] = dict(
    state="/s/kadm", cwd="/s/kadm-in",
    # The first migrate fills in a random bootstrap token and the hostname; migrating the filled-in
    # file again gives the same bytes every time (transcripts/lab-21.txt). The seed migrates once and
    # drops one defaulted line, which the measured migrate writes back.
    op="kubeadm config migrate --old-config /s/kadm/kubeadm.yaml --new-config /s/kadm/kubeadm.yaml",
    seed=r"""
rm -rf /s/kadm /s/kadm-in && mkdir -p /s/kadm /s/kadm-in
printf 'apiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\nkubernetesVersion: v1.37.1\nclusterName: home\nnetworking:\n  podSubnet: 10.244.0.0/16\n' > /s/kadm/kubeadm.yaml
kubeadm config migrate --old-config /s/kadm/kubeadm.yaml --new-config /s/kadm/kubeadm.yaml > /s/kadm-in/seed.log 2>&1
sed -i '/imagePullSerial/d' /s/kadm/kubeadm.yaml
""")

D["go"] = dict(
    state="/s/goenv", cwd="/s/goenv-in",
    # Upstream's go 1.27.1 ahead of trixie's 1.24.4 on PATH, so the operation names `go` bare as a user
    # writes it. Telemetry is turned off in the seed (`go telemetry off`, a user's own setting): left on,
    # every run writes mmap-ed counter files under HOME.
    env="export PATH=/opt/go127/go/bin:$PATH GOENV=/s/goenv/env",
    op="go env -w GOFLAGS=-mod=mod",
    seed=r"""
rm -rf /s/goenv /s/goenv-in && mkdir -p /s/goenv /s/goenv-in
/opt/go127/go/bin/go telemetry off > /s/goenv-in/seed.log 2>&1
GOENV=/s/goenv/env /opt/go127/go/bin/go env -w GOPROXY=https://proxy.example.internal,direct GOPRIVATE=git.example.internal/* GONOSUMDB=git.example.internal/* >> /s/goenv-in/seed.log 2>&1
test -s /s/goenv/env
""")


def main():
    out = HERE / "defines"
    for name, d in D.items():
        p = out / name
        p.mkdir(parents=True, exist_ok=True)
        (p / "seed.sh").write_text("set -eu\n" + d["seed"].lstrip("\n"))
        (p / "sideeye.toml").write_text(
            f'[world]\nstate = "{d["state"]}"\n\n[define]\noperation = "{d["op"]}"\ncwd       = "{d["cwd"]}"\n'
            + (f'apparatus = {d["apparatus"]}\n' if "apparatus" in d else "")
            + (f'expected_status = "{d["expect"]}"\n' if "expect" in d else ""))  # a quoted string (docs/cli.md); unquoted, explore refused it at setup
        if "env" in d:
            (p / "env.sh").write_text(d["env"] + "\n")
        elif (p / "env.sh").exists():
            (p / "env.sh").unlink()
    print(len(D), "defines:", " ".join(D))


main()
