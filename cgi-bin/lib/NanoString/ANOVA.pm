#!/usr/bin/perl
##
# NanoString/ANOVA.pm
# 
# Perl module to perform ANOVA to generate p-values and generates a heatmap.
#
# Chris Brumbaugh, cbrumbau@soe.ucsc.edu, 04/21/2011
##

package NanoString::ANOVA;

use strict;
use warnings;

our $VERSION = 1.0;
our $script = '';
our $debug = 0;
our $debug_verbosity = 3;

sub setScript {
	my ($package, $file) = @_;
	$script = $file;
}

sub setDebug {
	my ($package, $level) = @_;
	$debug = $level;
}

sub setDebugVerbosity {
	my ($package, $lines) = @_;
	$debug_verbosity = $lines;
}

# format_localtime ()
# Provides the local time formatted to be used in debug logs
# Input: None
# Return: A string containing the formatted local time
sub format_localtime {
	my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekdays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	(my $second, my $minute, my $hour, my $day_of_month, my $month, my $year_offset, my $day_of_week, my $day_of_year, my $daylight_savings) = localtime();
	my $year = 1900 + $year_offset;
	my $the_time = "$weekdays[$day_of_week] $months[$month] $day_of_month, $year, $hour:$minute:$second";
	return "[".$the_time."] ";
}

=head1 NAME
 
	NanoString::ANOVA - Generates p-values from NanoString data and generates
	a heatmap from this normalized data.

=head1 SYNOPSIS

	use NanoString::ANOVA;
	NanoString::ANOVA->applyANOVA ($R, $raw_conds_ref, $tabdelimited_output, $output_dir, $anova_pvalue_cutoff, $anova_mean_cutoff, $pvalue, $adjpvalue_type);
	NanoString::ANOVA->generateHeatmap ($R, $output_dir, $heatmap_colors, $heatmap_clustercols, $heatmap_key);

=head1 DESCRIPTION

This is a library which generates p-values for normalized NanoString data by
t-test and generates a heatmap.

=head2 Methods

=head3 applyANOVA

	NanoString::ANOVA->applyANOVA ($R, $raw_conds_ref, $tabdelimited_output, $output_dir, $anova_pvalue_cutoff, $anova_mean_cutoff, $pvalue, $adjpvalue_type);

Takes a flag to designate tab delimited output and the path to the output
directory.

=cut

