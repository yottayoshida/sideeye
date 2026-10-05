set -eu
rm -rf /s/rio /s/rio-in && mkdir -p /s/rio /s/rio-in
python3 -c "import numpy as np, rasterio; from rasterio.transform import from_origin; a=np.arange(10000,dtype='uint16').reshape(100,100); d=rasterio.open('/s/rio/a.tif','w',driver='GTiff',height=100,width=100,count=1,dtype='uint16',transform=from_origin(139.0,36.0,0.01,0.01)); d.write(a,1); d.close()"
