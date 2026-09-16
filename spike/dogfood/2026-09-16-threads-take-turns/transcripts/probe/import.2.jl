JL 0001 tid=25 open64 /w/st2/lib/library.db flags=0x88042 write=1 fd=3
JL 0002 tid=25 create rc=0 new=ffffa222f160
JL 0003 tid=26 started creator=25 self=ffffa222f160
JL 0004 tid=25 create rc=0 new=ffffa191f160
JL 0005 tid=27 started creator=25 self=ffffa191f160
JL 0006 tid=25 create rc=0 new=ffffa110f160
JL 0007 tid=28 started creator=25 self=ffffa110f160
JL 0008 tid=27 open64 /w/st2/lib/library.db flags=0x88042 write=1 fd=4
JL 0009 tid=27 open64 /w/st2/lib/library.db-journal flags=0x88042 write=1 fd=5
JL 0010 tid=27 pwrite64 fd=5 n=512 off=0
JL 0011 tid=27 pwrite64 fd=5 n=4 off=512
JL 0012 tid=27 pwrite64 fd=5 n=4096 off=516
JL 0013 tid=27 pwrite64 fd=5 n=4 off=4612
JL 0014 tid=27 pwrite64 fd=5 n=4 off=4616
JL 0015 tid=27 pwrite64 fd=5 n=4096 off=4620
JL 0016 tid=27 pwrite64 fd=5 n=4 off=8716
JL 0017 tid=27 pwrite64 fd=5 n=4 off=8720
JL 0018 tid=27 pwrite64 fd=5 n=4096 off=8724
JL 0019 tid=27 pwrite64 fd=5 n=4 off=12820
JL 0020 tid=27 fdatasync fd=5
JL 0021 tid=27 pwrite64 fd=5 n=12 off=0
JL 0022 tid=27 fdatasync fd=5
JL 0023 tid=27 pwrite64 fd=4 n=4096 off=0
JL 0024 tid=27 pwrite64 fd=4 n=4096 off=4096
JL 0025 tid=27 pwrite64 fd=4 n=4096 off=20480
JL 0026 tid=27 fdatasync fd=4
JL 0027 tid=27 close fd=5
JL 0028 tid=27 unlink /w/st2/lib/library.db-journal
JL 0029 tid=28 open64 /w/st2/lib/library.db flags=0x88042 write=1 fd=5
JL 0030 tid=28 open64 /w/st2/lib/library.db-journal flags=0x88042 write=1 fd=6
JL 0031 tid=28 pwrite64 fd=6 n=512 off=0
JL 0032 tid=28 pwrite64 fd=6 n=4 off=512
JL 0033 tid=28 pwrite64 fd=6 n=4096 off=516
JL 0034 tid=28 pwrite64 fd=6 n=4 off=4612
JL 0035 tid=28 pwrite64 fd=6 n=4 off=4616
JL 0036 tid=28 pwrite64 fd=6 n=4096 off=4620
JL 0037 tid=28 pwrite64 fd=6 n=4 off=8716
JL 0038 tid=28 fdatasync fd=6
JL 0039 tid=28 pwrite64 fd=6 n=12 off=0
JL 0040 tid=28 fdatasync fd=6
JL 0041 tid=28 pwrite64 fd=5 n=4096 off=0
JL 0042 tid=28 pwrite64 fd=5 n=4096 off=4096
JL 0043 tid=28 fdatasync fd=5
JL 0044 tid=28 close fd=6
JL 0045 tid=28 unlink /w/st2/lib/library.db-journal
JL 0046 tid=25 join-enter target=ffffa110f160
JL 0047 tid=25 join-return target=ffffa110f160 rc=0
JL 0048 tid=25 join-enter target=ffffa222f160
JL 0049 tid=25 join-return target=ffffa222f160 rc=0
JL 0050 tid=25 join-enter target=ffffa191f160
JL 0051 tid=25 join-return target=ffffa191f160 rc=0
JL 0052 tid=25 close fd=5
JL 0053 tid=25 close fd=4
JL 0054 tid=25 close fd=3
