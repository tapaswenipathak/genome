package Genome::Db::Ucsc::Base;

use strict;
use warnings;

use Genome;

use Exception::Class (
    'DatabaseResolutionFailure' => {
        fields => [
            'reference_name'
        ],
    },
);

class Genome::Db::Ucsc::Base {
    is => 'Command::V2',
    has_input => [
        filename => {
            is => 'Text',
            is_output => 1,
        },
        reference_name => {
            is => 'Text',
            valid_values => ["hg18", "hg19"],
        },
    ],
    has_optional_param => [
        db_user => {
            is => 'Text',
            default_value => 'genomep',
        },
        db_password => {
            is => 'Text',
            default_value => 'password',
        },
        db_host => {
            is => 'Text',
            default_value => 'genome-mysql.cse.ucsc.edu',
        },
    ],
    doc => "Fetches data from UCSC tables",
};

sub execute {
    my $self = shift;
    my $temp_output_file = eval { $self->_fetch_data_from_ucsc(); };
    if (my $e = Exception::Class->caught('DatabaseResolutionFailure')) {
        $self->status_message(sprintf(
                "Could not find gap database for reference name '%s'",
                $e->reference_name));
        return;
    }

    $self->_add_header_to_output_file();
    $self->_sort_into_output_file($temp_output_file);
    return 1;
}

sub _fetch_data_from_ucsc {
    my $self = shift;

    my ($database_name, $table_names) = $self->_resolve_database_and_table_names();
    my $query = $self->_resolve_query($table_names);
    my $temp_output_file = Genome::Sys->create_temp_file_path();
    my $command = sprintf(
        'mysql --user=%s --password=%s --host=%s -N -A -D %s -e \'%s\' > %s',
        $self->db_user, $self->db_password, $self->db_host,
        $database_name, $query, $temp_output_file);

    unless(Genome::Sys->shellcmd(cmd => $command)) {
        $self->error_message($!);
        die $self->error_message;
    }

    return $temp_output_file
}

sub _resolve_database_and_table_names {
    my $self = shift;

    my $database_name = $self->reference_name;
    my $table_names = $self->table_names($database_name);
    unless ($database_name && $table_names) {
        Exception::Class->throw('DatabaseResolutionFailure',
            reference_name => $self->reference_name);
    }
    return ($database_name, $table_names);
}

sub _resolve_query {
    my ($self, $table_names) = @_;

    my @select_statements;
    for my $tn (@{$table_names}) {
        push(@select_statements,
            sprintf("select %s from %s", join(", ", @{$self->headings}), $tn));
    }
    return join("; ", @select_statements);
}

sub _add_header_to_output_file {
    my $self = shift;

    my $header = sprintf("#%s\n", join("\t", @{$self->headings}));

    open my $fh, '>', $self->filename;
    print $fh $header;
    close $fh;
}

sub _sort_into_output_file {
    my ($self, $unsorted_filename) = @_;

    unless (-s $unsorted_filename) {
        $self->error_message("Empty file passed to sort.");
        die $self->error_message;
    }

    my $command = sprintf('sort -V %s >> %s',
        $unsorted_filename, $self->filename);

    Genome::Sys->shellcmd(cmd => $command);

    return $self->filename;
}

sub table_names {
    my $self = shift;
    $self->error_message("Must override table_names method in implementing class");
}

sub headings {
    my $self = shift;
    $self->error_message("Must override headings method in implementing class");
    return 0;
}

1;
