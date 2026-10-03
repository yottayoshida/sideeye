#!/usr/bin/env python3
"""Write every candidate's define for the 2026-10-03 user-data rounds: defines/<name>/{seed.sh,sideeye.toml}.

One file holds them so the whole slate's state roots, operations and seeds read side by side. A seed
rebuilds the state root and anything the operation reads from outside it (`<name>-in`), because
`--twice` and replay put back only `--state`. Paths under /s/aux are env.sh's HOME and XDG dirs.

    python3 gen-defines.py            # (re)writes defines/ next to this file
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent

# A statically linked image is named by path in its operation: named bare, v1.7.0's default-mode
# no_shim_marker names no observation mode, so run.sh would not follow it to supervised
# (2026-09-28 RESULTS.md, revision 1). The gate answers the same either way.
STATIC_BY_PATH = True

PIN = """# The clock pin docs/apparatus.md gives: libfaketime through /etc/ld.so.preload (never LD_PRELOAD,
# which Sideeye replaces), the time frozen. Written when this file is sourced, so a pinned define
# runs in a box of its own — the preload is global and would ride on every later target.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'"""

D = {}

D["perl"] = dict(
    state="/s/perl", cwd="/s/perl",
    op="perl -i -pe s/foo/bar/ a.txt b.txt",
    seed=r"""
rm -rf /s/perl && mkdir -p /s/perl && cd /s/perl
printf 'alpha foo\nbeta foo\ngamma\n' > a.txt
printf 'delta foo\nepsilon\n' > b.txt
""")

D["kakoune"] = dict(
    state="/s/kakoune", cwd="/s/kakoune",
    op="kak -n -f ggiX<esc> a.txt b.txt",
    seed=r"""
rm -rf /s/kakoune && mkdir -p /s/kakoune && cd /s/kakoune
printf 'first line\nsecond line\nthird line\n' > a.txt
printf 'one\ntwo\n' > b.txt
""")

D["samtools"] = dict(
    state="/s/samtools", cwd="/s/samtools-in",
    op="samtools reheader -i /s/samtools-in/new.hdr /s/samtools/a.cram",
    seed=r"""
rm -rf /s/samtools /s/samtools-in && mkdir -p /s/samtools /s/samtools-in && cd /s/samtools-in
{ printf '@HD\tVN:1.6\tSO:unsorted\n@SQ\tSN:chr1\tLN:1000\n@RG\tID:rg1\tSM:sampleA\n'
  i=0; while [ $i -lt 50 ]; do printf 'r%d\t0\tchr1\t%d\t60\t10M\t*\t0\t0\tACGTACGTAC\tIIIIIIIIII\tRG:Z:rg1\n' $i $((i*10+1)); i=$((i+1)); done; } > a.sam
samtools view -C --output-fmt-option no_ref=1 -o /s/samtools/a.cram a.sam
samtools view -H /s/samtools/a.cram | sed 's/sampleA/sampleB/' > new.hdr
""")

D["upx"] = dict(
    state="/s/upx", cwd="/s/upx",
    op="upx -q /s/upx/prog",
    seed=r"""
rm -rf /s/upx && mkdir -p /s/upx
cp /usr/bin/bash /s/upx/prog
""")

D["bzip3"] = dict(
    state="/s/bzip3", cwd="/s/bzip3",
    op="bzip3 -e --rm a.log",
    seed=r"""
rm -rf /s/bzip3 && mkdir -p /s/bzip3 && cd /s/bzip3
i=0; while [ $i -lt 2000 ]; do echo "line $i of a log that matters"; i=$((i+1)); done > a.log
""")

D["hexapdf"] = dict(
    state="/s/hexapdf", cwd="/s/hexapdf",
    env=PIN,
    apparatus='["env:FAKETIME=2026-10-01 00:00:00", "preload:libfaketime"]',
    op="hexapdf -f modify -i 1-2 a.pdf a.pdf",
    seed=r"""
rm -rf /s/hexapdf && mkdir -p /s/hexapdf && cd /s/hexapdf
ruby -e 'require "hexapdf"; d=HexaPDF::Document.new; 3.times{|i| d.pages.add.canvas.font("Helvetica",size:12).text("page #{i}",at:[50,700])}; d.write("a.pdf")'
""")

