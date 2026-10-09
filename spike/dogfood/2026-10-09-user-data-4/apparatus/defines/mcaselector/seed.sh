set -eu
# A world directory with one region file of six chunks written by make_region.py (three with
# InhabitedTime 100, three with 5000) and the empty poi/ and entities/ directories MCA Selector
# looks for. The JVM's temporary file goes to java.io.tmpdir (/tmp, not TMPDIR), outside --state.
rm -rf /s/mc && mkdir -p /s/mc/world/region /s/mc/world/poi /s/mc/world/entities /s/mc-in
python3 /ap/defines/mcaselector/make_region.py /s/mc/world/region 6 > /s/mc-seed.log
[ -s /s/mc/world/region/r.0.0.mca ]
