#!/bin/sh
# Finding seeds and operations by running them (plain, no engine): notes, wiki, subtitles, raster,
# directory scores, credential files, configs.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 90 "$@" </dev/null 2>&1 | tail -${TAILN:-8}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }

echo "##### jump"
mkdir -p /lab/jump/d1 /lab/jump/d2; export JUMP_HOME=/lab/jumpdb
cd /lab/jump/d1 && x jump chdir; cd /lab/jump/d2 && x jump chdir; x jump pin proj /lab/jump/d1
sum /lab/jumpdb; sum /s/aux/home 2>/dev/null | head; x jump top
unset JUMP_HOME; cd /

echo "##### dokuwiki"
cp -a /opt/dokuwiki /lab/dw
printf '====== Start ======\nOur household wiki.\n' > /lab/page.txt
x php /lab/dw/bin/dwpage.php -m "first" commit /lab/page.txt wiki:start
printf '====== Start ======\nOur household wiki, edited.\n' > /lab/page.txt
x php /lab/dw/bin/dwpage.php -m "second" commit /lab/page.txt wiki:start
sum /lab/dw/data | grep -v -E '/cache/|/index/' | head -20

echo "##### basic-memory"
mkdir -p /lab/bm
x basic-memory project add main /lab/bm --default
x basic-memory tool write-note --title "Plans" --folder notes --content "# Plans
- renew passport"
sum /lab/bm; sum /s/aux/home/.basic-memory 2>/dev/null | head
x basic-memory tool edit-note plans --operation append --content "- call the bank"
sum /lab/bm; cat /lab/bm/notes/*.md | head -12

echo "##### ffsubsync"
mkdir -p /lab/sub
python3 - <<'P'
def ts(s): h=int(s//3600); m=int(s%3600//60); sec=s%60; return f"{h:02}:{m:02}:{int(sec):02},{int((sec%1)*1000):03}"
ref=[]; sub=[]
for i in range(60):
    a=5+i*7.3; b=a+2.5
    ref.append(f"{i+1}\n{ts(a)} --> {ts(b)}\nline {i}\n")
    sub.append(f"{i+1}\n{ts(a+3.2)} --> {ts(b+3.2)}\nline {i}\n")
open('/lab/sub/ref.srt','w').write("\n".join(ref)); open('/lab/sub/movie.srt','w').write("\n".join(sub))
P
sum /lab/sub
TAILN=6 x ffsubsync /lab/sub/ref.srt -i /lab/sub/movie.srt --overwrite-input
sum /lab/sub; sed -n 1,3p /lab/sub/movie.srt

echo "##### rasterio"
mkdir -p /lab/rio
python3 -c "import numpy as np, rasterio; from rasterio.transform import from_origin; a=np.arange(10000,dtype='uint16').reshape(100,100);
d=rasterio.open('/lab/rio/a.tif','w',driver='GTiff',height=100,width=100,count=1,dtype='uint16',transform=from_origin(139.0,36.0,0.01,0.01)); d.write(a,1); d.close()" && echo made
sum /lab/rio
x rio edit-info --crs EPSG:4326 --tag survey=2026 /lab/rio/a.tif
sum /lab/rio; ls -la /lab/rio; x rio info /lab/rio/a.tif

echo "##### kaggle"
mkdir -p /lab/kg; printf '{"username":"alice","key":"0123456789abcdef0123456789abcdef"}\n' > /lab/kg/kaggle.json; chmod 600 /lab/kg/kaggle.json
export KAGGLE_CONFIG_DIR=/lab/kg
x kaggle config set -n path -v /data/kaggle
sum /lab/kg; cat /lab/kg/*.json; ls -la /lab/kg
unset KAGGLE_CONFIG_DIR

echo "##### huggingface_hub"
mkdir -p /lab/hf; export HF_HOME=/lab/hf
printf '[hf_a]\nhf_token = hf_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n\n[hf_b]\nhf_token = hf_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > /lab/hf/stored_tokens
printf 'hf_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' > /lab/hf/token
x hf auth list
x hf auth logout --token-name hf_a
sum /lab/hf; cat /lab/hf/stored_tokens
unset HF_HOME

echo "##### skopeo / oras / nerdctl (docker-style auth files)"
mkdir -p /lab/auth
for f in sk oras dc; do printf '{"auths":{"registry.example.com":{"auth":"YWxpY2U6c2VjcmV0"},"ghcr.io":{"auth":"Ym9iOnRva2Vu"},"quay.io":{"auth":"Y2Fyb2w6cHc="}}}\n' > /lab/auth/$f.json; done
x skopeo logout --authfile /lab/auth/sk.json registry.example.com
x oras logout --registry-config /lab/auth/oras.json registry.example.com
mkdir -p /lab/dcfg && cp /lab/auth/dc.json /lab/dcfg/config.json; export DOCKER_CONFIG=/lab/dcfg
x nerdctl logout registry.example.com
unset DOCKER_CONFIG
sum /lab/auth; sum /lab/dcfg; cat /lab/auth/sk.json; echo; cat /lab/dcfg/config.json; echo

echo "##### regctl"
mkdir -p /s/aux/home/.regctl
x regctl registry set registry.example.com --tls disabled
x regctl registry set ghcr.io --req-per-sec 5
sum /s/aux/home/.regctl; cat /s/aux/home/.regctl/config.json | head -20

echo "##### velero"
x velero client config set namespace=backups features=EnableCSI
sum /s/aux/home/.config/velero; cat /s/aux/home/.config/velero/config.json; echo

echo "##### codex"
mkdir -p /lab/codex; export CODEX_HOME=/lab/codex
printf 'model = "o3"\n\n[mcp_servers.docs]\ncommand = "docs-server"\n' > /lab/codex/config.toml
x codex mcp add notes -- /usr/bin/true --flag
sum /lab/codex; cat /lab/codex/config.toml
unset CODEX_HOME

echo "##### sheldon"
mkdir -p /lab/sheldon; export SHELDON_CONFIG_DIR=/lab/sheldon SHELDON_DATA_DIR=/lab/sheldon-data
printf 'shell = "zsh"\n\n[plugins.base16]\ngithub = "chriskempson/base16-shell"\n' > /lab/sheldon/plugins.toml
x sheldon add autosugg --github zsh-users/zsh-autosuggestions
sum /lab/sheldon; sum /lab/sheldon-data 2>/dev/null; cat /lab/sheldon/plugins.toml
unset SHELDON_CONFIG_DIR SHELDON_DATA_DIR

echo "##### micro"
mkdir -p /lab/micro; printf '{\n    "tabsize": 4,\n    "notanoption": true,\n    "colorscheme": "monokai"\n}\n' > /lab/micro/settings.json
x micro -config-dir /lab/micro -clean
sum /lab/micro; cat /lab/micro/settings.json

echo "##### vercel"
x vercel telemetry disable --global-config /lab/vercel
sum /lab/vercel; sum /s/aux/home/.local/share/com.vercel.cli 2>/dev/null

echo "##### ntfs-3g"
mkdir -p /lab/ntfs; truncate -s 16M /lab/ntfs/vol.img
x mkntfs -F -Q -L OLDLABEL /lab/ntfs/vol.img
sum /lab/ntfs
x ntfslabel /lab/ntfs/vol.img NEWLABEL
sum /lab/ntfs; x ntfslabel /lab/ntfs/vol.img

echo "##### firewalld"
sum /etc/firewalld | head; ls /etc/firewalld /etc/firewalld/zones 2>&1 | head
x firewall-offline-cmd --zone=public --add-port=8080/tcp
sum /etc/firewalld; ls -la /etc/firewalld/zones

echo "##### i18n-tasks"
mkdir -p /lab/i18n/config/locales /lab/i18n/app/views/home; cd /lab/i18n
printf 'en:\n  home:\n    index:\n      title: Welcome\n' > config/locales/en.yml
printf 'ja:\n  home:\n    index:\n      title: ようこそ\n' > config/locales/ja.yml
printf "<h1><%%= t('.title') %%></h1>\n<p><%%= t('.intro') %%></p>\n<p><%%= t('home.index.footer') %%></p>\n" > app/views/home/index.html.erb
x i18n-tasks missing
x i18n-tasks add-missing
sum /lab/i18n/config; cat config/locales/ja.yml
cd /

echo "##### yt-dlp"
mkdir -p /lab/yt-in /lab/yt; head -c 200000 /dev/urandom > /lab/yt-in/clip.mp4
printf 'generic clip0\n' > /lab/yt/archive.txt
x yt-dlp --enable-file-urls --download-archive /lab/yt/archive.txt -o '/lab/yt-out/%(title)s.%(ext)s' file:///lab/yt-in/clip.mp4
sum /lab/yt; cat /lab/yt/archive.txt; ls /lab/yt-out 2>&1
