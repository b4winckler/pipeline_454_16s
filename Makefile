#
# Makefile for 454 pipeline
#
# QC  -	quality control
# QF  - quality filtering
# OTU - OTU generation
# TAX - taxonomic classification
# PHY - phylogenetic tree generation

# Input parameters
FASTQ_INPUT := test.fastq
MAXEE := 1.0
TRUNCLEN := 250
OTUID := 0.97
OTULABEL := OTU_


# Server configuration
FASTQC_BIN := /projects/qiime/FastQC/fastqc
USEARCH_BIN := /projects/qiime/usearch/usearch7
SFF2FASTQ_BIN := /projects/s16/bjorn/seqtools/bin/sff2fastq
PYTHON_BIN := python

USEARCH_SCRIPTS := /projects/qiime/usearch/scripts
UC2OTUTAB_PY := $(USEARCH_SCRIPTS)/uc2otutab.py
FASTA_NUMBER_PY := $(USEARCH_SCRIPTS)/fasta_number.py


# Other
QC_OUT := $(patsubst %.fastq, %_fastqc.zip, $(FASTQ_INPUT))
QF_OUT := $(patsubst %.fastq, %.fasta, $(FASTQ_INPUT))
OTU_OUT := $(patsubst %.fastq, %_otureps.fasta, $(FASTQ_INPUT)) \
	   $(patsubst %.fastq, %_otutable.txt, $(FASTQ_INPUT))


.PHONY: all qc qf clean

all: qf otu

qc: $(QC_OUT)

qf: $(QF_OUT)

otu: $(OTU_OUT)

clean:
	-rm -f $(QC_OUT) $(QF_OUT) $(OTU_OUT)


# NB: FastQC automatically adds the suffix "_fastqc"
%_fastqc.zip: %.fastq
	$(FASTQC_BIN) --noextract $<

%.fasta: %.fastq
	$(USEARCH_BIN) -fastq_filter $< -fastq_maxee $(MAXEE) \
		       -fastq_trunclen $(TRUNCLEN) -fastaout $@

%_derep.fasta: %.fasta
	$(USEARCH_BIN) -derep_fulllength $< -output $@ -sizeout

%_sort.fasta: %_derep.fasta
	$(USEARCH_BIN) -sortbysize $< -output $@ -minsize 2

%_otureps1.fasta: %_sort.fasta
	$(USEARCH_BIN) -cluster_otus $< -otus $@ -otuid $(OTUID)

%_otureps.fasta: %_otureps1.fasta
	$(PYTHON_BIN) $(FASTA_NUMBER_PY) $< $(OTULABEL) > $@

%_otumap.uc: %.fasta %_otureps.fasta
	$(USEARCH_BIN) -usearch_global $< -db $(word 2, $^) \
		       -strand plus -id $(OTUID) -uc $@

# FIXME: This will create an empty output file even if the script fails
%_otutable.txt: %_otumap.uc
	$(PYTHON_BIN) $(UC2OTUTAB_PY) $< > $@

%.fastq: %.sff.gz
	zcat $< | sff2bin -o $@

%.fastq: %.sff
	$(SFF2FASTQ_BIN) -o $@ $<
