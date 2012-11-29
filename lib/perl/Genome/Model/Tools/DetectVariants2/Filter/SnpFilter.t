#!/usr/bin/env genome-perl

use strict;
use warnings;

use above "Genome";
use File::Temp;
use Test::More tests => 12;
use Data::Dumper;
use File::Compare;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

BEGIN {
    use_ok( 'Genome::Model::Tools::DetectVariants2::Filter::SnpFilter')
};

my $refbuild_id = 101947881;
my $test_data_directory = $ENV{GENOME_TEST_INPUTS} . "/Genome-Model-Tools-DetectVariants2-Filter-SnpFilter";

# Updated to .v2 for correcting an error with newlines
my $expected_directory = $test_data_directory . "/expected";
my $detector_directory = $test_data_directory . "/samtools-r599-";
my $detector_vcf_directory = $test_data_directory . "/detector_vcf_result";
my $tumor_bam_file  = $test_data_directory. '/flank_tumor_sorted.bam';
my $normal_bam_file  = $test_data_directory. '/flank_normal_sorted.bam';
my $test_output_base = File::Temp::tempdir('Genome-Model-Tools-DetectVariants2-Filter-SnpFilter-XXXXX', DIR => "$ENV{GENOME_TEST_TEMP}", CLEANUP => 1);
my $test_output_dir = $test_output_base . '/filter';

my $vcf_version = Genome::Model::Tools::Vcf->get_vcf_version;

my @expected_output_files = qw| snvs.hq
                                snvs.hq.bed
                                snvs.hq.v1.bed
                                snvs.hq.v2.bed
                                snvs.lq
                                snvs.lq.bed
                                snvs.lq.v1.bed
                                snvs.lq.v2.bed | ;

my $detector_result = Genome::Model::Tools::DetectVariants2::Result->__define__(
    output_dir => $detector_directory,
    detector_name => 'Genome::Model::Tools::DetectVariants2::Samtools',
    detector_params => '',
    detector_version => 'awesome',
    aligned_reads => $tumor_bam_file,
    control_aligned_reads => $normal_bam_file,
    reference_build_id => $refbuild_id,
);
$detector_result->lookup_hash($detector_result->calculate_lookup_hash());

my $detector_vcf_result = Genome::Model::Tools::DetectVariants2::Result::Vcf::Detector->__define__(
    input => $detector_result,
    output_dir => $detector_vcf_directory,
    aligned_reads_sample => "TEST",
    vcf_version => $vcf_version,
);
$detector_vcf_result->lookup_hash($detector_vcf_result->calculate_lookup_hash());

$detector_result->add_user(user => $detector_vcf_result, label => 'uses');

my $snp_filter_high_confidence = Genome::Model::Tools::DetectVariants2::Filter::SnpFilter->create(
    previous_result_id => $detector_result->id,
    output_directory => $test_output_dir,
);

ok($snp_filter_high_confidence, "created SnpFilter object");
ok($snp_filter_high_confidence->execute(), "executed SnpFilter");

for my $output_file (@expected_output_files){
    my $expected_file = $expected_directory."/".$output_file;
    my $actual_file = $test_output_dir."/".$output_file;
    is(compare($actual_file, $expected_file), 0, "$actual_file output matched expected output");
}
ok(-s $test_output_dir."/snvs.vcf.gz", " found a meaty vcf");
