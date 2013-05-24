package Genome::Model::Tools::Validation::Sciclone;

use strict;
use warnings;
use FileHandle;
use Genome;
use File::Basename;
use FileHandle;
#use Math::Combinatorics;

class Genome::Model::Tools::Validation::Sciclone {
    is => 'Command',

    has => [
        variant_files => {
            is => 'Text',
            doc => "comma separated list - files of validated variants with readcounts. 7-column Bam-readcount format - columns: Chr, Start, Ref, Var, RefReads, VarReads, VAF",
            is_optional => 0,
            is_input => 1 ,
        },

        copy_number_files => {
            is => 'Text',
            doc => 'comma separated list - files of segmented copy number calls. If not specified, assumes all variants are CN 2. Expects 5-col format - Chr, St, Sp, NumProbes, SegMean. If you have CNVHMM calls, use "gmt copy-number convert-cnvhmm-output-to-sane-format" to fix them',
            is_optional => 1,
            is_input => 1
        },

        sample_names => {
            is => 'Text',
            doc => "comma separated list - Sample name to be put on graphs",
            is_optional => 1,
            is_input => 1,
        },

        regions_to_exclude => {
            is => 'Text',
            doc => "comma separated list - regions to exclude (first 3 cols are chr,st,sp). Commonly used for LOH calls",
            is_optional => 1,
            is_input => 1,
        },

        clusters_file => {
            is => 'Text',
            doc => "output file containing clustered data",
            is_optional => 0,
            is_input => 1,
            is_output => 1
        },

        r_script_file => {
            is => 'Text',
            doc => "filename to dump R commands to",
            is_optional => 0,
            is_input => 1,
            is_output => 1
        },

        minimum_depth => {
            is => 'Integer',
            doc => "Plot/Cluster only using variants that have at least this many reads. 100 is a reasonable default for capture data. If only wgs data is available, you'll need to lower this value.",
            is_optional => 1,
            default => 100,
        },

        cn_calls_are_log2 => {
            is => 'Boolean',
            doc => "copy number calls are in log 2 format (default is absolute CN - 1, 2, 3, etc)",
            is_optional => 1,
            default => 0,
        },


        skip_if_output_is_present => {
            is => 'Text',
            doc => "Skip if Output is Present",
            is_optional => 1,
            is_input => 1,
            default => 0,
        },

        do_clustering => {
            is => 'Boolean',
            doc => "if true, clusters the data. if false, just creates a plot (saving time)",
            is_optional => 1,
            default => 1,
        },

        tumor_purities => {
            is => 'Integer',
            doc => "comma separated list of tumor purities (between 0 to 100). Will be estimated by the tool if not provided",
            is_optional => 1,
        },


        ##-------plotting options------
        plot1d_file => {
            is => 'Text',
            doc => "filename for 1d plots (pdf)",
            is_optional => 1,
            is_input => 1,
            is_output => 1
        },

        plot2d_file => {
            is => 'Text',
            doc => "filename for 2d plots (pdf)",
            is_optional => 1,
            is_input => 1,
            is_output => 1
        },

        plot3d_file => {
            is => 'Text',
            doc => "prefix filename for 3d plots - will create one plot for each trio of samples (gif)",
            is_optional => 1,
            is_input => 1,
            is_output => 1
        },

        highlight_sex_chrs => {
            is => 'Boolean',
            doc => "Highlight the sex chromosomes (X|Y) on the plot (1d plot)",
            is_optional => 1,
            is_input => 1,
            default => 1,
        },

        positions_to_highlight => {
            is => 'Text',
            doc => "A tab-delimited file listing variants highlight on the plot. First two columns must be Chr, St (1d plot & 2d plot)",
            is_optional => 1,
            is_input => 1,
        },

        label_highlighted_points => {
            is => 'Boolean',
            doc => "if true, assumes that the positions-to-highlight file has a third column, containing names for the points to be highlighted. Sets plotOnlyCN2 to true and adds numbered labels and a legend for the highlighted points (1d plot & 2d plot)",
            is_optional => 1,
            default => 0,
        },

        minimum_labelled_peak_height => {
            is => 'Text',
            doc => "only KDE peaks that exceed this height get labelled (1d plot)",
            is_optional => 1,
            is_input => 1,
            default => 0.001
        },

        only_label_highest_peak => {
            is => 'Boolean',
            doc => "only label the highest peak (1d plot)",
            is_optional => 1,
            default => 0
        },

        overlay_error_bars => {
            is => 'Boolean',
            doc => "show error bars in the plot (2d plot)",
            is_optional => 1,
            default => 0,
        },

        plot_only_cn2 => {
            is => 'Boolean',
            doc => "only plot the CN2 data (1d plot)",
            is_optional => 1,
            default => 0,
        },

        overlay_clusters => {
            is => 'Boolean',
            doc => "overlay information about how the points clustered onto the scatterplot (1d plot & 2d plot)",
            is_optional => 1,
            default => 1,
        },

        show_title => {
            is => 'Boolean',
            doc => "show the sample name on the plot (1d plot)",
            is_optional => 1,
            default => 1,
        },
        
        plot_size_3d => {
            is => 'Integer',
            doc => 'size in pixels of the square 3d plots',
            is_optional => 1,
            default => 700,
        },


        ],
};


