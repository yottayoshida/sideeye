#!/bin/sh
# fitscheck with the mode it accepts, and pymol through the system python its package installs into.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
mkdir -p /lab/fits /lab/pm /lab/pm-in
python3 -c "import numpy as np; from astropy.io import fits; h=fits.PrimaryHDU(np.arange(4096,dtype='int16').reshape(64,64)); h.header['OBSERVER']='night-1'; t=fits.ImageHDU(np.ones((32,32),dtype='float32'),name='FLAT'); fits.HDUList([h,t]).writeto('/lab/fits/obs.fits')"
sum /lab/fits
x fitscheck -k standard -w /lab/fits/obs.fits
sum /lab/fits; x fitscheck /lab/fits/obs.fits
printf 'fragment ala\nfragment gly\nsave /lab/pm/model.pse\n' > /lab/pm-in/make.pml
x /usr/bin/python3 -m pymol -cq /lab/pm-in/make.pml
sum /lab/pm
printf 'set bg_rgb, white\ncolor red, ala\nsave /lab/pm/model.pse\n' > /lab/pm-in/edit.pml
x /usr/bin/python3 -m pymol -cq /lab/pm/model.pse /lab/pm-in/edit.pml
sum /lab/pm