D["mapshaper"] = dict(
    state="/s/mapshaper", cwd="/s/mapshaper",
    op="mapshaper /s/mapshaper/a.shp -each x=n*10 -o force",
    seed=r"""
rm -rf /s/mapshaper /s/mapshaper-in && mkdir -p /s/mapshaper /s/mapshaper-in
cat > /s/mapshaper-in/in.json <<'J'
{"type":"FeatureCollection","features":[
{"type":"Feature","properties":{"name":"a","n":1},"geometry":{"type":"Point","coordinates":[139.7,35.6]}},
{"type":"Feature","properties":{"name":"b","n":2},"geometry":{"type":"Point","coordinates":[135.5,34.7]}},
{"type":"Feature","properties":{"name":"c","n":3},"geometry":{"type":"Point","coordinates":[141.3,43.0]}}]}
J
cd /s/mapshaper-in && mapshaper -i in.json -o format=shapefile /s/mapshaper/a.shp > /dev/null 2>&1
""")

D["nushell"] = dict(
    state="/s/nushell", cwd="/s/nushell-in",
    op="nu -n /s/nushell-in/edit.nu",
    seed=r"""
rm -rf /s/nushell /s/nushell-in && mkdir -p /s/nushell /s/nushell-in
printf '{"name":"ledger","entries":[1,2,3,4,5],"owner":"me"}\n' > /s/nushell/a.json
printf 'open /s/nushell/a.json | upsert note "kept" | save -f /s/nushell/a.json\n' > /s/nushell-in/edit.nu
""")

D["kustomize"] = dict(
    state="/s/kustomize", cwd="/s/kustomize",
    op="/opt/bin/kustomize edit set image nginx=nginx:1.27.1",
    seed=r"""
rm -rf /s/kustomize && mkdir -p /s/kustomize && cd /s/kustomize
printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n- deploy.yaml\nimages:\n- name: nginx\n  newTag: "1.25"\n' > kustomization.yaml
printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: web\n' > deploy.yaml
""")

D["zlua"] = dict(
    state="/s/zlua", cwd="/s/zlua-dirs",
    op="lua5.4 /opt/bin/z.lua --add /s/zlua-dirs/projects",
    env="export _ZL_DATA=/s/zlua/zlua.db\n" + PIN,
    apparatus='["env:FAKETIME=2026-10-01 00:00:00", "preload:libfaketime"]',
    seed=r"""
rm -rf /s/zlua /s/zlua-dirs && mkdir -p /s/zlua /s/zlua-dirs/projects /s/zlua-dirs/notes
printf '/s/zlua-dirs/notes|12|1790000000\n/s/zlua-dirs/projects|3|1790000100\n/root|40|1790000200\n' > /s/zlua/zlua.db
""")

D["doing"] = dict(
    state="/s/doing", cwd="/s/doing-in",
    op="doing now wrote the quarterly notes",
    seed=r"""
rm -rf /s/doing /s/doing-in && mkdir -p /s/doing /s/doing-in /s/aux/home/.config/doing
printf -- '---\ndoing_file: /s/doing/doing.md\ncurrent_section: Currently\nbackup_dir: /s/doing-in/backups\n' > /s/aux/home/.config/doing/config.yml
printf 'Currently:\n\t- 2026-10-01 09:00 | met the auditors <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>\n\t- 2026-10-02 10:30 | reconciled september <bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb>\n' > /s/doing/doing.md
""")

D["notesmd"] = dict(
    state="/s/notes", cwd="/s/notes-in",
    op="/opt/bin/notesmd-cli move projects/alpha projects/alpha-2026 --vault vault",
    seed=r"""
rm -rf /s/notes /s/notes-in && mkdir -p /s/notes/vault/projects /s/notes/vault/daily /s/notes-in /s/aux/home/.config/obsidian
printf '{"vaults":{"v1":{"path":"/s/notes/vault","ts":1,"open":true}}}\n' > /s/aux/home/.config/obsidian/obsidian.json
printf '# Alpha\nThe alpha plan.\n' > /s/notes/vault/projects/alpha.md
printf 'Worked on [[alpha]] today.\nSee [[projects/alpha]].\n' > /s/notes/vault/daily/2026-10-01.md
printf 'Index: [[alpha]], [[beta]]\n' > /s/notes/vault/index.md
""")

