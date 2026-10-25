# Navidrome's settings for this define: its data folder (the database and caches) is the state, the
# music is read from outside it. Its default DbPath opens the database in WAL mode, whose -shm file
# is a shared writable mapping (ADR 0098's wall); the configuration file names the same path with
# _journal_mode=DELETE, every other parameter kept as shipped. ND_DBPATH in the environment is not
# read (measured: the debug line "Opening DataBase" still names the default), the file is. One OS
# thread for Go's scheduler.
mkdir -p /s/aux
# The scanner's and the artwork worker's own concurrency set to one (conf/configuration.go,
# DevScannerThreads and DevArtworkWorkerConcurrency): with them the full scan's writing threads fell
# from 6 to 3 under --observe supervised, not to one (transcripts/entry-s4.txt).
printf 'DbPath = "/s/nd/navidrome.db?cache=shared&_busy_timeout=15000&_journal_mode=DELETE&_foreign_keys=on&synchronous=normal"\nDevScannerThreads = 1\nDevArtworkWorkerConcurrency = 1\n' > /s/aux/navidrome.toml
export ND_CONFIGFILE=/s/aux/navidrome.toml ND_DATAFOLDER=/s/nd ND_MUSICFOLDER=/s/aux/music ND_CACHEFOLDER=/s/nd/cache \
       ND_LOGLEVEL=info ND_ENABLEINSIGHTSCOLLECTOR=false ND_SCANNER_SCHEDULE=0 GOMAXPROCS=1
