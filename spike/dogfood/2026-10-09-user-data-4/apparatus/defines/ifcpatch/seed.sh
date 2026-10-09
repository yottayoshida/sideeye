set -eu
# A small IFC4 model with fixed GlobalIds (make_model.py); `ifcpatch -i model.ifc -r Optimise` with no
# -o writes the patched model back over its input (lab 15: model.ifc.<n>.tmp opened O_TRUNC, renamed
# over model.ifc, no fsync). ifcpatch.log lands in the cwd, outside --state.
rm -rf /s/ifc /s/ifc-in && mkdir -p /s/ifc /s/ifc-in
/opt/py/bin/python3 /ap/defines/ifcpatch/make_model.py /s/ifc/model.ifc > /s/ifc-seed.log 2>&1
grep -q IFCWALL /s/ifc/model.ifc