D["dotdrop"] = dict(
    state="/s/dotdrop", cwd="/s/dotdrop-in",
    op="dotdrop install -f -c /s/dotdrop-in/config.yaml -p host",
    seed=r"""
rm -rf /s/dotdrop /s/dotdrop-in && mkdir -p /s/dotdrop/home /s/dotdrop-in/dotfiles
printf 'config:\n  backup: true\n  create: true\n  dotpath: dotfiles\ndotfiles:\n  f_bashrc:\n    src: bashrc\n    dst: /s/dotdrop/home/.bashrc\n  f_gitconfig:\n    src: gitconfig\n    dst: /s/dotdrop/home/.gitconfig\nprofiles:\n  host:\n    dotfiles:\n    - f_bashrc\n    - f_gitconfig\n' > /s/dotdrop-in/config.yaml
printf 'export EDITOR=vim\nalias ll="ls -l"\n' > /s/dotdrop-in/dotfiles/bashrc
printf '[user]\n\tname = me\n' > /s/dotdrop-in/dotfiles/gitconfig
printf '# my local bashrc, hand edited\nexport PATH=$HOME/bin:$PATH\n' > /s/dotdrop/home/.bashrc
printf '[user]\n\tname = old\n' > /s/dotdrop/home/.gitconfig
""")

D["dotter"] = dict(
    state="/s/dotter", cwd="/s/dotter-in",
    op="/opt/bin/dotter deploy -f -y",
    seed=r"""
rm -rf /s/dotter /s/dotter-in && mkdir -p /s/dotter/home /s/dotter-in/.dotter
printf '[default.files]\nbashrc = { target = "/s/dotter/home/.bashrc", type = "template" }\ngitconfig = { target = "/s/dotter/home/.gitconfig", type = "template" }\n' > /s/dotter-in/.dotter/global.toml
printf 'packages = ["default"]\n' > /s/dotter-in/.dotter/local.toml
printf 'export EDITOR=vim\n' > /s/dotter-in/bashrc
printf '[user]\n\tname = me\n' > /s/dotter-in/gitconfig
printf '# hand edited\nexport PATH=$HOME/bin:$PATH\n' > /s/dotter/home/.bashrc
printf '[user]\n\tname = old\n' > /s/dotter/home/.gitconfig
""")

D["mu"] = dict(
    state="/s/mu", cwd="/s/mu-in",
    # The index lives inside the state root: kept outside, the first recorded run moved the
    # message in the index too and the second, from restored mail but the same index, failed.
    op="mu move --muhome /s/mu/home /s/mu/Maildir/inbox/cur/1001.msg:2,S /archive",
    seed=r"""
rm -rf /s/mu /s/mu-in && mkdir -p /s/mu-in /s/mu/home
for d in inbox archive; do mkdir -p /s/mu/Maildir/$d/cur /s/mu/Maildir/$d/new /s/mu/Maildir/$d/tmp; done
for n in 1001 1002 1003; do
  printf 'From: a@example.org\nTo: me@example.org\nSubject: message %s\nDate: Thu, 01 Oct 2026 10:00:00 +0000\nMessage-ID: <%s@example.org>\n\nbody of %s\n' $n $n $n > "/s/mu/Maildir/inbox/cur/$n.msg:2,S"
done
mu init --muhome /s/mu/home --maildir /s/mu/Maildir > /dev/null
mu index --muhome /s/mu/home > /dev/null
""")

D["snapraid"] = dict(
    state="/s/snapraid", cwd="/s/snapraid-in",
    op="snapraid -c /s/snapraid-in/snapraid.conf sync",
    seed=r"""
rm -rf /s/snapraid /s/snapraid-in && mkdir -p /s/snapraid/d1 /s/snapraid/parity /s/snapraid/content /s/snapraid-in
printf 'parity /s/snapraid/parity/snapraid.parity\ncontent /s/snapraid/content/snapraid.content\ncontent /s/snapraid/d1/snapraid.content\ndata d1 /s/snapraid/d1/\nblocksize 64\n' > /s/snapraid-in/snapraid.conf
head -c 200000 /dev/zero | tr '\0' 'a' > /s/snapraid/d1/photo1.raw
head -c 150000 /dev/zero | tr '\0' 'b' > /s/snapraid/d1/photo2.raw
snapraid -c /s/snapraid-in/snapraid.conf sync > /dev/null 2>&1
head -c 120000 /dev/zero | tr '\0' 'c' > /s/snapraid/d1/photo3.raw
""")

