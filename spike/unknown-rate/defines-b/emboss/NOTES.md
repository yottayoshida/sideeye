# emboss — define (explored)

Debian description: "European molecular biology open software suite";
implemented-in::c, scope::suite (100+ command-line binaries). man seqret:
"seqret - Reads and writes (returns) sequences", synopsis
`seqret ... -sequence seqall ... -outseq seqoutall` — a file-in, file-out
transformer, the suite's canonical retrieval tool.

Local-file state, documented non-interactive writer → define. One
representative operation per the uniform protocol: `seqret` copying a
FASTA sequence file to a new file inside the state directory (`-auto`
suppresses the interactive prompting EMBOSS tools otherwise do — the
suite-wide qualifier). Choosing one binary out of a suite is exactly the
"representative operation" trade the rules section documents.
