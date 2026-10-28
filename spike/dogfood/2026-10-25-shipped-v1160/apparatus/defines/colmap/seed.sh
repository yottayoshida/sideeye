set -eu
# The reconstruction a user ran mapping for, in COLMAP's binary format under sparse/0 (the text model
# make_model.py writes, converted by COLMAP's own model_converter).
rm -rf /s/colmap /s/aux/colmap-txt && mkdir -p /s/colmap/sparse/0 /s/aux
python3 /ap/defines/colmap/make_model.py /s/aux/colmap-txt
/opt/bin/colmap model_converter --input_path /s/aux/colmap-txt --output_path /s/colmap/sparse/0 --output_type BIN > /s/aux/colmap-convert.log 2>&1
install -m 755 /ap/defines/colmap/check.sh /s/colmap-check.sh
