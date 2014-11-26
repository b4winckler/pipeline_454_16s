#
# Makefile for 454 pipeline
#
# Usage:
#
# 1. (optional) If a fastq file is already available then you can skip this
#    step.  Instead copy (or softlink) the file to the same folder as this
#    makefile and update INFILE below to match its name, but be aware that
#    fasta headers are assumed to be of the format mentioned below.
#
#    Copy (or softlink) all sff files (may be gzipped) and corresponding
#    barcodes to the sff/ folder (see below for barcode naming convention),
#    then set PRIMER below to match the PCR primer used by your project and
#    finally generate one fastq file from all sff files with
#
#         make sff
#
# 2. Generate quality control files
#
#         make qc
#
#    Check qc files and modify MAXEE and TRUNCLEN settings below based on
#    results.
#
# 3. Run pipeline
#
#         make
#
#    to create the following files
#
#         reads.fasta           quality filtered reads
#         reads_otureps.fasta   OTU representatives
#         reads_otutab.tsv      OTU abundance table
#         reads_otutax.tsv      OTU taxonomy
#
#
# Targets:
#
# sff     Generate input file from all sff[.gz] files in sff/.  For each file
#         X.sff[.gz] there must also be a file named X-barcodes.fasta where
#         each header names the sample and the corresponding sequence is the
#         barcode for that sample.
#         This step must be run manually and is not affected by 'clean'.
#         It is also possible to put an already generated reads.fastq file in
#         the pwd to avoid generating it from sff files, but be aware that the
#         fasta headers must end with ';barcodelabel=X;', where 'X' identifies
#         the sample.
#
# qc      Run quality control on reads.fastq.
#
# qf      Run quality filter on reads.fastq.
#
# otu     Generate OTUs from qf output.
#
# tax     Taxonomic classification of OTU representatives.
#
# phy     Phylogenetic tree generation from otu output (not implemented).
#
# clean   Delete all generated files except reads.fastq.
#

# FIXME: Commands that create files by redirecting to stdout will not clean up
# after themselves if they fail which causes dependency problems as it seems
# the command succeeded based on the target file being present.


## Input parameters (modify these to match project) ##########################

# Name of the input file (see note on fasta header requirements above).  If you
# already have a fastq file you can change this to match its name.
INFILE := reads.fastq

# Path to sff files (see note on barcodes above).  Note that intermediate files
# will be placed in this folder so do not set it to a location that should be
# read-only.
SFF_PATH := sff

# Primer in sff files (must be the same for all sff files)
PRIMER := CCTACGGGNGGCWGCAG

# Maximum expected errors used in quality filtering
MAXEE := 1.0

# Truncation length used in quality filtering
TRUNCLEN := 250

# OTU identity (in range 0.0-1.0)
OTUID := 0.97

# Prefix used to label OTUs
OTULABEL := OTU_


## Server configuration (modify these to match server) #######################

THIRD_PARTY_PATH := /projects/s16/bjorn/3rdparty
USEARCH_PATH := /projects/qiime/usearch

FASTQC := /projects/qiime/FastQC/fastqc
SFF2FASTQ := /projects/s16/bjorn/seqtools/bin/sff2fastq
PYTHON := python
ZCAT := zcat
JAVA := java
USEARCH := $(USEARCH_PATH)/usearch7
UC2OTUTAB_PY := $(USEARCH_PATH)/scripts/uc2otutab.py
FASTA_NUMBER_PY := $(USEARCH_PATH)/scripts/fasta_number.py
FASTQ_STRIP_BARCODE_RELABEL2_PY := $(USEARCH_PATH)/scripts/fastq_strip_barcode_relabel2.py
GOLD_DB_PATH := $(USEARCH_PATH)/microbiomeutil-r20110519/gold.fa
RDP_CLASSIFIER_JAR := $(THIRD_PARTY_PATH)/rdp_classifier_2.10.1/dist/classifier.jar



