set -eu
rm -rf /s/rrdtool && mkdir -p /s/rrdtool/state
mkdir -p "/s/rrdtool/state"
rm -f "/s/rrdtool/state/t.rrd"
rrdtool create "/s/rrdtool/state/t.rrd" --start 1700000000 --step 60 \
  DS:v:GAUGE:120:U:U RRA:AVERAGE:0.5:1:100 RRA:MAX:0.5:5:50
rrdtool update "/s/rrdtool/state/t.rrd" 1700000060:11 1700000120:22
