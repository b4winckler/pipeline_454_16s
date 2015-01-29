# Convert QIIME RDP taxonomy assignments file to a CSV file.
#
# For example, the input
#
#   OTU_5   k__Bacteria;p__Proteobacteria;c__Gammaproteobacteria;o__Pasteurellales;f__Pasteurellaceae;g__Haemophilus;s__parainfluenzae      0.870
#   OTU_21  k__Bacteria;p__Firmicutes;c__Bacilli;o__Gemellales;f__Gemellaceae       1.000
#
# is converted to the output
#
#   OTU_5,Bacteria,Proteobacteria,Gammaproteobacteria,Pasteurellales,Pasteurellaceae,Haemophilus,parainfluenzae,0.870
#   OTU_21,Bacteria,Firmicutes,Bacilli,Gemellales,Gemellaceae,,,1.000
#
# Note that the output always contains exactly 9 columns.

BEGIN {
    print "taxa,kingdom,phylum,class,order,family,genus,species,confidence"
}

{
    printf "%s,", $1

    split($2, tax, ";")
    for (i = 1; i <= 7; ++i) {
        sub("[kpcofgs]__", "", tax[i])
        printf "%s,", tax[i]
    }

    print $3
}

