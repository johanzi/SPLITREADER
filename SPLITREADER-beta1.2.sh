#!/bin/bash 

#############################################
#                                           #  
#                                           #
#            SPLITREADER beta1.2            #
#                                           #
#                                           # 
#############################################

##Questions or comments to quadrana(ar)biologie.ens.fr

#$1 ->  bam file (we'll take care of the rest)
# $1 Could be  path to a bam file. Extract the in name (ex. /path/to/name.bam --> extract 
in=$1
#in=test_data/test.bam
tmp=`basename $in`
BAMname=${tmp%.bam}

#TE-> should be indicated in the first column of the TE-information.txt file located in listDir
#TSD -> should be indicated in the second column of the TE-information.txt file located in listDir


#############################################################
#IN THE FOLLOWING VARIABLE YOU CAN PROVIDE THE MINIMUM READ LEGTH. By default this is 100nt
LENGTH=100

#### If not specified, the program will calculate the longest read


#############################################################
#IN THE FOLLOWING VARIABLE YOU CAN PROVIDE THE MINIMUM NUMBER OF SPLIT-READS IN EACH EXTRIMITY OF THE TE. By default is 5 reads
READS=3
maxcov=60
#### If not specified, the program calculate it. To this end, the program calculates the minimum number of reads as 3 standard deviation under the mean whole genome coverage
####This value should be at least 3, if not, it is forced to be 3
 
#############################################################

#############################################################
#IN THE FOLLOWING VARIABLE YOU CAN EXPLICITE THE NUMBER OF THREADS YOU WANT TO USE FOR MAPPING. By default is 2 threads
CORES=2
#############################################################


# Path to configure (by default it is the current directory)


OutputDir=. # this notation "./" usually causes errors. Ex: OutputDir/file.out --> .//file.out no such file or directory!

#list of TEs to analyze
listDir=./TE_list

#Folder containing the Bowtie2 index for each TE sequence
SequencesDir=./TEs_indexes

#Bowtie2 index for reference genome
GenomeIndexFile=/projects/genomes/Arabidopsis_thaliana/TAIR10/Bowtie2_indexes/TAIR10

#Coordinates of inner pericentromeres 
#Cent=./centromeres.bed

#Bowtie2 executable path
Bowtie2Dir=/usr/local/bin
#samtools executable path
samtoolsDir=/usr/local/bin/
#bedtools executable path
bedtoolsdir=/usr/local/bin
#picard tools executable path
picardDir=/groups/a2e/Leandro/scripts/picard-tools-1.99


# PID of this batch
IDPID=$$
# Temporary directory
TmpDir=./QD-$IDPID
mkdir -p $TmpDir
  
#Extracting unmapped reads
echo "Extracting unmapped reads from $in"
pe=`$samtoolsDir/samtools view -c -f 1 $in | awk '{print $1}'` 

$samtoolsDir/samtools view -f 4 -u $in > $TmpDir/$BAMname.bam 2>> $TmpDir/log.txt

if [ -z "$pe" ]
then

java -jar $picardDir/SamToFastq.jar INPUT=$TmpDir/$BAMname.bam FASTQ=$TmpDir/$BAMname.fastq 2>> $TmpDir/log.txt
else

java -jar $picardDir/SamToFastq.jar INPUT=$TmpDir/$BAMname.bam FASTQ=$TmpDir/$BAMname.1.fastq SECOND_END_FASTQ=$TmpDir/$BAMname.2.fastq 2>> $TmpDir/log.txt

cat $TmpDir/$BAMname.1.fastq $TmpDir/$BAMname.2.fastq > $TmpDir/$BAMname.fastq

rm -f $TmpDir/$BAMname.1.fastq
rm -f $TmpDir/$BAMname.2.fastq
fi


    
#end=`wc -l $listDir/TE-information.txt | awk '{print $1}'`

