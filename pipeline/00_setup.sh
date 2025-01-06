#!/usr/bin/bash -l

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
		outname=$(basename $file | perl -p -e "s/_${marker}_S\d+_(R[12])_001.fastq.gz/_\$1.fastq.gz/")
		if [ ! -f $marker/$outname ]; then
			ln -s $file $marker/$outname
		fi
	done
	for region in CA FL
	do
		mkdir -p region_$region/$marker
		tail -n +2 $METADATA | grep -P "\t${region}_" | cut -f1 | while read sample
		do
			ln -s ../../${marker}/${sample}_R1.fastq.gz region_${region}/${marker}
			ln -s ../../${marker}/${sample}_R2.fastq.gz region_${region}/${marker}
		done
		pushd region_${region}/${marker}
		ln -s ../../${marker}/Neg-Pool*.fastq.gz ../../${marker}/Pos-Pool*.fastq.gz ./
		popd
	done
done
