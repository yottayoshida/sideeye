# bogofilter-sqlite — define (explored)

Same tool and documentation as bogofilter-bdb (one Debian source, two
storage backends); this package's binary is `bogofilter-sqlite` and the
wordlist under `-d` is a sqlite database. Selected independently by the
predicate, kept as its own trial deliberately: the buku row in
docs/target-classes.md is exactly the lesson that a sqlite-backed store
answers the built-in byte comparison differently than a plain-file store.
Same setup/operation shape as bogofilter-bdb.
