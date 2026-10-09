set -eu
rm -rf /s/fits /s/fits-in && mkdir -p /s/fits /s/fits-in
python3 -c "import numpy as np; from astropy.io import fits; h=fits.PrimaryHDU(np.arange(4096,dtype='int16').reshape(64,64)); h.header['OBSERVER']='night-1'; t=fits.ImageHDU(np.ones((32,32),dtype='float32'),name='FLAT'); fits.HDUList([h,t]).writeto('/s/fits/obs.fits')"
# astropy's own switch for no memory map (its configuration, [io.fits] use_memmap): fitscheck -w updated
# the file through a shared mapping (unsupported_syscall_observed, 2026-10-05).
mkdir -p "$HOME/.astropy/config" && printf '[io.fits]\nuse_memmap = False\n' > "$HOME/.astropy/config/astropy.cfg"
