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
FASTQ_INPUT := test.fastq
MAXEE := 1.0
TRUNCLEN := 250
OTUID := 0.97
OTULABEL := OTU_


# Server configuration
FASTQC_BIN := /projects/qiime/FastQC/fastqc
SFF2FASTQ_BIN := /projects/s16/bjorn/seqtools/bin/sff2fastq
PYTHON_BIN := python

USEARCH_PATH := /projects/qiime/usearch
USEARCH_BIN := $(USEARCH_PATH)/usearch7
UC2OTUTAB_PY := $(USEARCH_PATH)/scripts/uc2otutab.py
FASTA_NUMBER_PY := $(USEARCH_PATH)/scripts/fasta_number.py
GOLD_DB_PATH := $(USEARCH_PATH)/microbiomeutil-r20110519/gold.fa


# Targets
QC_TARGETS := $(patsubst %.fastq, %_fastqc.zip, $(FASTQ_INPUT))
QF_TARGETS := $(patsubst %.fastq, %.fasta, $(FASTQ_INPUT))
OTU_TARGETS := $(patsubst %.fastq, %_otureps.fasta, $(FASTQ_INPUT)) \
	       $(patsubst %.fastq, %_otutable.txt, $(FASTQ_INPUT))
ALL_TARGETS := $(QC_TARGETS) $(QF_TARGETS) $(OTU_TARGETS)


.PHONY: all qc qf clean

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
	$(FASTQC_BIN) --noextract $<


## Rule for quality filtering
#
%.fasta: %.fastq
	$(USEARCH_BIN) -fastq_filter $< -fastq_maxee $(MAXEE) \
		       -fastq_trunclen $(TRUNCLEN) -fastaout $@


## Rules for generating OTU representatives
#
# dereplicate -> sort -> cluster OTUs -> database chimera removal
#   -> sequentially label OTUs
#
%_derep.fasta: %.fasta
	$(USEARCH_BIN) -derep_fulllength $< -output $@ -sizeout

%_sort.fasta: %_derep.fasta
	$(USEARCH_BIN) -sortbysize $< -output $@ -minsize 2

%_otureps1.fasta: %_sort.fasta
	$(USEARCH_BIN) -cluster_otus $< -otus $@ -otuid $(OTUID)

%_otureps2.fasta: %_otureps1.fasta
	$(USEARCH_BIN) -uchime_ref $< -db $(GOLD_DB_PATH) -strand plus \
		       -nonchimeras $@

%_otureps.fasta: %_otureps2.fasta
	$(PYTHON_BIN) $(FASTA_NUMBER_PY) $< $(OTULABEL) > $@


## Rules for generating OTU abundance table
#
# map reads to OTU representatives -> create table
#
%_otumap.uc: %.fasta %_otureps.fasta
	$(USEARCH_BIN) -usearch_global $< -db $(word 2, $^) \
		       -strand plus -id $(OTUID) -uc $@

%_otutable.txt: %_otumap.uc
	$(PYTHON_BIN) $(UC2OTUTAB_PY) $< > $@


## Rules for generating fastq files from sff files
#
%.fastq: %.sff.gz
	zcat $< | sff2bin -o $@

%.fastq: %.sff
	$(SFF2FASTQ_BIN) -o $@ $<
