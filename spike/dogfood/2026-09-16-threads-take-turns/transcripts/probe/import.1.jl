JL 0001 tid=18 open64 /w/st1/lib/library.db flags=0x88042 write=1 fd=3
JL 0002 tid=18 create rc=0 new=ffffaf39f160
JL 0003 tid=19 started creator=18 self=ffffaf39f160
JL 0004 tid=18 create rc=0 new=ffffaea8f160
JL 0005 tid=20 started creator=18 self=ffffaea8f160
JL 0006 tid=18 create rc=0 new=ffffae27f160
JL 0007 tid=21 started creator=18 self=ffffae27f160
JL 0008 tid=20 open64 /w/st1/lib/library.db flags=0x88042 write=1 fd=4
JL 0009 tid=20 open64 /w/st1/lib/library.db-journal flags=0x88042 write=1 fd=5
JL 0010 tid=20 pwrite64 fd=5 n=512 off=0
JL 0011 tid=20 pwrite64 fd=5 n=4 off=512
JL 0012 tid=20 pwrite64 fd=5 n=4096 off=516
JL 0013 tid=20 pwrite64 fd=5 n=4 off=4612
JL 0014 tid=20 pwrite64 fd=5 n=4 off=4616
JL 0015 tid=20 pwrite64 fd=5 n=4096 off=4620
JL 0016 tid=20 pwrite64 fd=5 n=4 off=8716
JL 0017 tid=20 pwrite64 fd=5 n=4 off=8720
JL 0018 tid=20 pwrite64 fd=5 n=4096 off=8724
JL 0019 tid=20 pwrite64 fd=5 n=4 off=12820
JL 0020 tid=20 fdatasync fd=5
JL 0021 tid=20 pwrite64 fd=5 n=12 off=0
JL 0022 tid=20 fdatasync fd=5
JL 0023 tid=20 pwrite64 fd=4 n=4096 off=0
JL 0024 tid=20 pwrite64 fd=4 n=4096 off=4096
JL 0025 tid=20 pwrite64 fd=4 n=4096 off=20480
JL 0026 tid=20 fdatasync fd=4
JL 0027 tid=20 close fd=5
JL 0028 tid=20 unlink /w/st1/lib/library.db-journal
JL 0029 tid=21 open64 /w/st1/lib/library.db flags=0x88042 write=1 fd=5
JL 0030 tid=21 open64 /w/st1/lib/library.db-journal flags=0x88042 write=1 fd=6
JL 0031 tid=21 pwrite64 fd=6 n=512 off=0
JL 0032 tid=21 pwrite64 fd=6 n=4 off=512
JL 0033 tid=21 pwrite64 fd=6 n=4096 off=516
JL 0034 tid=21 pwrite64 fd=6 n=4 off=4612
JL 0035 tid=21 pwrite64 fd=6 n=4 off=4616
JL 0036 tid=21 pwrite64 fd=6 n=4096 off=4620
JL 0037 tid=21 pwrite64 fd=6 n=4 off=8716
JL 0038 tid=21 fdatasync fd=6
JL 0039 tid=21 pwrite64 fd=6 n=12 off=0
JL 0040 tid=21 fdatasync fd=6
JL 0041 tid=21 pwrite64 fd=5 n=4096 off=0
JL 0042 tid=21 pwrite64 fd=5 n=4096 off=4096
JL 0043 tid=21 fdatasync fd=5
JL 0044 tid=21 close fd=6
JL 0045 tid=21 unlink /w/st1/lib/library.db-journal
JL 0046 tid=18 join-enter target=ffffae27f160
JL 0047 tid=18 join-return target=ffffae27f160 rc=0
JL 0048 tid=18 join-enter target=ffffaf39f160
JL 0049 tid=18 join-return target=ffffaf39f160 rc=0
JL 0050 tid=18 join-enter target=ffffaea8f160
JL 0051 tid=18 join-return target=ffffaea8f160 rc=0
JL 0052 tid=18 close fd=5
JL 0053 tid=18 close fd=4
JL 0054 tid=18 close fd=3
