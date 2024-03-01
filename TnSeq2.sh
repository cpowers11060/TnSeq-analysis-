#!/bin/bash
#SBATCH -t 10:00:00
#SBATCH --nodes=1 --ntasks-per-node=1
#SBATCH --mem=24g
#SBATCH --export=NONE
#SBATCH --mail-user=thpalma@uri.edu
#SBATCH --mail-type=END,FAIL
#This requires fqgrep (https://github.com/indraniel/fqgrep)
#module load cutadapt/1.9.1-foss-2017a-Python-2.7.13

module load fqgrep/0.4.4-foss-2019b
module load SAMtools/0.1.20-GCC-8.3.0
module load Bowtie2/2.4.1-GCC-8.3.0
module load flexbar/3.5.0-foss-2019b
module load cutadapt/2.8-GCCcore-8.3.0-Python-3.7.4

usage () {
  echo "usage: $0 [-g <path to genome files>] <pfx> "
  echo "Required parameters:"
  echo "-g     The location of the genome you're using (PA14)"
  echo "must load these modules prior to using script:
        python/2.7, cutadapt/1.8.1, bowtie2/2.3.2"
  echo "To load modules: module load python/2.7 , etc."

  echo ""
  echo "The required parameters must precede the file prefix for your sequence file:"
  echo "  (e.g. if your sequence file is named condition1.fastq,"
  echo "   the prefix is \"condition1\")"
  echo ""
  echo "Example:"
  echo "$0 -g $HOME/ref_genome/PA14/PA14 condition1"
}

# Read in the important options
while getopts ":g:" option; do
  case "$option" in
          g)  GENOME="$OPTARG" ;;
    h)  # it's always useful to provide some help
        usage
        exit 0
        ;;
    :)  echo "Error: -$option requires an argument"
        usage
        exit 1
        ;;
    ?)  echo "Error: unknown option -$option"
        usage
        exit 1
        ;;
  esac
done
shift $(( OPTIND - 1 ))

# Do some error checking to make sure parameters are defined
if [ -z "$GENOME" ]; then
  echo "Error: you must specify an assembly using -g"
  usage
  exit 1
fi

# Give the usage if there aren't enough parameters
if [ $# -lt 1 ] ; then
  echo "you must provide a file prefix for analysis"
  usage
  exit 1
fi

PREFIX=$1
BOWTIEREF=$GENOME

echo "Performing TnSeq analysis on $PREFIX..."
echo "TnSeq processing stats for $PREFIX" > $PREFIX-TnSeq.txt
echo "Total sequences: " >> $PREFIX-TnSeq.txt
egrep -c '^@' $PREFIX.fastq >> $PREFIX-TnSeq.txt


# IRs
echo "$PREFIX: Removing C-tail..."
#Modify the -m flag depending on you sequence leght. This is currently based on 60 bp reads.
cutadapt -a C{9} -m 20 -o $PREFIX.trim.fastq $PREFIX.fastq >$PREFIX-cutadapt-report.txt

# Map and convert - feel free to change bowtie2 parameters yourself
echo "$PREFIX: Mapping with Bowtie2..."
echo "Bowtie2 report:" >> $PREFIX-TnSeq.txt
bowtie2 --end-to-end -p 16 -a -x $GENOME -U $PREFIX.trim.fastq -S $PREFIX.sam 2>> $PREFIX-TnSeq.txt
grep '^@' $PREFIX.sam > $PREFIX-mapped.sam
cat $PREFIX.sam | grep -v '^@' | awk -F "\t" '(and($2, 0x4) != 0x4)' | sort -u -k1,1 >> $PREFIX-mapped.sam
echo "Number of reads mapping at high enough score:" >> $PREFIX-TnSeq.txt
cat $PREFIX-mapped.sam | wc -l >> $PREFIX-TnSeq.txt
echo "$PREFIX: Tallying mapping results..."
grep -v '^@' $PREFIX-mapped.sam | awk -F "\t" 'and($2, 0x100) != 0x100 {if (and($2, 0x10) != 0x10) print $4; else print $4+length($10)}' | grep '[0-9]' | sort | uniq -c | sort -n -r > $PREFIX-sites.txt
echo "Number of insertion sites identified:" >> $PREFIX-TnSeq.txt
wc -l $PREFIX-sites.txt >> $PREFIX-TnSeq.txt
echo "Most frequent sites:" >> $PREFIX-TnSeq.txt
head -10 $PREFIX-sites.txt >> $PREFIX-TnSeq.txt

# Sort output, cleanup
echo "$PREFIX: Cleaning up..."
mkdir $PREFIX 2> /dev/null
mv $PREFIX-cutadapt-report.txt $PREFIX/
mv $PREFIX-TnSeq.txt $PREFIX/
mv $PREFIX.sam $PREFIX/
mv $PREFIX-mapped.sam $PREFIX/
mv $PREFIX-sites.txt $PREFIX/
