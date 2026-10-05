#!/bin/sh
# Seeds and operations, plain runs: the third build's six.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
mkdir -p /lab

echo "##### stripe"
TAILN=30 x stripe config --help
mkdir -p /s/aux/home/.config/stripe
printf '[default]\n  color = "on"\n  device_name = "laptop"\n  test_mode_api_key = "sk_test_aaaa"\n  test_mode_pub_key = "pk_test_aaaa"\n\n[work]\n  test_mode_api_key = "sk_test_bbbb"\n' > /s/aux/home/.config/stripe/config.toml
x stripe config --set color off
sum /s/aux/home/.config/stripe; cat /s/aux/home/.config/stripe/config.toml

echo "##### infracost"
TAILN=25 x infracost configure set --help
x infracost configure set currency EUR
x infracost configure set api_key ico-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
sum /s/aux/home/.config/infracost; for f in /s/aux/home/.config/infracost/*; do echo "== $f"; cat "$f"; done

echo "##### meltano"
cd /lab
TAILN=6 x meltano init proj --no-usage-stats
cd /lab/proj 2>/dev/null && { sum /lab/proj | head; TAILN=20 x meltano config meltano list; x meltano config meltano set send_anonymous_usage_stats false; sum /lab/proj | head; cat meltano.yml; }
cd /

echo "##### astropy fitscheck"
TAILN=30 x fitscheck --help
mkdir -p /lab/fits
python3 -c "import numpy as np; from astropy.io import fits; h=fits.PrimaryHDU(np.arange(4096,dtype='int16').reshape(64,64)); h.header['OBSERVER']='night-1'; t=fits.ImageHDU(np.ones((32,32),dtype='float32'),name='FLAT'); fits.HDUList([h,t]).writeto('/lab/fits/obs.fits')" && echo made
sum /lab/fits
x fitscheck --checksum both --write /lab/fits/obs.fits
sum /lab/fits; x fitscheck /lab/fits/obs.fits

echo "##### pymol"
mkdir -p /lab/pm /lab/pm-in
printf 'fragment ala\nfragment gly\nsave /lab/pm/model.pse\n' > /lab/pm-in/make.pml
x pymol -cq /lab/pm-in/make.pml
sum /lab/pm
printf 'set bg_rgb, white\ncolor red, ala\nsave /lab/pm/model.pse\n' > /lab/pm-in/edit.pml
x pymol -cq /lab/pm/model.pse /lab/pm-in/edit.pml
sum /lab/pm

echo "##### azure-cli"
export AZURE_CORE_COLLECT_TELEMETRY=0 AZURE_CONFIG_DIR=/lab/az
mkdir -p /lab/az; printf '[core]\noutput = json\ncollect_telemetry = false\n\n[defaults]\nlocation = japaneast\ngroup = rg-home\n' > /lab/az/config
x az config set core.output=table
sum /lab/az; cat /lab/az/config
