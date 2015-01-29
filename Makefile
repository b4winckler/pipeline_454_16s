#
# Makefile for 454 pipeline
#
# Executive summary - modify MAXEE, TRUNCLEN and SAMPLE_METADATA below then
# (runs pipeline, writes log, and prints time it took):
#
#    time make 2>&1 | tee -a log-$(date "+%Y_%m_%d-%H_%M_%S").txt
#
# Usage:
#
# 1. (optional) If a fastq file is already available then you can skip this
#    step.  Instead copy (or softlink) the fastq file to the same folder as
#    this makefile and update INFILE below to match its name, but be aware that
#    fasta headers are assumed to be of the format mentioned below.
#
#    If no fastq file is available, copy (or softlink) all sff files (may be
#    gzipped) and corresponding barcodes to the sff/ folder (see below for
#    barcode naming convention), then set PRIMER below to match the PCR primer
#    used by your project and finally generate one fastq file from all sff
#    files with
#
#         make sff
#
# 2. Generate quality control files
#
#         make qc
#
#    Modify MAXEE and TRUNCLEN settings below based on qc results which can be
#    found in the following files
#
#         reads_fastqc.zip
#         reads_fastq_stats.txt
#
# 3. Copy file with sample metadata to ./mapping.txt (see expected format
#    below) and run pipeline
#
#         make
#
#    to create the following files
#
#         reads.fasta           quality filtered reads
#         reads_otureps.fasta   OTU representatives
#         reads_otutab.tsv      OTU abundance table
#         reads_otutax.tsv      OTU taxonomy
#         reads_otuphy.tre      phylogenetic tree of OTU representatives
#         reads.biom            BIOM format OTU table, metadata and taxonomy
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
# phy     Phylogenetic tree generation from OTU representatives.
#
# biom    Create a biom format file with OTU table and taxonomy.  The file
#         named by SAMPLE_METADATA must be in the same folder as this makefile.
#         This file contains metadata for each sample with one row per sample
#         and items separated by tabs.  The first item is the sample name and
#         remaining items are arbitrary.  The first row must be a header naming
#         the items and this row must start with a # sign.
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

# PCR primer in sff files (must be the same for all sff files)
PRIMER := CCTACGGGNGGCWGCAG

# Maximum expected errors used for quality filtering
MAXEE := 1.0

# Truncation length used for quality filtering
TRUNCLEN := 250

# OTU identity (in range 0.0-1.0)
OTUID := 0.97

# Prefix used to label OTUs
OTULABEL := OTU_

# Tab-separated file with meta data for each sample
SAMPLE_METADATA := mapping.txt


## Server configuration (modify these to match server) #######################

# Number of parallel process to use for steps that support it
NUMJOBS := 10

THIRD_PARTY_PATH := /projects/s16/bjorn/3rdparty
USEARCH_PATH := /projects/qiime/usearch

FASTQC := /projects/qiime/FastQC/fastqc
SFF2FASTQ := /projects/s16/bjorn/seqtools/bin/sff2fastq
PYTHON := python
ZCAT := zcat
JAVA := java
AWK := awk
USEARCH := $(USEARCH_PATH)/usearch7
UC2OTUTAB_PY := $(USEARCH_PATH)/scripts/uc2otutab.py
FASTA_NUMBER_PY := $(USEARCH_PATH)/scripts/fasta_number.py
FASTQ_STRIP_BARCODE_RELABEL2_PY := $(USEARCH_PATH)/scripts/fastq_strip_barcode_relabel2.py
GOLD_DB_PATH := $(USEARCH_PATH)/microbiomeutil-r20110519/gold.fa
RDP_CLASSIFIER_JAR := $(THIRD_PARTY_PATH)/rdp_classifier_2.10.1/dist/classifier.jar
QIIME_ACTIVATION_SCRIPT := /projects/qiime/activate-qiime-1.7.0.sh

# Use Anaconda Python which is assumed to have the following package installed
# via pip: biom-format
ANACONDA_PATH := $(THIRD_PARTY_PATH)/anaconda-2.1.0/bin
export PATH := $(ANACONDA_PATH):$(PATH)


## Below here is not meant to be configured by user ##########################