sub applyANOVA {
	my $package = shift;
	my $rawdata_conds_ref = shift;
	my @rawdata_conds = @{$rawdata_conds_ref};
	my $tabdelimited_output = shift;
	my $output_dir = shift;
	my $anova_pvalue_cutoff = shift;
	my $anova_mean_cutoff = shift;
	my $adjpvalue = shift;
	my $adjpvalue_type = shift;

	open (RSCRIPT, '>>', $script);

	my $pvalue_code = '';
	if ($adjpvalue) {
		$pvalue_code = 'p.value.adj';
	} elsif (!$adjpvalue) {
		$pvalue_code = 'p.value';
	}

	# Get unique labels for diff exp, create string to pass to R
	my %store_labels = ();
	for my $label (@rawdata_conds) {
		$store_labels{$label}++;
	}
	my @unique_labels = keys (%store_labels);
	@unique_labels = sort {$a <=> $b} @unique_labels;
	my $labels_string = '';
	for my $i (0..$#unique_labels) {
		$labels_string = $labels_string.'"'.$unique_labels[$i].'"';
		if ($i < $#unique_labels) {
			$labels_string = $labels_string.', ';
		}
	}
	if ($debug > 0) {
		print STDERR format_localtime()."DEBUG: Using unique conditions (".$labels_string.") for ANOVA.\n";
	}

	# Load libraries for generating heatmap into R
	if ($debug > 0) {
		print STDERR format_localtime()."DEBUG: Loading libraries and subroutines required for ANOVA and heatmap generation...\n";
	}
	print RSCRIPT '# Load required packages
library("pheatmap"); # for pheatmap

anova.matrix <- function(x, cov) {
	this.lm <- lm(x ~ cov);
	this.anova <- anova(this.lm);
	this.result <- matrix(NA, nrow = 1, ncol = 4);
	colnames(this.result) <- c("sum.of.squares", "mean.square", "f.value", "p.value");
	this.result[1,1] <- this.anova$`Sum Sq`[1];
	this.result[1,2] <- this.anova$`Mean Sq`[1];
	this.result[1,3] <- this.anova$`F value`[1];
	this.result[1,4] <- this.anova$`Pr(>F)`[1];
	return(this.result);
}

base.means <- function(x, feature_indices) {
	this.result <- matrix(NA, nrow = 1, ncol = (1+length(feature_indices)));
	col_names <- c("baseMean");
	for (i in (1:length(feature_indices))) {
		col_names[i+1] <- paste("baseMean", i, sep = "");
	}
	colnames(this.result) <- col_names;
	this.result[1] <- mean(x);
	for (i in (1:length(feature_indices))) {
		this.result[i+1] <- mean(x[feature_indices[[i]]]);
	}
	return(this.result)
}'."\n";

	# Send the conditions to R
	if ($debug > 0) {
		print STDERR format_localtime()."DEBUG: Sending conditions (".join (',', @rawdata_conds).") for ANOVA...\n";
	}
	print RSCRIPT 'conds <- array(c('.join (',', @rawdata_conds).'), dim=c('.scalar (@rawdata_conds).'));'."\n";
	
	# Do t-test on normalized_data
	if ($debug > 0) {
		print STDERR format_localtime()."DEBUG: Perform ANOVA on normalized data...\n";
	}
	print RSCRIPT 'anova <- apply(norm_rna, 1, anova.matrix, cov = factor(conds));
anova <- data.frame(t(anova));
colnames(anova) <- c("sum.of.squares", "mean.square", "f.value", "p.value");
# Map features to columns by indices
features <- sort(unique(conds));
feature_indices <- list();
for (i in (1:length(features))) {
	feature_indices[[i]] <- which(conds == features[i])
}
# Calculate mean
base.mean <- apply(norm_rna, 1, base.means, feature_indices = feature_indices);
base.mean <- t(base.mean);
col_names <- c("baseMean");
for (i in (1:length(feature_indices))) {
	col_names[i+1] <- paste("baseMean", i, sep = "");
}
colnames(base.mean) <- col_names;
# Store calculations into anova data frame
anova <- cbind(base.mean, anova);
# Store calculations into anova data frame
anova$p.value.adj <- p.adjust(anova$p.value, method = "'.$adjpvalue_type.'");
# Add id column, change rownames to numbers, reorder columns
anova$id <- rownames(anova);
rownames(anova) <- 1:nrow(anova);
anova <- anova[,c(length(anova),1:(length(anova)-1))];
sort.anova <- anova[order(anova$'.$pvalue_code.'),]; # sort results by p-values'."\n";

	# Output ANOVA to file
	if ($tabdelimited_output) {
		if ($debug > 0) {
			print STDERR format_localtime()."DEBUG: Writing sorted ANOVA to tab delimited file...\n";
		}
		print RSCRIPT 'write.table(sort.anova, file = "'.$output_dir.'sorted_ANOVA.tab", sep = "\t");'."\n";
	} else {
		if ($debug > 0) {
			print STDERR format_localtime()."DEBUG: Writing sorted ANOVA to csv file...\n";
		}
		print RSCRIPT 'write.csv(sort.anova, file = "'.$output_dir.'sorted_ANOVA.csv");'."\n";
	}

	# Prepare for heatmap using cutoff values
	if ($debug > 0) {
		print STDERR format_localtime()."DEBUG: Prepare for heatmap by taking pval < ".$anova_pvalue_cutoff."...\n";
	}
	print RSCRIPT 'pval_row_index <- which((anova$'.$pvalue_code.' < '.$anova_pvalue_cutoff.') %in% c(TRUE));
filtered_norm_rna <- norm_rna[pval_row_index, ]; # get normalized data with '.$pvalue_code.' < '.$anova_pvalue_cutoff.'
mean_row_index <- which((rowMeans(filtered_norm_rna) > '.$anova_mean_cutoff.') %in% c(TRUE));
filtered_norm_rna <- filtered_norm_rna[mean_row_index, ]; # get normalized data with mean > '.$anova_mean_cutoff."\n";

	# Output heatmap filtered data to file
	if ($tabdelimited_output) {
		if ($debug > 0) {
			print STDERR format_localtime()."DEBUG: Writing filtered ANOVA to tab delimited file...\n";
		}
		print RSCRIPT 'write.table(filtered_norm_rna, file = "'.$output_dir.'heatmap.tab", sep = "\t");'."\n";
	} else {
		if ($debug > 0) {
			print STDERR format_localtime()."DEBUG: Writing filtered ANOVA to csv file...\n";
		}
		print RSCRIPT 'write.csv(filtered_norm_rna, file = "'.$output_dir.'heatmap.csv");'."\n";
	}

	close (RSCRIPT);

	return 1;
}

