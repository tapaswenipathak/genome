#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above "Genome";

require File::Compare;
use Test::More;

use_ok('Genome::InstrumentData::Command::Import::Basic') or die;

my $sample = Genome::Sample->create(name => '__TEST_SAMPLE__');
ok($sample, 'Create sample');

my $test_dir = $ENV{GENOME_TEST_INPUTS}.'Genome-InstrumentData-Command-Import-Basic';
my $source_sra = $test_dir.'/test.sra';
my $cmd = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => [$source_sra],
    import_source_name => 'sra',
    sequencing_platform => 'solexa',
    instrument_data_properties => [qw/ lane=2 flow_cell_id=XXXXXX /],
);
ok($cmd, "create import command");
ok($cmd->execute, "excute import command");

my $instrument_data = $cmd->instrument_data;
ok($instrument_data, 'got instrument data 2');
is($instrument_data->original_data_path, $source_sra, 'original_data_path correctly set');
is($instrument_data->import_format, 'bam', 'import_format correctly set');
is($instrument_data->sequencing_platform, 'solexa', 'sequencing_platform correctly set');
is($instrument_data->is_paired_end, 0, 'is_paired_end correctly set');
is($instrument_data->read_count, 148, 'read_count correctly set');
my $allocation = $instrument_data->allocations;
ok($allocation, 'got allocation');
ok($allocation->kilobytes_requested > 0, 'allocation kb was set');

# sra
ok(-s $allocation->absolute_path.'/all_sequences.sra', 'sra exists');

# bam
my $bam_via_archive_path = $instrument_data->archive_path;
my $bam_via_bam_path = $instrument_data->bam_path;
ok($bam_via_bam_path, 'got bam via bam path');
ok(-s $bam_via_bam_path, 'bam via bam path exists');
is($bam_via_bam_path, $allocation->absolute_path.'/all_sequences.bam', 'bam via bam path named correctly');

my $bam_via_attrs = eval{ $instrument_data->attributes(attribute_label => 'bam_path')->attribute_value; };
ok($bam_via_attrs, 'got bam via attrs');
ok(-s $bam_via_attrs, 'bam via attrs exists');
is($bam_via_attrs, $allocation->absolute_path.'/all_sequences.bam', 'bam via attrs named correctly');

is(File::Compare::compare($bam_via_archive_path, $test_dir.'/test.sra.bam'), 0, 'sra dumped and sorted bam matches');

# flagstat
is(File::Compare::compare($bam_via_archive_path.'.flagstat', $test_dir.'/test.sra.bam.flagstat'), 0, 'flagstat matches');

#print $cmd->instrument_data->allocations->absolute_path."\n"; <STDIN>;
done_testing();
