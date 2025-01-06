#!/usr/bin/bash -l
#SBATCH -o logs/setup.log -p short -c 8 -n 1 -N 1 --mem 8gb

if [ -s config.txt ]; then
	echo "Using config.txt for variables"
else
	echo "Please create a config.txt file with the following variables:"
	echo "FASTQSOURCE=/path/to/fastq/files"
	exit 1
fi

source "config.txt"

if [[ -z $FASTQSOURCE || ! -d $FASTQSOURCE ]]; then
	echo "Please set FASTQSOURCE in config.txt to the path of the directory containing the raw fastq files"
	exit 1
fi

if [[ -z $METADATA || ! -s $METADATA ]]; then
	echo "Please set METADATA in config.txt to the path of the file with sample metdata"
	exit 1
fi


FASTQSOURCE=$(realpath $FASTQSOURCE)
for marker in 16S ITS
do
	mkdir -p $marker
	for file in $(ls ${FASTQSOURCE}/${marker}/*_${marker}_*.gz)
	do
		outname=$(basename $file | perl -p -e "s/_${marker}_(S\d+)_(R[12])_001.fastq.gz/_NoCode_L001_\$2_001.fastq.gz/")
		if [ ! -f $marker/$outname ]; then
			ln -s $file $marker/$outname
		fi
	done
	for region in CA FL
	do
		mkdir -p region_$region/$marker
		tail -n +2 $METADATA | grep -P "\t${region}_" | cut -f1 | while read sample
		do
			LEFT=${sample}_NoCode_L001_R1_001.fastq.gz
			RIGHT=${sample}_NoCode_L001_R2_001.fastq.gz
			if [[ ! -f region_${region}/${marker}/$LEFT || ! -f region_${region}/${marker}/$RIGHT ]]; then
				ln -s ../../${marker}/$LEFT ../../${marker}/$RIGHT region_${region}/${marker}
			fi
		done
		head -n 1 $METADATA > region_$region/metadata_${marker}.tsv 
		tail -n +2 $METADATA | grep -P "\t${region}_" >> region_$region/metadata_${marker}.tsv 
		# Add the control pools
		# this is a little redundant it is getting count 2x for each region but 
		# it should work
		tail -n +2 $METADATA | grep -P "^(Pos|Neg)-Pool" | cut -f1 | while read sample
		do
			LEFT=${marker}/${sample}_NoCode_L001_R1_001.fastq.gz
			RIGHT=${marker}/${sample}_NoCode_L001_R2_001.fastq.gz
			if [[ ! -f $LEFT  || ! -f $RIGHT ]]; then
				echo "ERROR: Missing Control Pool $sample ($LEFT,$RIGHT)"
				continue
			fi
			len1=$(pigz -dc $LEFT | head -n 100 | wc -l  | awk '{print $1}' )
			len2=$(pigz -dc $RIGHT | head -n 100 | wc -l | awk '{print $1}')
			if [[ $len1 == 0 || $len2 = 0 ]]; then
				echo "ERROR: Skipping Control Pool $sample as R1 ($len1) or R2 ($len2) are empty"
				continue
			fi
			tail -n +2 $METADATA | grep -P "^$sample\s+" >> region_$region/metadata_${marker}.tsv
			ln -s ../../$LEFT ../../$RIGHT region_${region}/${marker}/			
		done
	done
done
