# One broken state per leg of CANDIDATES.md 2.4, each breaking that leg alone, on the completed state.
LEGS="a b c d"
S=/s/mb
byid() { grep -l "Message-ID: <$2@" $S/$1/cur/* $S/$1/new/* 2>/dev/null; }
break_a() { f=$(byid far four); rm -f $f; }
break_b() { f=$(byid near two); cp "$f" $S/near/new/1999.9.dup; }
break_c() { for side in far near; do f=$(byid $side two); rm -f $f; done; }
break_d() { f=$(byid near one); mv "$f" "${f%S}"; }
