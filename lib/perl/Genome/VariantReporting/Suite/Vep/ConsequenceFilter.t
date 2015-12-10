#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Test::Exception;
use Genome::File::Vcf::Entry;
use Genome::VariantReporting::Suite::Vep::TestHelper qw(create_vcf_header create_entry_with_vep);

my $pkg = 'Genome::VariantReporting::Suite::Vep::ConsequenceFilter';
use_ok($pkg);
my $factory = Genome::VariantReporting::Framework::Factory->create();
isa_ok($factory->get_class('filters', $pkg->name), $pkg);

my $filter = $pkg->create(consequences => ['missense_variant']);
my $filter2 = $pkg->create(consequences => ['frameshift_variant', 'inframe_insertion', 'inframe_deletion']);
lives_ok(sub {$filter->validate}, "Filter validates");

my $csq_format = 'Allele|Gene|Feature|Feature_type|Consequence|cDNA_position|CDS_position|Protein_position|Amino_acids|Codons|Existing_variation|DISTANCE|STRAND|SYMBOL|SYMBOL_SOURCE';

subtest "with no vep information" => sub {
    my %expected_return_values = (
        C => 0,
        G => 0,
    );
    my $entry = create_entry_with_vep('', $csq_format);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry gets filtered correctly");
};

subtest "with failing vep information" => sub {
    my %expected_return_values = (
        C => 0,
        G => 0,
    );
    my $entry = create_entry_with_vep('CSQ=C|ENSG00000035115|ENST00000356150|Transcript|INTRON_VARIANT||||||||-1|SH3YL1|HGNC', $csq_format);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry gets filtered correctly");
};

subtest "with passing vep information I" => sub {
    my %expected_return_values = (
        C => 1,
        G => 0,
    );
    my $entry = create_entry_with_vep('CSQ=C|ENSG00000035115|ENST00000356150|Transcript|MISSENSE_VARIANT||||||||-1|SH3YL1|HGNC', $csq_format);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry gets filtered correctly");
};

subtest "with passing vep information II" => sub {
    my %expected_return_values = (
        C => 0,
        G => 1,
    );
    my $entry = create_entry_with_vep('CSQ=G|ENSG00000035115|ENST00000356150|Transcript|MISSENSE_VARIANT&INTRON_VARIANT||||||||-1|SH3YL1|HGNC', $csq_format);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry gets filtered correctly");
};

subtest "with passing vep information III" => sub {
    my %expected_return_values = (
        C => 0,
        G => 1,
    );
    my $entry = create_entry_with_vep('CSQ=G|ENSG00000035115|ENST00000356150|Transcript|INTRON_VARIANT||||||||-1|SH3YL1|HGNC,G|ENSG00000035115|ENST00000356150|Transcript|MISSENSE_VARIANT||||||||-1|SH3YL1|HGNC', $csq_format);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry gets filtered correctly");
};

subtest "with passing vep information IV" => sub {
    my %expected_return_values = (
        C => 0,
        G => 1,
    );
    my $entry = create_entry_with_vep('CSQ=G|ENSG00000035115|ENST00000356150|Transcript|INFRAME_DELETION||||||||-1|SH3YL1|HGNC,G|ENSG00000035115|ENST00000356150|Transcript|MISSENSE_VARIANT||||||||-1|SH3YL1|HGNC', $csq_format);
    is_deeply({$filter2->filter_entry($entry)}, \%expected_return_values, "Entry gets filtered correctly");
};

subtest "with passing vep information V" => sub {
    my %expected_return_values = (
        C => 0,
        G => 1,
    );
    my $entry = create_entry_with_vep('CSQ=G|ENSG00000035115|ENST00000356150|Transcript|FRAMESHIFT_VARIANT&FEATURE_ELONGATION||||||||-1|SH3YL1|HGNC,G|ENSG00000035115|ENST00000356150|Transcript|MISSENSE_VARIANT||||||||-1|SH3YL1|HGNC', $csq_format);
    is_deeply({$filter2->filter_entry($entry)}, \%expected_return_values, "Entry gets filtered correctly");
};

subtest "test vcf_id and vcf_description" => sub {
    my $vcf_id = 'CONSEQUENCES_MISSENSE_VARIANT';
    my $vcf_description = 'Transcript consequence is one of: missense_variant';
    is($filter->vcf_id, $vcf_id, 'filter vcf_id created correctly');
    is($filter->vcf_description, $vcf_description, 'filter vcf_description created correctly');
};

done_testing;
