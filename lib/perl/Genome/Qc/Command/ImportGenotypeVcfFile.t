#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Test::Factory::Model::ReferenceSequence;
use Genome::Test::Factory::Build;

my $pkg = 'Genome::Qc::Command::ImportGenotypeVcfFile';
use_ok($pkg);

my $test_dir = __FILE__.'.d';
my $genotype_vcf_file = File::Spec->join($test_dir, 'genotype.vcf');
my $reference_sequence_model = Genome::Test::Factory::Model::ReferenceSequence->setup_object();
my $reference_sequence_build = Genome::Test::Factory::Build->setup_object(model_id => $reference_sequence_model->id);

my $cmd = $pkg->create(
    genotype_vcf_file => $genotype_vcf_file,
    reference_sequence_build => $reference_sequence_build,
);
isa_ok($cmd, $pkg);
ok($cmd->execute, 'Command executes correctly');

my $result = $cmd->output_result;
isa_ok($result, 'Genome::SoftwareResult::ImportedFile');
is($result->file_content_hash,  Genome::Sys->md5sum($genotype_vcf_file), 'File content hash is correct');

done_testing;
