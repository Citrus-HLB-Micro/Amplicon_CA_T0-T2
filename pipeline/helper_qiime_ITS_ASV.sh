#!/usr/bin/bash -l
#SBATCH --job-name=ITS_analysis
#SBATCH --output=logs/ITS_analysis_output.%A.log
#SBATCH --error=logs/ITS_analysis_error.%A.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --time=7-0:00:00
#SBATCH --mem=150G

CPU=$SLURM_CPUS_PER_TASK
if [ -z $CPU ]; then
    CPU=1
fi

QIIMEDB=/srv/projects/db/UNITE/qiime
OUTDIR=qiime_ITS_ASV
mkdir -p $OUTDIR $OUTDIR/export
###########################################
# ITS Analysis Pipeline for OTU
###########################################

# Primers
# 5'-GAACCWGCGGARGGATCA-3'
# 5'-GCTGCGTTCTTCATCGATGC-3'

# Create a manifest file for importing

# Define the output file
output_file="manifest.tsv"

# Write the header to the output file
echo -e "sample-id\tforward-absolute-filepath\treverse-absolute-filepath" > $output_file

# Loop through all forward read files
for i in ITS/*R1_001.fastq.gz; do
    sample_id=$(basename $i | cut -d'_' -f1)
    # Extract the sample ID by removing the unwanted part
    #sample_id="${i/_L001_R1_001.fastq.gz/}"
    # Define the forward and reverse file paths
    forward_filepath="$PWD/$i"
    reverse_filepath="$PWD/${i/_R1_001.fastq.gz/_R2_001.fastq.gz}"

    # Modify the sample ID by removing "_L001_R1_001" and "_L001_R2_001" for the reverse read
    #sample_id="${sample_id/_[^_]+_L001_R1/}"
    
    # Write the sample ID and file paths to the output file
    echo -e "$sample_id\t$forward_filepath\t$reverse_filepath" >> $output_file
done

echo "Manifest file created: $output_file"

module load qiime2/2024.10-amplicon

# Import sequences with the manifest

if [ ! -s $OUTDIR/paired-end-demux.qza ]; then
  qiime tools import \
    --type 'SampleData[PairedEndSequencesWithQuality]' \
    --input-path manifest.tsv \
    --output-path $OUTDIR/paired-end-demux.qza \
    --input-format PairedEndFastqManifestPhred33V2
fi

if [ ! -s $OUTDIR/paired-end-demux.qza ]; then
	echo "could not create paired end artifact"
	exit
fi

# ITSXpress trimming
if [ ! -s $OUTDIR/trimmed_exact.qza ]; then
    qiime itsxpress trim-pair-output-unmerged \
	  --i-per-sample-sequences $OUTDIR/paired-end-demux.qza \
	  --p-region ITS1 \
	  --p-taxa F \
	  --p-cluster-id 1.0 \
	  --p-threads $CPU \
	  --o-trimmed $OUTDIR/trimmed_exact.qza 
fi
if [ ! -s $OUTDIR/trimmed_exact.qza ]; then
    echo "could not create trimmed artifact"
    exit
fi

# Summarize demultiplexed sequences
qiime demux summarize \
  --i-data $OUTDIR/trimmed_exact.qza \
  --o-visualization $OUTDIR/reads_trimmed_summary.qzv


#  '04_denoise' 
if [ ! -s $OUTDIR/04_denoise/representative_sequences.qza ]; then
    qiime dada2 denoise-paired \
	  --i-demultiplexed-seqs $OUTDIR/trimmed_exact.qza \
	  --p-trunc-len-r 0 \
	  --p-trunc-len-f 0 \
	  --output-dir $OUTDIR/04_denoise \
	  --p-n-threads $CPU
fi

if [ ! -s $OUTDIR/04_denoise/representative_sequences.qza ]; then
    echo "could not find denoise results in $OUTDIR/04_denoise"
    exit
fi

# List files in the 04_denoise directory
ls $OUTDIR/04_denoise

# Export all QIIME artifacts (.qza files) in the 04_denoise directory
for i in $OUTDIR/04_denoise/*.qza; do
    echo "exporting data for $i"
    if [ -f "$i" ]; then
        qiime tools export --input-path "$i" --output-path "$i.export"
    fi
done

# Convert the feature table BIOM file to TSV format
biom convert -i $OUTDIR/04_denoise/table.qza.export/feature-table.biom -o $OUTDIR/04_denoise/table.qza.export/feature-table.biom.tsv --to-tsv

# Display the first few lines of the exported stats.tsv file
if [ -f $OUTDIR/04_denoise/denoising_stats.qza.export/stats.tsv ]; then
    echo "Contents of stats.tsv:"
    head $OUTDIR/04_denoise/denoising_stats.qza.export/stats.tsv
else
    echo "stats.tsv not found."
    exit
fi

# Display the first few lines of the exported dna-sequences.fasta file
if [ -f $OUTDIR/04_denoise/representative_sequences.qza.export/dna-sequences.fasta ]; then
    echo "Contents of dna-sequences.fasta:"
    head $OUTDIR/04_denoise/representative_sequences.qza.export/dna-sequences.fasta
else
    echo "$OUTDIR/dna-sequences.fasta not found."
fi

# Count the number of sequences in dna-sequences.fasta
if [ -f $OUTDIR/04_denoise/representative_sequences.qza.export/dna-sequences.fasta ]; then
    echo "Number of sequences in dna-sequences.fasta:"
    grep -c ">" $OUTDIR/04_denoise/representative_sequences.qza.export/dna-sequences.fasta
else
    echo "$OUTDIR/dna-sequences.fasta not found."
fi

###############
# '05_taxonomy'

# Ensure the output directory exists

DBVERSION=ver10_dynamic_04.04.2024_dev
# include singletons
#DBVERSION=ver10_dynamic_s_04.04.2024_dev

qiime feature-classifier classify-sklearn \
  --i-classifier $QIIMEDB/${DBVERSION}-classifier.qza \
  --i-reads $OUTDIR/04_denoise/representative_sequences.qza \
  --output-dir $OUTDIR/05_taxonomy_bayesianclassfier
  
qiime tools export \
  --input-path $OUTDIR/05_taxonomy_bayesianclassifier/classification.qza \
  --output-path $OUTDIR/05_taxonomy_bayesianclassifier/export

cut -f2 $OUTDIR/05_taxonomy_bayesianclassfier/export/taxonomy.tsv | sort | uniq -c | sort -n -r | head

################################################ OR
qiime feature-classifier classify-consensus-blast \
  --i-query $OUTDIR/representative_sequences.qza \
  --i-reference-taxonomy "$QIIMEDB/${DBVERSION}-taxonomy.qza" \
  --i-reference-reads "$QIIMEDB/${DBVERSION}-sequences.qza" \
  --output-dir $OUTDIR/05_taxonomy \
  --p-perc-identity 0.80 \
  --p-maxaccepts 1 
  
###############  

qiime tools export \
  --input-path $OUTDIR/05_taxonomy/classification.qza \
  --output-path $OUTDIR/05_taxonomy/export


cut -f2 $OUTDIR/05_taxonomy/export/taxonomy.tsv | sort | uniq -c | sort -n -r | head

# Phylogenetic analysis
qiime phylogeny align-to-tree-mafft-fasttree \
  --i-sequences $OUTDIR/04_denoise/representative_sequences.qza \
  --o-alignment $OUTDIR/aligned-rep-seqs.qza \
  --o-masked-alignment $OUTDIR/masked-aligned-rep-seqs.qza \
  --o-tree $OUTDIR/unrooted-tree.qza \
  --o-rooted-tree $OUTDIR/rooted-tree.qza


# Export tree
qiime tools export \
  --input-path $OUTDIR/rooted-tree.qza \
  --output-path $OUTDIR/exported_files

qiime taxa barplot \
 --i-table $OUTDIR/04_denoise/table.qza \
 --i-taxonomy $OUTDIR/05_taxonomy/classification.qza \
 --m-metadata-file metadata_ITS.tsv \
 --o-visualization $OUTDIR/taxa-bar-plots.qzv

qiime taxa barplot \
 --i-table $OUTDIR/04_denoise/table.qza \
 --i-taxonomy $OUTDIR/05_taxonomy_bayesianclassifier/classification.qza \
 --m-metadata-file metadata_ITS.tsv \
 --o-visualization $OUTDIR/taxa-bar-plots_bayesianclassifier.qzv

# Alpha rarefaction
qiime diversity alpha-rarefaction \
  --i-table $OUTDIR/04_denoise/table.qza \
  --i-phylogeny $OUTDIR/rooted-tree.qza \
  --p-max-depth 20000 \
  --m-metadata-file metadata_ITS.tsv \
  --o-visualization $OUTDIR/alpha-rarefaction.qzv


# Prepare taxonomy for BIOM
sed 's/Feature ID/#OTUID/g' "$OUTDIR/05_taxonomy/export/taxonomy.tsv" | \
sed 's/Taxon/taxonomy/g' | \
sed 's/Consensus/confidence/g' > "$OUTDIR/05_taxonomy/export/reformat.taxonomy.tsv"

# Prepare taxonomy for BIOM
sed 's/Feature ID/#OTUID/g' "$OUTDIR/05_taxonomy_bayesianclassifier/export/taxonomy.tsv" | \
sed 's/Taxon/taxonomy/g' | \
sed 's/Consensus/confidence/g' > "$OUTDIR/05_taxonomy_bayesianclassifier/export/reformat.taxonomy.tsv"

# Add metadata to BIOM
biom add-metadata \
  -i "$OUTDIR/04_denoise/table.qza.export/feature-table.biom" \
  -o "$OUTDIR/04_denoise/table.qza.export/taxonomy.feature-table.biom" \
  --observation-metadata-fp "$OUTDIR/05_taxonomy/export/reformat.taxonomy.tsv" \
  --sc-separated taxonomy

# Add metadata to BIOM
biom add-metadata \
  -i "$OUTDIR/04_denoise/table.qza.export/feature-table.biom" \
  -o "$OUTDIR/04_denoise/table.qza.export/taxonomy_bayesianclassifier.feature-table.biom" \
  --observation-metadata-fp "$OUTDIR/05_taxonomy_bayesianclassifier/export/reformat.taxonomy.tsv" \
  --sc-separated taxonomy

# Convert BIOM to TSV
biom convert \
  -i "$OUTDIR/04_denoise/table.qza.export/taxonomy.feature-table.biom" \
  -o "$OUTDIR/04_denoise/table.qza.export/taxonomy.feature-table.biom.tsv" \
  --to-tsv \
  --header-key taxonomy

# Convert BIOM to TSV
biom convert \
  -i "$OUTDIR/04_denoise/table.qza.export/taxonomy_bayesianclassifier.feature-table.biom" \
  -o "$OUTDIR/04_denoise/table.qza.export/taxonomy_bayesianclassifier.feature-table.biom.tsv" \
  --to-tsv \
  --header-key taxonomy

