#!/usr/bin/bash -l
#SBATCH -p short -c 2 --mem 8gb -N 1 -n 1 

mkdir -p logs
# data also available from gcp at
# gs://stajichlab-ecdre/Amplicon/Distribute/Year_T0-T2
IN=/bigdata/stajichlab/shared/projects/ECDRE/Amplicon/data/Years_T0-T2/CA_Only/ITS
CTL=/bigdata/stajichlab/shared/projects/ECDRE/Amplicon/data/Years_T0-T2/Controls/ITS
OUT=input
mkdir -p $OUT
for file in $(ls $IN/*_ITS_*.gz $CTL/*_ITS_*.gz)
do
	outname=$(basename $file | perl -p -e 's/_ITS_S\d+_(R[12])_001.fastq.gz/_$1.fastq.gz/')
	ln -s $file $OUT/$outname
done