D["dotenvx"] = dict(
    state="/s/dotenvx", cwd="/s/dotenvx",
    op="dotenvx encrypt -f /s/dotenvx/.env",
    seed=r"""
rm -rf /s/dotenvx && mkdir -p /s/dotenvx
printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > /s/dotenvx/.env
""")

D["gocryptfs"] = dict(
    state="/s/gocryptfs", cwd="/s/gocryptfs-in",
    # gocryptfs reads the NEW password from stdin and an operation has none, so the change is
    # issued from a two-line script outside the state root; gocryptfs is its awaited child.
    op="sh /s/gocryptfs-in/chpw.sh",
    seed=r"""
rm -rf /s/gocryptfs /s/gocryptfs-in && mkdir -p /s/gocryptfs/cipher /s/gocryptfs-in
printf 'old-passphrase\n' > /s/gocryptfs-in/old
printf 'new-passphrase\n' > /s/gocryptfs-in/new
printf 'exec gocryptfs -passwd -passfile /s/gocryptfs-in/old /s/gocryptfs/cipher < /s/gocryptfs-in/new\n' > /s/gocryptfs-in/chpw.sh
gocryptfs -init -q -passfile /s/gocryptfs-in/old /s/gocryptfs/cipher > /dev/null
""")

D["kubectx"] = dict(
    state="/s/kubectx", cwd="/s/kubectx-in",
    op="/opt/bin/kubectx staging",
    env="export KUBECONFIG=/s/kubectx/config",
    seed=r"""
rm -rf /s/kubectx /s/kubectx-in && mkdir -p /s/kubectx /s/kubectx-in /s/aux/home/.kube
cat > /s/kubectx/config <<'Y'
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://prod.example.invalid:6443
    certificate-authority-data: Y2EtcHJvZA==
  name: prod
- cluster:
    server: https://staging.example.invalid:6443
    certificate-authority-data: Y2Etc3RhZ2luZw==
  name: staging
contexts:
- context: {cluster: prod, user: prod-admin}
  name: prod
- context: {cluster: staging, user: staging-admin}
  name: staging
current-context: prod
users:
- name: prod-admin
  user: {token: placeholder-prod-credential}
- name: staging-admin
  user: {token: placeholder-staging-credential}
Y
""")

D["tofu"] = dict(
    state="/s/tofu", cwd="/s/tofu",
    op="tofu state rm terraform_data.b",
    seed=r"""
rm -rf /s/tofu && mkdir -p /s/tofu && cd /s/tofu
printf 'resource "terraform_data" "a" { input = "alpha" }\nresource "terraform_data" "b" { input = "beta" }\nresource "terraform_data" "c" { input = "gamma" }\n' > main.tf
TF_IN_AUTOMATION=1 tofu init -input=false > /dev/null
TF_IN_AUTOMATION=1 tofu apply -auto-approve -input=false > /dev/null
""")

D["dwarfs"] = dict(
    state="/s/dwarfs", cwd="/s/dwarfs-in",
    op="mkdwarfs -i /s/dwarfs/photos.dwarfs -o /s/dwarfs/photos.dwarfs --recompress -f -N 1 -l 3",
    seed=r"""
rm -rf /s/dwarfs /s/dwarfs-in && mkdir -p /s/dwarfs /s/dwarfs-in/src
i=0; while [ $i -lt 40 ]; do head -c 4000 /dev/zero | tr '\0' "$(printf '\\%03o' $((65 + i % 26)))" > /s/dwarfs-in/src/img$i.raw; i=$((i+1)); done
mkdwarfs -i /s/dwarfs-in/src -o /s/dwarfs/photos.dwarfs -N 1 -l 1 > /dev/null 2>&1
""")

D["flatpak"] = dict(
    state="/s/flatpak", cwd="/s/flatpak",
    op="flatpak override --user --env=GTK_THEME=Adwaita:dark --nofilesystem=home org.example.Notes",
    env="export XDG_DATA_HOME=/s/flatpak/data",
    seed=r"""
rm -rf /s/flatpak && mkdir -p /s/flatpak/data/flatpak/overrides
printf '[Context]\nfilesystems=~/Documents/notes;\n\n[Environment]\nNOTES_SYNC=1\n' > /s/flatpak/data/flatpak/overrides/org.example.Notes
""")

