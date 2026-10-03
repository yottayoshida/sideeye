Title: `-o force` can leave the input .shp empty and the rest of the shapefile unchanged

`-o force` writes each file over its input with `fs.writeFileSync` (`src/io/mapshaper-file-export.mjs` line 51 at `8e8a24e`), which truncates, then writes. If a write fails (full disk) or the process is killed in between, the file is left empty.

```
mapshaper -i in.json -o format=shapefile a.shp
(ulimit -f 0; mapshaper a.shp -each x=n*10 -o force)
```

`a.shp` is now 0 bytes (was 184), `a.shx`/`a.dbf` unchanged; the layer no longer imports. 0.7.72, Node 20, Debian 13.

A temporary file plus rename would avoid it.

Disclosure: found with [sideeye](https://github.com/yottayoshida/sideeye), my personal crash-consistency checker; written with an AI assistant (Claude), checked against the runs.
