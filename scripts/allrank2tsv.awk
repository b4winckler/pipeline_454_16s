# Convert RDP classifier "allrank" format (i.e. RDP's default output format) to
# tab-separated format with a header.  Missing ranks in the input are printed
# as blanks in the output (so two tabs in a succession or a tab at the end of
# a line indicates a missing rank).

BEGIN {
    FS=OFS="\t"
    print "#otuid", "domain", "phylum", "class", "order", "family", "genus"
}

{
    delete x

    # allrank format is tab-separated with fields:
    #   otuid orientation taxa1 rank1 confidendence1 taxa2 rank2 confidence2 ..
    for (i=4; i < NF; i += 3) {
        x[$i] = $(i-1)
    }

    print $1, x["domain"], x["phylum"], x["class"], x["order"], x["family"], x["genus"]
}
