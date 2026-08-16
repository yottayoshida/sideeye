# audiolink — wall W2 (no local-file state)

Debian description: "makes managing and searching for music easier";
debtags carry protocol::db:mysql. man audiolink: "audiolink assists you in
creating a configuration file ... and creating the MySQL database and
tables which the AudioLink programs, alfilldb(1) and alsearch(1) use."

The state this tool writes lives in a MySQL server, not in a local file
directory — outside the product's declared domain (README: state in one
directory). W2.
