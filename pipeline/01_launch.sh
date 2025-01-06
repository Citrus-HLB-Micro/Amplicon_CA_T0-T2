#!/usr/bin/bash -l
#SBATCH -p short --out logs/01_launch.log -n 1 -N 1 -c 1 


#!/usr/bin/bash -l

if [ -s config.txt ]; then
	echo "Using config.txt for variables"
else
	echo "Please create a config.txt file with the following variables:"
	echo "FASTQSOURCE=/path/to/fastq/files"
	exit 1
fi

source "config.txt"

if [[ -z $METADATA || ! -s $METADATA ]]; then
	echo "Please set METADATA in config.txt to the path of the file with sample metdata"
	exit 1
fi

for region in CA FL
do
    pushd region_$region
    mkdir -p logs
    
    marker=16S    
    echo "Processing $marker in $region"
    RUNNAME=ECDRE_T0T2_16S_ASV_${region}
    sbatch --export=ALL,RUNNAME=$RUNNAME -o logs/${marker}_${region}.log -J ${marker}_${region} ../pipeline/helper_16S_ASV.sh 

    marker=ITS    
    echo "Processing $marker in $region"
    RUNNAME=ECDRE_T0T2_ITS_OTU_${region}
    sbatch --export=ALL,RUNNAME=$RUNNAME -o logs/${marker}_${region}.log -J ${marker}_${region} ../pipeline/helper_ITS_OTU.sh 

    popd
done
