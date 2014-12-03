package Genome::VariantReporting::Command::CreateCombinedReports;

use strict;
use warnings FATAL => 'all';
use Genome;

my $FACTORY = Genome::VariantReporting::Framework::Factory->create();

class Genome::VariantReporting::Command::CreateCombinedReports {
    is => 'Command::V2',
    has_input => [
        combination_label => {
            is => 'Text',
            doc => 'A way to distinguish this set of reports from others.',
        },
        snvs_input_vcf => {
            is => 'Path',
            doc => 'The source of variants to create a report from',
        },
        snvs_plan_file => {
            is => 'Path',
            doc => 'A plan (yaml) file describing the report generation workflow',
        },
        snvs_translations_file => {
            is => 'Path',
            doc => 'A yaml file containing key-value pairs where the key is a value from the plan file that needs to be translated at runtime',
        },

        indels_input_vcf => {
            is => 'Path',
            doc => 'The source of variants to create a report from',
        },
        indels_plan_file => {
            is => 'Path',
            doc => 'A plan (yaml) file describing the report generation workflow',
        },
        indels_translations_file => {
            is => 'Path',
            doc => 'A yaml file containing key-value pairs where the key is a value from the plan file that needs to be translated at runtime',
        },

        use_header_from => {
            is => 'Text',
            valid_values => ['snvs', 'indels'],
            doc => 'Use the header from this report type in the combined report',
            is_optional => 1,
        },
    ],
    has_transient_optional => [
        dag => {
            is => 'Genome::WorkflowBuilder::DAG',
        },
    ],
};

# This can be made into a Process/Command pair by defining
# execute to create the process and then run it.  This is not
# needed at this time though, and so it has not been implemented.

sub dag {
    my $self = shift;

    unless (defined($self->__dag)) {
        my $dag = Genome::WorkflowBuilder::DAG->create(
            name => sprintf('Create Snvs, Indels, and Combined Reports (%s)',
                $self->combination_label),
        );
        my $snvs_dag = $self->get_connected_dag($dag, 'snvs');
        my $indels_dag = $self->get_connected_dag($dag, 'indels');
        $self->connect_combine_operations($dag, $snvs_dag, $indels_dag);

        $self->__dag($dag);
    }
    return $self->__dag;
}

sub get_connected_dag {
    my $self = shift;
    my $outer_dag = shift;
    my $variant_type = shift;

    my $input_vcf_accessor = sprintf("%s_input_vcf", $variant_type);
    my $plan_file_accessor = sprintf("%s_plan_file", $variant_type);
    my $translations_file_accessor = sprintf("%s_translations_file",
        $variant_type);

    my $cmd = Genome::VariantReporting::Command::CreateReport->create(
        input_vcf => $self->$input_vcf_accessor,
        variant_type => $variant_type,
        plan_file => $self->$plan_file_accessor,
        translations_file => $self->$translations_file_accessor,
    );
    my $dag = $cmd->dag;
    $outer_dag->connect_input(
        input_property => 'process_id',
        destination => $dag,
        destination_property => 'process_id',
    );

    for my $output_name ($dag->output_properties) {
        if ($output_name =~ m/output_result \((.*)\)/) {
            my $report_name = $1;

            $outer_dag->connect_output(
                output_property => sprintf('%s_result (%s)', $variant_type,
                    $report_name),
                source => $dag,
                source_property => $output_name,
            );

            $self->redeclare_label_constant($dag, $report_name, $variant_type);
        }
    }
    $outer_dag->add_operation($dag);

    return $dag;
}

sub redeclare_label_constant {
    my $self = shift;
    my $dag = shift;
    my $report_name = shift;
    my $variant_type = shift;

    my $input_name = sprintf('Generate Report (%s).label', $report_name);
    my $value = sprintf('%s.%s.%s', $self->combination_label,
        $report_name, $variant_type);
    $dag->declare_constant(
        $input_name => $value,
    );
}

sub connect_combine_operations {
    my $self = shift;
    my $dag = shift;
    my $snvs_dag = shift;
    my $indels_dag = shift;

    for my $output_name ($snvs_dag->output_properties) {
        if ($output_name =~ m/output_result \((.*)\)/) {
            my $report_name = $1;
            my $report_class = $FACTORY->get_class('reports', $report_name);
            next unless $report_class->can_be_combined;

            my $combine_op = Genome::WorkflowBuilder::Command->create(
                name => sprintf('Combine Reports (%s)', $report_name),
                command => 'Genome::VariantReporting::Command::CombineReports',
            );

            my $converge = Genome::WorkflowBuilder::Converge->create(
                output_properties => ['report_results'],
                name => "Converge ($output_name)",
            );
            $dag->add_operation($converge);

            $dag->create_link(
                source => $snvs_dag,
                source_property => $output_name,
                destination => $converge,
                destination_property => 'snvs_report_result',
            );

            $dag->create_link(
                source => $indels_dag,
                source_property => $output_name,
                destination => $converge,
                destination_property => 'indels_report_result',
            );

            $dag->create_link(
                source => $converge,
                source_property => 'report_results',
                destination => $combine_op,
                destination_property => 'report_results',
            );

            if (defined($self->use_header_from) && $self->use_header_from eq 'indels') {
                $dag->create_link(
                    source => $indels_dag,
                    source_property => $output_name,
                    destination => $combine_op,
                    destination_property => 'use_header_from',
                );
            } else {
                $dag->create_link(
                    source => $snvs_dag,
                    source_property => $output_name,
                    destination => $combine_op,
                    destination_property => 'use_header_from',
                );
            }

            $combine_op->declare_constant(
                label => sprintf('%s.%s.combined',
                    $self->combination_label, $report_name),
                %{$report_class->combine_parameters},
            );
            # this has to be done AFTER the constants are declared.
            $dag->add_operation($combine_op);

            $dag->connect_input(
                input_property => 'process_id',
                destination => $combine_op,
                destination_property => 'process_id',
            );

            $dag->connect_output(
                output_property => sprintf('combined_result (%s)', $report_name),
                source => $combine_op,
                source_property => 'output_result',
            );
        }
    }
}

1;