D["podman"] = dict(
    state="/s/podman", cwd="/s/podman",
    op="podman system connection default work",
    env="export XDG_CONFIG_HOME=/s/podman/config",
    seed=r"""
rm -rf /s/podman && mkdir -p /s/podman/config/containers
printf '{"Connection":{"Default":"home","Connections":{"home":{"URI":"ssh://me@home.example.invalid:22/run/podman/podman.sock","Identity":"/s/aux/home/.ssh/id_home"},"work":{"URI":"ssh://me@work.example.invalid:22/run/podman/podman.sock","Identity":"/s/aux/home/.ssh/id_work"}}},"Farm":{}}\n' > /s/podman/config/containers/podman-connections.json
""")

D["electrum"] = dict(
    state="/s/electrum", cwd="/s/electrum-in",
    # The address is fixed by the wallet below, restored from a fixed Electrum seed so every
    # seed.sh gives the same wallet and the same first address. The seed was generated for this
    # run by `electrum make_seed` in the box and has never held funds: it is test data.
    op="electrum --offline -D /s/electrum -w /s/electrum/wallets/default_wallet setlabel bc1qpu8p9cz3nna0qlaw86v39ljxarwy7fgmc0fter groceries",
    seed=r"""
rm -rf /s/electrum /s/electrum-in && mkdir -p /s/electrum /s/electrum-in
electrum --offline -D /s/electrum restore "rare theme weasel regular medal follow save already pigeon glow nerve smoke" > /dev/null
""")

D["transmission"] = dict(
    state="/s/transmission", cwd="/s/transmission-in",
    op="transmission-edit -a https://tracker2.example.invalid/announce /s/transmission/linux-isos.torrent",
    seed=r"""
rm -rf /s/transmission /s/transmission-in && mkdir -p /s/transmission /s/transmission-in/payload
i=0; while [ $i -lt 20 ]; do head -c 30000 /dev/zero | tr '\0' x > /s/transmission-in/payload/part$i.bin; i=$((i+1)); done
transmission-create -o /s/transmission/linux-isos.torrent -t https://tracker1.example.invalid/announce /s/transmission-in/payload > /dev/null
""")

D["hcloud"] = dict(
    state="/s/hcloud", cwd="/s/hcloud",
    op="/opt/bin/hcloud context use work",
    env="export HCLOUD_CONFIG=/s/hcloud/cli.toml",
    seed=r"""
rm -rf /s/hcloud && mkdir -p /s/hcloud
printf 'active_context = "home"\n\n[[contexts]]\n  name = "home"\n  token = "placeholder-home-credential"\n\n[[contexts]]\n  name = "work"\n  token = "placeholder-work-credential"\n' > /s/hcloud/cli.toml
""")

D["doctl"] = dict(
    state="/s/doctl", cwd="/s/doctl",
    op="doctl auth switch --context work --config /s/doctl/config.yaml",
    seed=r"""
rm -rf /s/doctl && mkdir -p /s/doctl
printf 'access-token: placeholder-default-credential\ncontext: default\nauth-contexts:\n  work: placeholder-work-credential\n' > /s/doctl/config.yaml
""")

D["argocd"] = dict(
    state="/s/argocd", cwd="/s/argocd",
    op="argocd context work --config /s/argocd/config",
    seed=r"""
rm -rf /s/argocd /s/aux/home/.config/argocd && mkdir -p /s/argocd /s/aux/home/.config/argocd
printf 'contexts:\n- name: home\n  server: argocd.home.example.invalid\n  user: home\n- name: work\n  server: argocd.work.example.invalid\n  user: work\ncurrent-context: home\nservers:\n- grpc-web-root-path: ""\n  server: argocd.home.example.invalid\n- grpc-web-root-path: ""\n  server: argocd.work.example.invalid\nusers:\n- auth-token: placeholder-home-credential\n  name: home\n- auth-token: placeholder-work-credential\n  name: work\n' > /s/argocd/config
chmod 600 /s/argocd/config
""")

D["kubecm"] = dict(
    state="/s/kubecm", cwd="/s/kubecm",
    op="/opt/bin/kubecm delete staging --config /s/kubecm/config",
    seed=D["kubectx"]["seed"].replace("/s/kubectx", "/s/kubecm"))

D["minikube"] = dict(
    # MINIKUBE_HOME holds .minikube/; the state root is its config directory alone, because
    # .minikube/logs/audit.json gains a timestamped line per command (the first gate's red).
    state="/s/minikube/.minikube/config", cwd="/s/minikube",
    op="/opt/bin/minikube config set memory 6144",
    env="export MINIKUBE_HOME=/s/minikube",
    seed=r"""
rm -rf /s/minikube && mkdir -p /s/minikube/.minikube/config
printf '{\n    "cpus": 4,\n    "driver": "docker",\n    "memory": 4096\n}\n' > /s/minikube/.minikube/config/config.json
""")

