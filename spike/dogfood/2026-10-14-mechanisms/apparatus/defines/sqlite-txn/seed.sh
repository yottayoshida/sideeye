set -eu
rm -rf /s/sq /s/sq-aux && mkdir -p /s/sq /s/sq-aux
sqlite3 /s/sq/ledger.db "CREATE TABLE accounts(id TEXT PRIMARY KEY, bal INTEGER NOT NULL);
CREATE TABLE journal(n INTEGER PRIMARY KEY, src TEXT, dst TEXT, amt INTEGER);
CREATE INDEX accounts_bal ON accounts(bal);
INSERT INTO accounts VALUES('A', 100), ('B', 50);"
install -m 755 /ap/defines/sqlite-txn/check.sh /s/sq-aux/check.sh