sub help_brief {
    "infer the subclonal architecture of tumors and create informative plots"
}

sub help_synopsis {
    return <<EOS
        Inputs of variant readcounts and copy-number segmentation data, Output of cluster assignments and pdf plots.
EXAMPLE:	gmt validation clonality-plot --variant-file snvs.txt,snvs2.txt --output-prefix clonality --sample-names 'Sample1,Sample2' --copy_number_files segs.paired.dat,segs2.paired.dat
EOS
}

sub help_detail {
    return <<EOS
This tool can be used to plot the CN-separated SNV density plots that are known at TGI as 'clonality plots'. Can be used for WGS or Capture data, but best results will be had with greater than 100x read depth.
EOS
}

sub execute {
    my $self = shift;

    ##inputs##
    my $variant_files = $self->variant_files;
    my $cn_files = $self->copy_number_files;
    my $sample_names = $self->sample_names;
    my $tumor_purities = $self->tumor_purities;
    my $cn_calls_are_log2 = $self->cn_calls_are_log2;
    my $regions_to_exclude = $self->regions_to_exclude;

    ##outputs##
    my $clusters_file = $self->clusters_file;
    my $plot1d_file = $self->plot1d_file;
    my $plot2d_file = $self->plot2d_file;
    my $plot3d_file = $self->plot3d_file;
    my $r_script_file = $self->r_script_file;


    ##options##
    my $skip_if_output_is_present = $self->skip_if_output_is_present;
    my $minimum_depth = $self->minimum_depth;
    my $do_clustering = $self->do_clustering;
    my $highlight_sex_chrs = $self->highlight_sex_chrs;
    my $positions_to_highlight = $self->positions_to_highlight;
    my $label_highlighted_points  = $self->label_highlighted_points;
    my $minimum_labelled_peak_height = $self->minimum_labelled_peak_height;
    my $only_label_highest_peak = $self->only_label_highest_peak;
    my $plot_only_cn2 = $self->plot_only_cn2;
    my $overlay_clusters = $self->overlay_clusters;
    my $show_title = $self->show_title;
    my $plot_size_3d = $self->plot_size_3d;
    my $overlay_error_bars = $self->overlay_error_bars;

    my $rfile;
    open($rfile, ">$r_script_file") || die "Can't open R file for writing.\n";

    # write out the r commands
    print $rfile "library(sciClone)\n";

    ##TODO - handle headers

    #read in the variant files
    my @variantFiles = split(",",$variant_files);
    my @variantVars;
    my $i=0;
    for($i=0;$i<@variantFiles;$i++){
        my $var = "v$i";
        push(@variantVars,$var);
        # read in the file (and convert varscan, if necessary)
        print $rfile "$var = " . 'read.table("' . $variantFiles[$i] .  '")' . "\n";
        print $rfile "$var = $var" . '[,c(1,2,5,6,7)]' . "\n";
    }

    #read in the cn files
    my @cnVars;
    if(defined($cn_files)){
        my @cnFiles = split(",",$cn_files);
        my $i=0;
        for($i=0;$i<@cnFiles;$i++){
            my $var = "cn$i";
            push(@cnVars,$var);
            # read in the file (and convert varscan, if necessary)
            print $rfile "$var = " . 'read.table("' . $cnFiles[$i] .  '")' . "\n";
            print $rfile "$var = $var" . '[,c(1,2,3,5)]' . "\n";
        }
    }

    my @regVars;
    if(defined($regions_to_exclude)){
        my @regFiles =  split(",",$regions_to_exclude);
        my $i=0;
        for($i=0;$i<@regFiles;$i++){
            #skip empty files
            if(-s $regFiles[$i]){
                my $var = "reg$i";
                push(@regVars,$var);
                # read in the file (and convert varscan, if necessary)
                print $rfile "$var = " . 'read.table("' . $regFiles[$i] .  '")' . "\n";
                print $rfile "$var = $var" . '[,c(1,2,3)]' . "\n";
            }
        }
    }

    if(defined($positions_to_highlight)){
        if(!(-s $positions_to_highlight)){
            die("file specified in positions-to-highlight does not exist");
        }
        print $rfile "highlights = " . 'read.table("' . $positions_to_highlight .  '")' . "\n";
    }

    my @sampleNames = split(",",$sample_names);
    my $sampleNames = '"' . join('","',@sampleNames) . '"';


    #--- clustering command ---
    my $cmd = 'sc = sciClone(vafs=list(' . join(",",@variantVars) . ")";
    $cmd = $cmd . ", sampleNames=c(" . $sampleNames . ")";

    if(defined($cn_files)){
        $cmd = $cmd . ", copyNumberCalls=list(" . join(",",@cnVars) . ")";
    }

    
    if(defined($regions_to_exclude)){
        $cmd = $cmd . ", regionsToExclude=list(" . join(",",@regVars) . ")";
    }

    $cmd = $cmd . ", minimumDepth=$minimum_depth";

    if(defined($tumor_purities)){
        print "tp: " . $tumor_purities . "\n";
        $cmd = $cmd . ", purity=c($tumor_purities)";
    }

    if($cn_calls_are_log2){
        $cmd = $cmd . ", cnCallsAreLog2=TRUE";
    }

    if($do_clustering){
        $cmd = $cmd . ", doClustering=TRUE";
    } else {
        $cmd = $cmd . ", doClustering=FALSE";
    }
    print $rfile $cmd . ")\n";


    #write out the cluster table command:
    print $rfile "writeClusterTable(sc, \"$clusters_file\")\n";


    #--- 1d plotting ---
    if(defined(($plot1d_file))){
        print $rfile "sc.plot1d(sc,\"$plot1d_file\"";

        if($highlight_sex_chrs){
            print $rfile ", highlightSexChrs=TRUE"
        }
        if(defined($positions_to_highlight)){
            if(!(-s $positions_to_highlight)){
                die("file specified in positions-to-highlight does not exist");
            }
            print $rfile ", positionsToHighlight=highlights";
        }

        if($label_highlighted_points){
            print $rfile ", highlightsHaveNames=TRUE";
        } else {
            print $rfile ", highlightsHaveNames=FALSE";
        }

        if(defined($minimum_labelled_peak_height)){
            print $rfile ", minimumLabelledPeakHeight=$minimum_labelled_peak_height";
        }

        if($only_label_highest_peak){
            print $rfile ", onlyLabelHighestPeak=TRUE";
        } else {
            print $rfile ", onlyLabelHighestPeak=FALSE";
        }


        if($plot_only_cn2){
            print $rfile ", plotOnlyCN2=TRUE";
        } else {
            print $rfile ", plotOnlyCN2=FALSE";
        }

        if($overlay_clusters){
            print $rfile ", overlayClusters=TRUE";
        } else {
            print $rfile ", overlayClusters=FALSE";
        }

        if($show_title){
            print $rfile ", showTitle=TRUE";
        } else {
            print $rfile ", showTitle=FALSE";
        }
        print $rfile ")\n";

        # not implemented:
        # showCopyNumberScatterPlots
        # overlayIndividualModels
        # showHistogram
        #


    }


    #--- 2d plotting ---
    if(defined(($plot2d_file))){
        if(@sampleNames < 2){
            die("can't do 2d plotting without at least 2 samples")
        }

        print $rfile "sc.plot2d(sc,\"$plot2d_file\"";

        if($overlay_clusters){
            print $rfile ", overlayClusters=TRUE";
        } else {
            print $rfile ", overlayClusters=FALSE";
        }

        if(defined($positions_to_highlight)){
            if(!(-s $positions_to_highlight)){
                die("file specified in positions-to-highlight does not exist");
            }
            print $rfile ", positionsToHighlight=highlights";
        }

        if($label_highlighted_points){
            print $rfile ", highlightsHaveNames=TRUE";
        } else {
            print $rfile ", highlightsHaveNames=FALSE";
        }

        # if($overlay_error_bars){
        #     print $rfile ", overlayErrorBars=TRUE";
        # } else {
        #     print $rfile ", overlayErrorBars=FALSE";
        # }

        print $rfile ")\n";
    }


    #--- 3d plotting ---
    if(defined(($plot3d_file))){
        print "Warning: 3d plotting not implemented in gmt yet\n";
        # if(@sampleNames < 3){
        #     die("can't do 3d plotting without at least 3 samples")
        # }
        
        # my @combs = combine(2,@sampleNames);
        # my @lists = map { join ",", @$_ } @combs; 
        # my $count = 1;
        # foreach my $list (@lists){
        #     print $rfile "sc.plot3d(sc, outputFile=\"$plot3d_file.$count\", samplesToPlot=$list";
        #     print $rfile ", size=$plot_size_3d";
        #     print $rfile ")\n";
        #     $count++;
        # }

    }

    close $rfile;

    #now actually run the R script
    # my $rcmd = "R --vanilla --slave \< $r_script_output_file";
    my $rcmd = "Rscript $r_script_file";
    my $return_value = Genome::Sys->shellcmd(
        cmd => "$rcmd",
        );
    unless($return_value) {
        $self->error_message("Failed to execute: Returned $return_value");
        die $self->error_message;
    }
    return $return_value;
}
