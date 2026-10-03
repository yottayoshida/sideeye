set -eu
rm -rf /s/samtools /s/samtools-in && mkdir -p /s/samtools /s/samtools-in && cd /s/samtools-in
{ printf '@HD\tVN:1.6\tSO:unsorted\n@SQ\tSN:chr1\tLN:1000\n@RG\tID:rg1\tSM:sampleA\n'
  i=0; while [ $i -lt 50 ]; do printf 'r%d\t0\tchr1\t%d\t60\t10M\t*\t0\t0\tACGTACGTAC\tIIIIIIIIII\tRG:Z:rg1\n' $i $((i*10+1)); i=$((i+1)); done; } > a.sam
samtools view -C --output-fmt-option no_ref=1 -o /s/samtools/a.cram a.sam
samtools view -H /s/samtools/a.cram | sed 's/sampleA/sampleB/' > new.hdr