D["babel"] = dict(
    state="/s/babel", cwd="/s/babel",
    op="pybabel update -i messages.pot -d translations",
    seed=r"""
rm -rf /s/babel && mkdir -p /s/babel/translations/ja/LC_MESSAGES /s/babel/translations/fr/LC_MESSAGES && cd /s/babel
hdr='msgid ""\nmsgstr ""\n"Project-Id-Version: demo 1.0\\n"\n"POT-Creation-Date: 2026-09-01 00:00+0000\\n"\n"MIME-Version: 1.0\\n"\n"Content-Type: text/plain; charset=utf-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n'
printf "$hdr"'msgid "Hello"\nmsgstr ""\n\nmsgid "Save"\nmsgstr ""\n\nmsgid "Delete"\nmsgstr ""\n' > messages.pot
printf "$hdr"'msgid "Hello"\nmsgstr "こんにちは"\n\nmsgid "Save"\nmsgstr "保存"\n\nmsgid "Quit"\nmsgstr "終了"\n' > translations/ja/LC_MESSAGES/messages.po
printf "$hdr"'msgid "Hello"\nmsgstr "Bonjour"\n\nmsgid "Save"\nmsgstr "Enregistrer"\n' > translations/fr/LC_MESSAGES/messages.po
""")

D["luarocks"] = dict(
    state="/s/luarocks", cwd="/s/luarocks",
    op="luarocks config --scope user rocks_trees.1.root /s/luarocks/tree",
    env="export LUAROCKS_CONFIG=/s/luarocks/config-5.4.lua",
    seed=r"""
rm -rf /s/luarocks && mkdir -p /s/luarocks/tree
printf 'rocks_servers = {\n   "https://luarocks.org"\n}\nrocks_trees = {\n   { name = "user", root = "/s/aux/home/.luarocks" }\n}\nvariables = {\n   LUA_INCDIR = "/usr/include/lua5.4"\n}\n' > /s/luarocks/config-5.4.lua
""")

D["bibtex-tidy"] = dict(
    state="/s/bibtex", cwd="/s/bibtex",
    op="bibtex-tidy refs.bib --modify --sort",
    seed=r"""
rm -rf /s/bibtex && mkdir -p /s/bibtex
printf '@article{knuth1984,\n  title={Literate Programming},\n  author={Knuth, Donald E.},\n  journal={The Computer Journal},\n  year={1984}\n}\n\n@book{abelson1996,\n title = {Structure and Interpretation of Computer Programs},\n author = {Abelson, Harold and Sussman, Gerald Jay},\n year = 1996, publisher={MIT Press}\n}\n' > /s/bibtex/refs.bib
""")

D["talosctl"] = dict(
    # The client keys are generated in the box by each seed and never written to the repository.
    state="/s/talos", cwd="/s/talos-in",
    op="/opt/bin/talosctl --talosconfig /s/talos/config config context work",
    seed=r"""
rm -rf /s/talos /s/talos-in && mkdir -p /s/talos /s/talos-in && cd /s/talos-in
talosctl gen config home https://10.0.0.1:6443 --output-types talosconfig -o /s/talos/config > /dev/null 2>&1
talosctl gen config work https://10.0.0.2:6443 --output-types talosconfig -o /s/talos-in/work > /dev/null 2>&1
talosctl --talosconfig /s/talos/config config merge /s/talos-in/work > /dev/null 2>&1
talosctl --talosconfig /s/talos/config config context home > /dev/null 2>&1
""")


def main():
    out = HERE / "defines"
    for name, d in D.items():
        p = out / name
        p.mkdir(parents=True, exist_ok=True)
        (p / "seed.sh").write_text("set -eu\n" + d["seed"].lstrip("\n"))
        (p / "sideeye.toml").write_text(
            f'[world]\nstate = "{d["state"]}"\n\n[define]\noperation = "{d["op"]}"\ncwd       = "{d["cwd"]}"\n'
            + (f'apparatus = {d["apparatus"]}\n' if "apparatus" in d else ""))
        if "env" in d:
            (p / "env.sh").write_text(d["env"] + "\n")
    print(len(D), "defines:", " ".join(D))


main()
