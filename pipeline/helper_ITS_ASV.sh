#!/usr/bin/bash -l

#SBATCH --time=4-0:00:00   # walltime
#SBATCH -N 1 -n 1 -c 48
#SBATCH --mem=96gb # memory 
#SBATCH --out logs/ASV_vsearch.%A.log

#QIIME DB
QIIMEDB=/srv/projects/db/UNITE/qiime
DBVERSION=ver10_dynamic_04.04.2024_dev

CPU=$SLURM_CPUS_ON_NODE # set the CPUS dynamically for the job
if [ -z $CPU ]; then # unless this is not really a slurm job
	CPU=2 # set the number of CPUs to 2
fi

module load amptk
module load usearch

if [ -z $RUNNAME ]; then
	BASE=ECDRE_ITS_ASV_$(date +'%Y%m%d')
else
	BASE=$RUNNAME
fi
#Change this to match your data folder name
INPUT=ITS

#Pre-processing steps will use `amptk illumina` command for demultiplexed PE reads
if [ ! -f $BASE.demux.fq.gz ]; then
    amptk illumina -i $INPUT --merge_method vsearch -f ITS1-F -r ITS2 --require_primer off -o $BASE \
	  --usearch usearch9  --rescue_forward on --primer_mismatch 2 -l 250 --cpus $CPU --cleanup
fi

if [ ! -f $BASE.otu_table.txt ]; then
    amptk dada2 -i $BASE.demux.fq.gz -o ${BASE} --uchime_ref ITS --usearch usearch9 -e 0.9 --cpus $CPU
fi

if [ ! -f $BASE.ASVs.taxonomy.txt ]; then
	amptk taxonomy -f $BASE.ASVs.fa -i $BASE.otu_table.txt -d ITS1
	amptk taxonomy -f $BASE.cluster.otus.fa -i $BASE.cluster.otu_table.txt -d ITS1
fi

if [ ! -f $BASE.ASV_taxonomy_bayesianclassifier/classification.qza ]; then

    module load qiime2/2024.10-amplicon
    perl -p -e 'tr/a-z/A-Z/' $BASE.ASVs.fa > $BASE.ASVs.uc.fa
    perl -p -e 'tr/a-z/A-Z/' $BASE.cluster.otus.fa > $BASE.cluster.otus.uc.fa
    qiime tools import \
	  --input-path $BASE.ASVs.uc.fa \
	  --output-path $BASE.ASVs.qza \
	  --type 'FeatureData[Sequence]'
    qiime tools import \
	  --input-path $BASE.cluster.otus.uc.fa \
	  --output-path $BASE.cluster.otus.qza \
	  --type 'FeatureData[Sequence]'
    
    #BAYESIAN CLASSIFIER
    ##ASVs
    OUTDIR=./$BASE.ASVs_taxonomy_bayesianclassifier # for now save in the current dir
    mkdir -p $OUTDIR
    qiime feature-classifier classify-sklearn \
 	  --i-classifier $QIIMEDB/${DBVERSION}-classifier.qza \
  	  --i-reads $BASE.ASVs.qza \
  	  --output-dir $OUTDIR

    qiime tools export \
	  --input-path $OUTDIR/classification.qza \
	  --output-path $OUTDIR/export

    ##OTUs
    OUTDIR=./$BASE.OTUs_taxonomy_bayesianclassifier # for now save in the current dir
    mkdir -p $OUTDIR
    qiime feature-classifier classify-sklearn \
 	  --i-classifier $QIIMEDB/${DBVERSION}-classifier.qza \
  	  --i-reads $BASE.cluster.otus.qza \
  	  --output-dir $OUTDIR
    qiime tools export \
	  --input-path $OUTDIR/classification.qza \
	  --output-path $OUTDIR/export
       
    
    #BLAST CLASSIFIER
    ##ASVs
    OUTDIR=./$BASE.ASVs_taxonomy_BLAST # for now save in the current dir
    mkdir -p $OUTDIR
    qiime feature-classifier classify-consensus-blast \
	  --i-query $BASE.ASVs.qza \
	  --i-reference-taxonomy "$QIIMEDB/${DBVERSION}-taxonomy.qza" \
	  --i-reference-reads "$QIIMEDB/${DBVERSION}-sequences.qza" \
	  --output-dir $OUTDIR \
	  --p-perc-identity 0.80 \
	  --p-maxaccepts 1
	  
    qiime tools export \
	  --input-path $OUTDIR/classification.qza \
	  --output-path $OUTDIR/export

    ## OTUs
    OUTDIR=./$BASE.OTUs_taxonomy_BLAST # for now save in the current dir
    mkdir -p $OUTDIR
    qiime feature-classifier classify-consensus-blast \
	  --i-query $BASE.cluster.otus.qza \
	  --i-reference-taxonomy "$QIIMEDB/${DBVERSION}-taxonomy.qza" \
	  --i-reference-reads "$QIIMEDB/${DBVERSION}-sequences.qza" \
	  --output-dir $OUTDIR
	  --p-perc-identity 0.80 \
	  --p-maxaccepts 1

    qiime tools export \
	  --input-path $OUTDIR/classification.qza \
	  --output-path $OUTDIR/export

fi
