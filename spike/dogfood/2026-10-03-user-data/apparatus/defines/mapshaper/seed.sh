set -eu
rm -rf /s/mapshaper /s/mapshaper-in && mkdir -p /s/mapshaper /s/mapshaper-in
cat > /s/mapshaper-in/in.json <<'J'
{"type":"FeatureCollection","features":[
{"type":"Feature","properties":{"name":"a","n":1},"geometry":{"type":"Point","coordinates":[139.7,35.6]}},
{"type":"Feature","properties":{"name":"b","n":2},"geometry":{"type":"Point","coordinates":[135.5,34.7]}},
{"type":"Feature","properties":{"name":"c","n":3},"geometry":{"type":"Point","coordinates":[141.3,43.0]}}]}
J
cd /s/mapshaper-in && mapshaper -i in.json -o format=shapefile /s/mapshaper/a.shp > /dev/null 2>&1
