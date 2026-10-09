set -eu
# A 64x64 grey JPEG made by oiiotool (the same package), with no caption; iconvert --inplace
# adds one (lab 1: writes photo.jpg.tmp.jpg, unlinks photo.jpg, renames the temporary over it).
rm -rf /s/oiio && mkdir -p /s/oiio
oiiotool --pattern constant:color=0.5,0.5,0.5 64x64 3 -o /s/oiio/photo.jpg > /s/oiio-seed.log 2>&1
[ -s /s/oiio/photo.jpg ]
