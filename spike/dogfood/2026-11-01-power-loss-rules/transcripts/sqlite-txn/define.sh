state=/s/sq
cwd=/
marker=no
setup=''
op='sqlite3 /s/sq/ledger.db '"'"'BEGIN; UPDATE accounts SET bal = bal - 30 WHERE id = '"'"'"'"'"'"'"'"'A'"'"'"'"'"'"'"'"'; UPDATE accounts SET bal = bal + 30 WHERE id = '"'"'"'"'"'"'"'"'B'"'"'"'"'"'"'"'"'; INSERT INTO journal(src, dst, amt) VALUES('"'"'"'"'"'"'"'"'A'"'"'"'"'"'"'"'"', '"'"'"'"'"'"'"'"'B'"'"'"'"'"'"'"'"', 30); COMMIT;'"'"''