##############
#Starting the SPLITREADER pipeline for each TE in the TE-indormation.txt file
cat $listDir/TE-information.txt | while read line ; do
    STARTTIME=$(date +%s)

    IDPID2=$PPID
    TmpResultsDir=$TmpDir/results-$IDPID2
    mkdir -p $TmpResultsDir

    TE=`echo $line| awk '{print $1}'`
    TSD=`echo $line| awk '{print $2}'`
   
   echo "##### RUNNING SPLIT-READ ANALYSIS ON $TE ######"    
   echo ""
  ############# 
   
   
   
   # Selecting split-reads by mapping the unmapped reads over TE extremities
   
   echo "Selecting split-reads"
   
    $Bowtie2Dir/bowtie2 -x $SequencesDir/$TE -U $TmpDir/$BAMname.fastq -S $TmpResultsDir/$BAMname-$TE.sam --local --very-sensitive --threads $CORES 2>> $TmpDir/log.txt 
   
        
       
    #############################################################
     ###filter soft-clipped reads with at least 20nt softclipped at 5' or 3' read's end 
    $samtoolsDir/samtools view -F 4 -S $TmpResultsDir/$BAMname-$TE.sam | awk '$6~/^[2-8][0-9]S/ || $6~/[2-8][0-9]S$/ {print $1}'| sed 's/\/2$//' | sed 's/\/1$//' | awk '{print $1"/1""\n"$1"/2"}' |sort -u > $TmpResultsDir/reads.name 2>> $TmpDir/log.txt

    java -jar $picardDir/FilterSamReads.jar INPUT=$TmpResultsDir/$BAMname-$TE.sam FILTER=includeReadList READ_LIST_FILE=$TmpResultsDir/reads.name OUTPUT=$TmpResultsDir/$BAMname-$TE-selected.sam 2>> $TmpResultsDir/log.txt 2>> $TmpDir/log.txt

    java -jar $picardDir/SamToFastq.jar INPUT=$TmpResultsDir/$BAMname-$TE-selected.sam FASTQ=$TmpResultsDir/$BAMname-$TE-split.fastq 2>> $TmpResultsDir/log.txt 2>> $TmpDir/log.txt

    ################################
  
   
    rm -f $TmpResultsDir/$BAMname-$TE-split.sam

    ###Estimating max read size (If necessary)
    
    if [ -z "$LENGTH" ]
     then
      LENGTH=`awk 'NR%4 == 2 {print length($0)}' $TmpResultsDir/$BAMname-$TE-split.fastq | sort | tail -1 `  
      length=$((LENGTH-20))
      echo "Maximum Read legth: $LENGTH [Estimated] "
      else
      length=$((LENGTH-20))
      echo "Maximum Read legth: $LENGTH [User defined] "
     fi
    
         
    ###Recursive split-reads mapping
    # step 1 for 3' read extremity: begining the loop.
    
      
   echo "Mapping 5' split-reads on reference genome"
   echo "Progresssion: ["
  
  $Bowtie2Dir/bowtie2 -x $GenomeIndexFile -U $TmpResultsDir/$BAMname-$TE-split.fastq -S $TmpResultsDir/$BAMname-$TE-local.sam --local --very-sensitive --threads $CORES --quiet 2>> $TmpDir/log.txt
   
  $samtoolsDir/samtools view -H -S $TmpResultsDir/$BAMname-$TE-local.sam > $TmpResultsDir/$BAMname-$TE-split-local-up.sam 2>> $TmpDir/log.txt
  cat $TmpResultsDir/$BAMname-$TE-split-local-up.sam > $TmpResultsDir/$BAMname-$TE-split-local-down.sam 
  
  $samtoolsDir/samtools view -F 4 -S $TmpResultsDir/$BAMname-$TE-local.sam | awk '$6~/^[0-9][0-9]S/ {print $0}' >> $TmpResultsDir/$BAMname-$TE-split-local-down.sam 2>> $TmpDir/log.txt
  $samtoolsDir/samtools view -F 4 -S $TmpResultsDir/$BAMname-$TE-local.sam | awk '$6~/[0-9][0-9]S$/ {print $0}' >> $TmpResultsDir/$BAMname-$TE-split-local-up.sam 2>> $TmpDir/log.txt
  
  $samtoolsDir/samtools view -Sbu -q 5 $TmpResultsDir/$BAMname-$TE-split-local-down.sam | $samtoolsDir/samtools sort - $TmpResultsDir/$BAMname-$TE-split-local-down 2>> $TmpDir/log.txt
  $samtoolsDir/samtools view -Sbu -q 5 $TmpResultsDir/$BAMname-$TE-split-local-up.sam | $samtoolsDir/samtools sort - $TmpResultsDir/$BAMname-$TE-split-local-up 2>> $TmpDir/log.txt
 
   rm -f $TmpResultsDir/$BAMname-$TE-split-local-up.sam
   rm -f $TmpResultsDir/$BAMname-$TE-split-local-down.sam
   rm -f $TmpResultsDir/$BAMname-$TE-local.sam
  

   
   
   
   ############################################
   
   length=$(($((LENGTH/2))-1))
   
  $Bowtie2Dir/bowtie2 -x $GenomeIndexFile -U $TmpResultsDir/$BAMname-$TE-split.fastq -S $TmpResultsDir/$BAMname-$TE-splitjunction-5-$length.sam --un $TmpResultsDir/$BAMname-$TE-split-5-$length -5 $length --mp 13 --rdg 8,5 --rfg 8,5 --very-sensitive --quiet 2>> $TmpDir/log.txt
    #$samtoolsDir/samtools view -Sbu -F 4  $TmpResultsDir/$BAMname-$TE-splitjunction-5-$length.sam | $samtoolsDir/samtools sort - $TmpResultsDir/$BAMname-$TE-splitjunction-5-$length
    rm -f $TmpResultsDir/$BAMname-$TE-splitjunction-5-$length.sam
     
    for ((i=$((length+1)); $i<$((LENGTH-18)); i=$i+1)); do
    echo -n "|" 
      previous=$(($i-1));

      $Bowtie2Dir/bowtie2 -x $GenomeIndexFile -U $TmpResultsDir/$BAMname-$TE-split-5-$previous -S $TmpResultsDir/$BAMname-$TE-splitjunction-5-$i.sam --un $TmpResultsDir/$BAMname-$TE-split-5-$i -5 $i --mp 13 --rdg 8,5 --rfg 8,5 --very-sensitive --quiet 2>> $TmpDir/log.txt
      $samtoolsDir/samtools view -Sbu -F 4 $TmpResultsDir/$BAMname-$TE-splitjunction-5-$i.sam | $samtoolsDir/samtools sort - $TmpResultsDir/$BAMname-$TE-splitjunction-5-$i 2>> $TmpDir/log.txt
      rm -f $TmpResultsDir/$BAMname-$TE-splitjunction-5-$i.sam
      rm -f $TmpResultsDir/$BAMname-$TE-split-5-$previous
    done

    
  $Bowtie2Dir/bowtie2 -x $GenomeIndexFile -U $TmpResultsDir/$BAMname-$TE-split.fastq -S $TmpResultsDir/$BAMname-$TE-splitjunction-3-$length.sam --un $TmpResultsDir/$BAMname-$TE-split-3-$length -3 $length --mp 13 --rdg 8,5 --rfg 8,5 --very-sensitive --quiet 2>> $TmpDir/log.txt
    #$samtoolsDir/samtools view -Sbu -F 4  $TmpResultsDir/$BAMname-$TE-splitjunction-3-$length.sam | $samtoolsDir/samtools sort - $TmpResultsDir/$BAMname-$TE-splitjunction-3-$length
    rm -f $TmpResultsDir/$BAMname-$TE-splitjunction-3-$length.sam
     
    for ((i=$((length+1)); $i<$((LENGTH-18)); i=$i+1)); do
    echo -n "|" 
      previous=$(($i-1));

      $Bowtie2Dir/bowtie2 -x $GenomeIndexFile -U $TmpResultsDir/$BAMname-$TE-split-3-$previous -S $TmpResultsDir/$BAMname-$TE-splitjunction-3-$i.sam --un $TmpResultsDir/$BAMname-$TE-split-3-$i -3 $i --mp 13 --rdg 8,5 --rfg 8,5 --very-sensitive --quiet 2>> $TmpDir/log.txt
      $samtoolsDir/samtools view -Sbu -F 4 $TmpResultsDir/$BAMname-$TE-splitjunction-3-$i.sam | $samtoolsDir/samtools sort - $TmpResultsDir/$BAMname-$TE-splitjunction-3-$i 2>> $TmpDir/log.txt
      rm -f $TmpResultsDir/$BAMname-$TE-splitjunction-3-$i.sam
      rm -f $TmpResultsDir/$BAMname-$TE-split-3-$previous
    done