## Below here is not meant to be configured by user ##########################

QC_TARGETS := $(patsubst %.fastq, %_fastqc.zip, $(INFILE))
QF_TARGETS := $(patsubst %.fastq, %.fasta, $(INFILE))
OTU_TARGETS := $(patsubst %.fastq, %_otureps.fasta, $(INFILE)) \
               $(patsubst %.fastq, %_otutab.tsv, $(INFILE))
TAX_TARGETS := $(patsubst %.fastq, %_otutax.tsv, $(INFILE))
SFF_FILES := $(wildcard $(SFF_PATH)/*.sff)
SFF_GZ_FILES := $(wildcard $(SFF_PATH)/*.sff.gz)
DEMULT_TARGETS := $(patsubst %.sff.gz, %_demultiplexed.fastq, $(SFF_GZ_FILES)) \
                  $(patsubst %.sff, %_demultiplexed.fastq, $(SFF_FILES)) \

ALL_TARGETS := $(QC_TARGETS) $(QF_TARGETS) $(OTU_TARGETS) $(DEMULT_TARGETS) \
               $(TAX_TARGETS)


.PHONY: all sff qc qf otu tax clean

all: qf otu tax

sff: $(DEMULT_TARGETS)
	cat $^ > $(INFILE)

qc: $(QC_TARGETS)

qf: $(QF_TARGETS)

otu: $(OTU_TARGETS)

tax: $(TAX_TARGETS)

clean:
	-rm -f $(ALL_TARGETS)


## Rule for quality control
#
# NB: FastQC automatically adds the suffix "_fastqc"
%_fastqc.zip: %.fastq
	$(FASTQC) --noextract $<


## Rule for quality filtering
#
%.fasta: %.fastq
	$(USEARCH) -fastq_filter $< -fastq_maxee $(MAXEE) \
		   -fastq_trunclen $(TRUNCLEN) -fastaout $@


## Rules for generating OTU representatives
#
# dereplicate -> sort -> cluster OTUs -> database chimera removal
#   -> sequentially label OTUs
#
%_derep.fasta: %.fasta
	$(USEARCH) -derep_fulllength $< -output $@ -sizeout

%_sort.fasta: %_derep.fasta
	$(USEARCH) -sortbysize $< -output $@ -minsize 2

%_otureps1.fasta: %_sort.fasta
	$(USEARCH) -cluster_otus $< -otus $@ -otuid $(OTUID)

%_otureps2.fasta: %_otureps1.fasta
	$(USEARCH) -uchime_ref $< -db $(GOLD_DB_PATH) -strand plus \
		   -nonchimeras $@

%_otureps.fasta: %_otureps2.fasta
	$(PYTHON) $(FASTA_NUMBER_PY) $< $(OTULABEL) > $@


## Rules for generating OTU abundance table
#
# map reads to OTU representatives -> create table
#
%_otumap.uc: %.fasta %_otureps.fasta
	$(USEARCH) -usearch_global $< -db $(word 2, $^) \
		   -strand plus -id $(OTUID) -uc $@

%_otutab.tsv: %_otumap.uc
	$(PYTHON) $(UC2OTUTAB_PY) $< > $@


## Rules for generating fastq file from one or more sff files
#
%_raw.fastq: %.sff.gz
	$(ZCAT) $< | $(SFF2FASTQ) -o $@

%_raw.fastq: %.sff
	$(SFF2FASTQ) -o $@ $<

%_demultiplexed.fastq: %_raw.fastq
	$(PYTHON) $(FASTQ_STRIP_BARCODE_RELABEL2_PY) $< $(PRIMER) \
	          $*-barcodes.fasta $(notdir $*) > $@


## Rule for generating RDP taxonomy assignments
#
%_otutax.tsv: %_otureps.fasta
	$(JAVA) -Xmx1g -jar $(RDP_CLASSIFIER_JAR) classify -o $@ $<
