JL 0001 tid=32 open64 /w/st3/lib/library.db flags=0x88042 write=1 fd=3
JL 0002 tid=32 create rc=0 new=ffff7eb2f160
JL 0003 tid=33 started creator=32 self=ffff7eb2f160
JL 0004 tid=32 create rc=0 new=ffff7e31f160
JL 0005 tid=34 started creator=32 self=ffff7e31f160
JL 0006 tid=32 create rc=0 new=ffff7da0f160
JL 0007 tid=35 started creator=32 self=ffff7da0f160
JL 0008 tid=34 open64 /w/st3/lib/library.db flags=0x88042 write=1 fd=4
JL 0009 tid=34 open64 /w/st3/lib/library.db-journal flags=0x88042 write=1 fd=5
JL 0010 tid=34 pwrite64 fd=5 n=512 off=0
JL 0011 tid=34 pwrite64 fd=5 n=4 off=512
JL 0012 tid=34 pwrite64 fd=5 n=4096 off=516
JL 0013 tid=34 pwrite64 fd=5 n=4 off=4612
JL 0014 tid=34 pwrite64 fd=5 n=4 off=4616
JL 0015 tid=34 pwrite64 fd=5 n=4096 off=4620
JL 0016 tid=34 pwrite64 fd=5 n=4 off=8716
JL 0017 tid=34 pwrite64 fd=5 n=4 off=8720
JL 0018 tid=34 pwrite64 fd=5 n=4096 off=8724
JL 0019 tid=34 pwrite64 fd=5 n=4 off=12820
JL 0020 tid=34 fdatasync fd=5
JL 0021 tid=34 pwrite64 fd=5 n=12 off=0
JL 0022 tid=34 fdatasync fd=5
JL 0023 tid=34 pwrite64 fd=4 n=4096 off=0
JL 0024 tid=34 pwrite64 fd=4 n=4096 off=4096
JL 0025 tid=34 pwrite64 fd=4 n=4096 off=20480
JL 0026 tid=34 fdatasync fd=4
JL 0027 tid=34 close fd=5
JL 0028 tid=34 unlink /w/st3/lib/library.db-journal
JL 0029 tid=35 open64 /w/st3/lib/library.db flags=0x88042 write=1 fd=5
JL 0030 tid=35 open64 /w/st3/lib/library.db-journal flags=0x88042 write=1 fd=6
JL 0031 tid=35 pwrite64 fd=6 n=512 off=0
JL 0032 tid=35 pwrite64 fd=6 n=4 off=512
JL 0033 tid=35 pwrite64 fd=6 n=4096 off=516
JL 0034 tid=35 pwrite64 fd=6 n=4 off=4612
JL 0035 tid=35 pwrite64 fd=6 n=4 off=4616
JL 0036 tid=35 pwrite64 fd=6 n=4096 off=4620
JL 0037 tid=35 pwrite64 fd=6 n=4 off=8716
JL 0038 tid=35 fdatasync fd=6
JL 0039 tid=35 pwrite64 fd=6 n=12 off=0
JL 0040 tid=35 fdatasync fd=6
JL 0041 tid=35 pwrite64 fd=5 n=4096 off=0
JL 0042 tid=35 pwrite64 fd=5 n=4096 off=4096
JL 0043 tid=35 fdatasync fd=5
JL 0044 tid=35 close fd=6
JL 0045 tid=35 unlink /w/st3/lib/library.db-journal
JL 0046 tid=32 join-enter target=ffff7da0f160
JL 0047 tid=32 join-return target=ffff7da0f160 rc=0
JL 0048 tid=32 join-enter target=ffff7eb2f160
JL 0049 tid=32 join-return target=ffff7eb2f160 rc=0
JL 0050 tid=32 join-enter target=ffff7e31f160
JL 0051 tid=32 join-return target=ffff7e31f160 rc=0
JL 0052 tid=32 close fd=5
JL 0053 tid=32 close fd=4
JL 0054 tid=32 close fd=3
