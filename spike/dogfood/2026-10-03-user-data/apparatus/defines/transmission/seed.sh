set -eu
rm -rf /s/transmission /s/transmission-in && mkdir -p /s/transmission /s/transmission-in/payload
i=0; while [ $i -lt 20 ]; do head -c 30000 /dev/zero | tr '\0' x > /s/transmission-in/payload/part$i.bin; i=$((i+1)); done
transmission-create -o /s/transmission/linux-isos.torrent -t https://tracker1.example.invalid/announce /s/transmission-in/payload > /dev/null
