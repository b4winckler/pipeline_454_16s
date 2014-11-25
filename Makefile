#
# Makefile for 454 pipeline
#
# QC  -	quality control
# QF  - quality filtering
# OTU - OTU generation
# TAX - taxonomic classification
# PHY - phylogenetic tree generation
#
# FIXME: Commands that create files by redirecting to stdout will not clean up
# after themselves if they fail which causes dependency problems as it seems
# the command succeeded based on the target file being present.

# Input parameters
INFILE := reads.fastq
SFF_PATH := sff
MAXEE := 1.0
TRUNCLEN := 250
OTUID := 0.97
OTULABEL := OTU_
PRIMER := CCTACGGGNGGCWGCAG


# Server configuration
FASTQC := /projects/qiime/FastQC/fastqc
SFF2FASTQ := /projects/s16/bjorn/seqtools/bin/sff2fastq
PYTHON := python
ZCAT := zcat

USEARCH_PATH := /projects/qiime/usearch
USEARCH := $(USEARCH_PATH)/usearch7
UC2OTUTAB_PY := $(USEARCH_PATH)/scripts/uc2otutab.py
FASTA_NUMBER_PY := $(USEARCH_PATH)/scripts/fasta_number.py
FASTQ_STRIP_BARCODE_RELABEL2_PY := $(USEARCH_PATH)/scripts/fastq_strip_barcode_relabel2.py
GOLD_DB_PATH := $(USEARCH_PATH)/microbiomeutil-r20110519/gold.fa


# Targets
QC_TARGETS := $(patsubst %.fastq, %_fastqc.zip, $(INFILE))
QF_TARGETS := $(patsubst %.fastq, %.fasta, $(INFILE))
OTU_TARGETS := $(patsubst %.fastq, %_otureps.fasta, $(INFILE)) \
  $(patsubst %.fastq, %_otutable.txt, $(INFILE))
ALL_TARGETS := $(QC_TARGETS) $(QF_TARGETS) $(OTU_TARGETS)



.PHONY: all sff qc qf otu clean

all: qf otu

qc: $(QC_TARGETS)

qf: $(QF_TARGETS)

otu: $(OTU_TARGETS)

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

%_otutable.txt: %_otumap.uc
	$(PYTHON) $(UC2OTUTAB_PY) $< > $@


## Rules for generating fastq file from multiple sff files
#
%_raw.fastq: %.sff.gz
	$(ZCAT) $< | $(SFF2FASTQ) -o $@

%_raw.fastq: %.sff
	$(SFF2FASTQ) -o $@ $<

%_demultiplexed.fastq: %_raw.fastq
	$(PYTHON) $(FASTQ_STRIP_BARCODE_RELABEL2_PY) $< $(PRIMER) \
	          $*-barcodes.fasta $(notdir $*) > $@

sff: $(patsubst %.sff.gz, %_demultiplexed.fastq, \
	   $(wildcard $(SFF_PATH)/*.sff.gz))
	cat $^ > $(INFILE)
	-rm -f $^
