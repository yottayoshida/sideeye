# httrack — wall W2 (state on a server)

Debian description: "Copy websites to your computer (Offline browser)";
`implemented-in::c`, `use::downloading`/`use::storing`, `works-with::text`.
Installed 3.49.6-1 in the trixie image. Freshness: no tracked file outside the
selection names it (`b2-author.sh`, 2026-09-18).

man httrack: "httrack allows you to download a World Wide Web site from the
Internet to a local directory, building recursively all directories, getting
HTML, images, and other files from the server to your computer." Every example
names a site on the network (`httrack www.someweb.com/bob/`), and the modes
that change the local mirror — `-w` mirror, `-g` get files, `-i` continue,
`--update` — all fetch from a server first. The mirror directory is local, but
no server exists inside the sweep's container and a define that starts one in
`setup.sh` would be apparatus beyond the uniform protocol (a second process
the run would have to account for). No server, no mirror: the first group's
goobook shape (state behind a remote account). W2.