QC_TARGETS := $(patsubst %.fastq, %_fastqc.zip, $(INFILE)) \
              $(patsubst %.fastq, %_fastq_stats.txt, $(INFILE))
QF_TARGETS := $(patsubst %.fastq, %.fasta, $(INFILE))
OTU_TARGETS := $(patsubst %.fastq, %_otureps.fasta, $(INFILE)) \
               $(patsubst %.fastq, %_otutab.tsv, $(INFILE))
TAX_TARGETS := $(patsubst %.fastq, %_otutaxrdp.tsv, $(INFILE))
PHY_TARGETS := $(patsubst %.fastq, %_otuphy.tre, $(INFILE))
SFF_FILES := $(wildcard $(SFF_PATH)/*.sff)
SFF_GZ_FILES := $(wildcard $(SFF_PATH)/*.sff.gz)
DEMULT_TARGETS := $(patsubst %.sff.gz, %_demultiplexed.fastq, $(SFF_GZ_FILES)) \
                  $(patsubst %.sff, %_demultiplexed.fastq, $(SFF_FILES))
BIOM_TARGETS := $(patsubst %.fastq, %.biom, $(INFILE))

ALL_TARGETS := $(QC_TARGETS) $(QF_TARGETS) $(OTU_TARGETS) $(DEMULT_TARGETS) \
               $(TAX_TARGETS) $(PHY_TARGETS) $(BIOM_TARGETS)

PYNAST_TMP := $(CURDIR)/pynast

ALL_TMP := $(PYNAST_TMP)


.PHONY: all sff qc qf otu tax phy biom clean

all: qf otu tax phy biom

sff: $(DEMULT_TARGETS)
	cat $^ > $(INFILE)

qc: $(QC_TARGETS)

qf: $(QF_TARGETS)

otu: $(OTU_TARGETS)

tax: $(TAX_TARGETS)

phy: $(PHY_TARGETS)

biom: $(BIOM_TARGETS)

clean:
	-rm -rf $(ALL_TARGETS) $(ALL_TMP)


## Rules for quality control
#
# NB: FastQC automatically adds the suffix "_fastqc"
%_fastqc.zip: %.fastq
	$(FASTQC) --noextract $<

%_fastq_stats.txt: %.fastq
	$(USEARCH) -fastq_stats $< -log $@


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
# taxrdp = the "alltax" format output by RDP
# tax = only taxonomic ranks from domain to genus
#
%_otutaxrdp.tsv: %_otureps.fasta
	$(JAVA) -Xmx1g -jar $(RDP_CLASSIFIER_JAR) classify -o $@ $<

%_otutax.tsv: %_otutaxrdp.tsv
	$(AWK) -f scripts/allrank2tsv.awk $< > $@


## Rules for generating phylogenetic tree for OTU representatives
#
$(PYNAST_TMP)/%_otureps_aligned.fasta: %_otureps.fasta
	source $(QIIME_ACTIVATION_SCRIPT) && \
	parallel_align_seqs_pynast.py -i $< --jobs_to_start=$(NUMJOBS) \
	    -o $(PYNAST_TMP)

$(PYNAST_TMP)/%_aligned_pfiltered.fasta: $(PYNAST_TMP)/%_aligned.fasta
	source $(QIIME_ACTIVATION_SCRIPT) && \
	filter_alignment.py -i $< -o $(PYNAST_TMP)

%_otuphy.tre: $(PYNAST_TMP)/%_otureps_aligned_pfiltered.fasta
	source $(QIIME_ACTIVATION_SCRIPT) && \
	make_phylogeny.py -i $< -o $@ -r midpoint

## Rules for generating biom file
#
#   create bare biom file (no taxonomy) -> add taxonomy to biom file
#
# NOTE: In theory it should be possible to add taxonomy on creation of the biom
# file but I could not get it to work (no taxonomy would be added).  Also, in
# theory RDP should be able to add taxonomy directly to bare biom file, but
# that I could not get to work either.
#
%_bare.biom: %_otutab.tsv $(SAMPLE_METADATA)
	biom convert -i $< -o $@ --table-type="OTU table" --to-json \
	    --sample-metadata-fp=$(word 2, $^)

%.biom: %_bare.biom %_otutax.tsv
	biom add-metadata -i $< --output-as-json \
	    --observation-metadata-fp=$(word 2, $^) -o $@