=head3 generateHeatmap

	NanoString::ANOVA->generateHeatmap ($R, $output_dir, $heatmap_colors, $heatmap_clustercols, $heatmap_key);

Takes the output directory and the heatmap colors.

=cut

sub generateHeatmap {
	my $package = shift;
	my $output_dir = shift;
	my $heatmap_colors = shift;
	my $heatmap_clustercols = shift;
	my $heatmap_key = shift;
	my $warnings_file = shift;

	open (RSCRIPT, '>>', $script);

	# Check if heatmap can be generated, else provide warning
	if ($debug > 0) {
		print STDERR format_localtime()."DEBUG: Processing warnings type 6...\n";
	}
	# 6. No statistically significant probes identified, heatmap cannot be generated
	print RSCRIPT '# 6. No statistically significant probes identified, heatmap cannot be generated
warnings <- c();
if (nrow(filtered_norm_rna) == 0) {
	warnings <- append(warnings, paste("WARNING: No statistically significant probes identified, heatmap cannot be generated."));
}
if (nrow(filtered_norm_rna) == 1) {
	warnings <- append(warnings, paste("WARNING: One statistically significant probes identified, heatmap cannot be generated."));
}
if (!exists("filtered_norm_rna")) {
	warnings <- append(warnings, paste("WARNING: No statistically significant probes identified, heatmap cannot be generated. (Running ANOVA failed.)"));
}
if (length(warnings) > 0) {
	FILEWRITE <- file("'.$warnings_file.'", open = "a");
	writeLines(warnings, FILEWRITE);
	close(FILEWRITE);
}'."\n";

	# Generate heatmap
	if ($debug > 0) {
		print STDERR format_localtime()."DEBUG: Generate heatmap and output to file...\n";
	}
	print RSCRIPT '# Load Cairo package
library("Cairo");

if (nrow(filtered_norm_rna) > 1) {
	# Convert _ to whitespace
	col_names <- colnames(data.matrix(filtered_norm_rna));
	col_names <- gsub("(sample_number__)", " ", col_names);
	col_names <- gsub("_", " ", col_names);
	colnames(filtered_norm_rna) <- col_names;
	# Adjust the margins
	row_names <- rownames(data.matrix(filtered_norm_rna));
	max_char_row <- max(nchar(row_names));
	max_char_col <- max(nchar(col_names));
	# Adjust image size
	# size for plot + size for label margins + size for dendrogram in pixels + outer margins
	heatmap_height <- length(row_names) * 30 + max_char_col * 8 + 50 + 50;
	heatmap_width <- length(col_names) * 30 + max_char_row * 8 + 50 + 50 + 75; # add 75 for legend
	CairoPNG(filename = "'.$output_dir.'heatmap.png", height = heatmap_height, width = heatmap_width, res = 72);
	pheatmap(filtered_norm_rna, '.$heatmap_clustercols.', '.$heatmap_key.', scale = "row", border_color = NA, cellwidth = 30, cellheight = 30, treeheight_row = 75, treeheight_col = 75, annotation_legend = FALSE, fontsize = 12, fontfamily = "mono", fontface = "plain", color = '.$heatmap_colors.');
	dev.off();
}'."\n";

	close (RSCRIPT);

	return 1;
}

=head1 AUTHOR

Chris Brumbaugh <cbrumbau@soe.ucsc.edu>

=cut

1;