echo -n "]"
echo -e "\n"

    # Post-treatment:
    
    # merge all the recursive mappings from either the 3' and 5'
        
   # rm -f $TmpResultsDir/$BAMname-$TE-split.fastq

    # Merging and sorting bam files
    $samtoolsDir/samtools merge -f -u $TmpResultsDir/$BAMname-$TE-split-5.bam $TmpResultsDir/$BAMname-$TE-splitjunction-5-*.bam 2>> $TmpDir/log.txt
    $samtoolsDir/samtools merge -f -u $TmpResultsDir/$BAMname-$TE-split-3.bam $TmpResultsDir/$BAMname-$TE-splitjunction-3-*.bam 2>> $TmpDir/log.txt
    $samtoolsDir/samtools sort $TmpResultsDir/$BAMname-$TE-split-5.bam $TmpResultsDir/$BAMname-$TE-split-5 2>> $TmpDir/log.txt
    $samtoolsDir/samtools sort $TmpResultsDir/$BAMname-$TE-split-3.bam $TmpResultsDir/$BAMname-$TE-split-3 2>> $TmpDir/log.txt
    
    rm -f $TmpResultsDir/$BAMname-$TE-splitjunction-[35]-*.bam
    
    # merge reads that were cliped at the 3' and mapped in the + strand with those clipped at the 5' and mapped on the - strand
    # merge reads that were cliped at the 3' and mapped in the - strand with those clipped at the 5' and mapped on the + strand
    
      echo "Searching for reads clusters..."
    $samtoolsDir/samtools view -F 16 -bh $TmpResultsDir/$BAMname-$TE-split-5.bam > $TmpResultsDir/$BAMname-$TE-split-5+.bam 2>> $TmpDir/log.txt 2>> $TmpDir/log.txt
    $samtoolsDir/samtools view -f 16 -bh $TmpResultsDir/$BAMname-$TE-split-5.bam > $TmpResultsDir/$BAMname-$TE-split-5-.bam 2>> $TmpDir/log.txt 2>> $TmpDir/log.txt
    $samtoolsDir/samtools view -F 16 -bh $TmpResultsDir/$BAMname-$TE-split-3.bam > $TmpResultsDir/$BAMname-$TE-split-3+.bam 2>> $TmpDir/log.txt 2>> $TmpDir/log.txt
    $samtoolsDir/samtools view -f 16 -bh $TmpResultsDir/$BAMname-$TE-split-3.bam > $TmpResultsDir/$BAMname-$TE-split-3-.bam 2>> $TmpDir/log.txt 2>> $TmpDir/log.txt

    
    #Merge the 5' and 3' clusters to create the downstream and upstream cluster

   $samtoolsDir/samtools merge -f -u $TmpResultsDir/$BAMname-$TE-up.bam $TmpResultsDir/$BAMname-$TE-split-5-.bam $TmpResultsDir/$BAMname-$TE-split-3+.bam $TmpResultsDir/$BAMname-$TE-split-local-up.bam 2>> $TmpDir/log.txt
   $samtoolsDir/samtools merge -f -u $TmpResultsDir/$BAMname-$TE-down.bam $TmpResultsDir/$BAMname-$TE-split-5+.bam $TmpResultsDir/$BAMname-$TE-split-3-.bam $TmpResultsDir/$BAMname-$TE-split-local-down.bam 2>> $TmpDir/log.txt
   samtools sort $TmpResultsDir/$BAMname-$TE-down.bam $TmpResultsDir/$BAMname-$TE-down 2>> $TmpDir/log.txt
   samtools sort $TmpResultsDir/$BAMname-$TE-up.bam $TmpResultsDir/$BAMname-$TE-up 2>> $TmpDir/log.txt
   
   

    #Calculate the coverage over mapped regions - filter regions according to minimum and maximum read-depth
    $samtoolsDir/samtools depth $TmpResultsDir/$BAMname-$TE-up.bam | awk -v M=$maxcov '$3<(M) {print $1 "\t" $2 "\t"$2"\t"$3}' > $TmpResultsDir/$BAMname-$TE-up.bed 2>> $TmpDir/log.txt
    $samtoolsDir/samtools depth $TmpResultsDir/$BAMname-$TE-down.bam | awk -v M=$maxcov ' $3<(M) {print $1 "\t" $2 "\t"$2"\t"$3}' > $TmpResultsDir/$BAMname-$TE-down.bed 2>> $TmpDir/log.txt

    #merge cluster of covered regions - filter out clusters that are longer than read-length
    sort -k 1,1 -k2,2n $TmpResultsDir/$BAMname-$TE-up.bed | $bedtoolsdir/mergeBed -i stdin -c 4 -o max > $TmpResultsDir/$BAMname-$TE-up-merge.bed 2>> $TmpDir/log.txt
    sort -k 1,1 -k2,2n $TmpResultsDir/$BAMname-$TE-down.bed | $bedtoolsdir/mergeBed -i stdin -c 4 -o max  > $TmpResultsDir/$BAMname-$TE-down-merge.bed 2>> $TmpDir/log.txt
    
     
    rm -f $TmpResultsDir/$BAMname-$TE-down.bed
    rm -f $TmpResultsDir/$BAMname-$TE-up.bed
    
    rm -f $TmpResultsDir/$BAMname-$TE-split-5+.bam
    rm -f $TmpResultsDir/$BAMname-$TE-split-5-.bam
    rm -f $TmpResultsDir/$BAMname-$TE-split-3+.bam
    rm -f $TmpResultsDir/$BAMname-$TE-split-3-.bam
  

    #searching for overlapping clusters meeting the expected TSD size 
      echo "Searching overlaps and defining insertions..."
      
      $bedtoolsdir/intersectBed -a $TmpResultsDir/$BAMname-$TE-up-merge.bed -b $TmpResultsDir/$BAMname-$TE-down-merge.bed -wo | awk -v tsd=$TSD -v te=$TE -v rea=$READS '($6-$2)>10 && ($7-$3)>10 && $9>=tsd && ($4+$8)>=rea {print $1 "\t" $6 "\t" $3 "\t"te"\t" ($9-1)"\t"$4"\t"$8}' >> $OutputDir/$BAMname-$TE-insertion-sites.bed
      
      ###only if excluding inner pericentromeres and donnors TEs:
      #awk '$1!="" {print $0}' $SequencesDir/$TE.txt > $TmpResultsDir/$TE-donnor.txt
      #$bedtoolsdir/intersectBed -a $TmpResultsDir/$BAMname-$TE-up-merge.bed -b $TmpResultsDir/$BAMname-$TE-down-merge.bed -wo | awk -v tsd=$TSD -v te=$TE '($6-$2)>10 && ($7-$3)>10 && $9>=tsd {print $1 "\t" $6 "\t" $3 "\t"te"\t" ($9-1)"\t"$4"\t"$8}' | intersectBed -a stdin -b $TmpResultsDir/$TE-donnor.txt -v | intersectBed -a stdin -b $Cent -v >> $OutputDir/$BAMname-insertion-sites.bed

    INSERTIONS=$(wc -l $OutputDir/$BAMname-$TE-insertion-sites.bed | awk '{print $1}')
      
      echo "Split-read analyis done: $INSERTIONS putative insertions identified..."

    ###merging bam files and moving them to the output folder 
    $samtoolsDir/samtools merge -f $TmpResultsDir/$BAMname-$TE-split.bam $TmpResultsDir/$BAMname-$TE-up.bam $TmpResultsDir/$BAMname-$TE-down.bam 2>> $TmpDir/log.txt
    $samtoolsDir/samtools sort $TmpResultsDir/$BAMname-$TE-split.bam $OutputDir/$BAMname-$TE-split 2>> $TmpDir/log.txt
    $samtoolsDir/samtools index $OutputDir/$BAMname-$TE-split.bam 2>> $TmpDir/log.txt

    rm -r -f $TmpResultsDir

    ENDTIME=$(date +%s)
      echo "It takes $((ENDTIME-STARTTIME)) seconds to analyse $TE."

done

rm -r -f $TmpDir
