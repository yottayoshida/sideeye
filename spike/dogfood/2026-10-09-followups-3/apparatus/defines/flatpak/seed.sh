set -eu
rm -rf /s/flatpak && mkdir -p /s/flatpak/data/flatpak/overrides
printf '[Context]\nfilesystems=~/Documents/notes;\n\n[Environment]\nNOTES_SYNC=1\n' > /s/flatpak/data/flatpak/overrides/org.example.Notes
