# Amplicon data analysis for T0-T2 

* 16S
* ITS

# Setup

The script `pipeline/00_setup.sh` takes care of symlinking from a 16S and ITS folder into a master folder followed by group by individual regions (as the current split for analyses).

There is a config.txt script which sets the base folder for finding the demultiplexed and aggregated by amplicon type of all flowcells data to link in. It is organized where the filenames do not list ITS or 16S but are just the 
`SAMPLEID_BARCODE_LANE_READDIRECTION_001.fastq.gz`



```
-> 16S
--> LB102-BT1_NoCode_L001_R1_001.fastq.gz 
--> LB102-BT1_NoCode_L001_R2_001.fastq.gz
```

Run this by running
`sbatch pipeline/00_setup.sh`

It will also link in the Pos and Neg pool files, but will remove any pools that are zero length.
We need to still decide which final pools to include. 

# Run
The second script will launch ASV clustering for 16S and OTU clustering for ITS in each of the region folders. Additional helper scripts can be written but for now we assume generally running same basic OTU/ASV table creation for each region.  Inclusion/removal of pool data needs to be considered.

This launches amptk runs for the clustering which will further run dada2 for 16S ASVs or a vsearch/usearch pipeline for OTU clustering.