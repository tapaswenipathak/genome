package Genome::Model::Command::Admin::RemoveDiskAllocationsFromTestdb;

use strict;
use warnings;

use Genome;
use DBI;
use TestDbServer::CmdLine qw(search_databases get_template_by_id get_database_by_id);
use Genome::Config;
use Try::Tiny;
use Sub::Install qw();
use Sub::Name qw();

use constant KB_IN_ONE_GB => 1024 * 1024;

class Genome::Model::Command::Admin::RemoveDiskAllocationsFromTestdb {
    is => 'Command::V2',
    doc => 'Remove disk allocations that were created while running under a test database',
    has => [
        database_name => {
            is => 'Text',
            default_value => _get_default_database_name(),
            doc => 'test database name, derived from the ds_gmschema_server config value',
        },
        database_server => {
            is => 'Text',
            default_value => _get_default_database_server(),
            doc => 'database server name, derived from the ds_gmschema_server config value',
        
        },
        database_port => {
            is => 'Text',
            default_value => _get_default_database_port(),
            doc => 'database listening port, derived from the ds_gmschema_server config value',
        },
        template_name => {
            is => 'Text',
            default_value => _get_default_template_name(),
            doc => 'template database name, resolved from the database host in the ds_gmschema_server config value',
        },
    ],
};

sub _get_default_database_name {
    my $conn = _parse_database_connection_info_from_env_var();
    return $conn->{dbname};
}

sub _get_default_database_server {
    my $conn = _parse_database_connection_info_from_env_var();
    return $conn->{host};
}

sub _get_default_database_port {
    my $conn = _parse_database_connection_info_from_env_var();
    return( $conn->{port} // 5432 );
}

sub _get_default_template_name {
    my $test_db_name = __PACKAGE__->_get_default_database_name();
    return __PACKAGE__->get_template_name_for_database_name($test_db_name);
}

sub _parse_database_connection_info_from_env_var {
    my %connection;
    foreach my $key ( qw( dbname host port ) ) {
        no warnings 'uninitialized';
        ($connection{$key}) = $ENV{XGENOME_DS_GMSCHEMA_SERVER} =~ m/$key=(.*?)(?:;|$)/;
    }
    return \%connection;
}

sub execute {
    my $self = shift;

    unless ($self->is_running_in_test_env) {
        die $self->error_message('Must be run within a test environment created with genome-test-env');
    }

    my @allocations = $self->collect_newly_created_allocations();
    $self->report_allocations_to_delete(@allocations);
    $self->delete_allocations(@allocations);
    return 1;
}

sub is_running_in_test_env {
    my $self = shift;

    return $ENV{XGENOME_TESTING};
}

sub collect_newly_created_allocations {
    my $self = shift;

    my $tmpl_allocations = $self->_make_iterator_for_template_allocations();
    my $db_allocations = $self->_make_iterator_for_database_allocations();

    my @new_allocations_in_database;
    my($next_tmpl_allocation, $next_db_allocation);
    while(1) {
        unless (defined $next_tmpl_allocation) {
            $next_tmpl_allocation = $tmpl_allocations->();
        }
        unless (defined $next_db_allocation) {
            $next_db_allocation = $db_allocations->();
        }

        last unless defined($next_db_allocation);

        if (!defined($next_tmpl_allocation)
            or
            $next_tmpl_allocation->id gt $next_db_allocation->id
        ) {
            # This allocation was created in the test database
            push @new_allocations_in_database, $next_db_allocation;
            undef($next_db_allocation);

        } elsif ($next_tmpl_allocation->id eq $next_db_allocation->id) {
            # this allocation exists in both the template and test database, ignore it
            undef($next_tmpl_allocation);
            undef($next_db_allocation);

        } else {
            # This allocation was deleted in the test database?!
            undef($next_tmpl_allocation);

        }
    }
    return @new_allocations_in_database;
}

sub _make_iterator_for_template_allocations {
    my $self = shift;
    my $dbh = $self->_dbh_for_template();
    return $self->_make_iterator_for_fetching_allocations($dbh);
}

sub _make_iterator_for_database_allocations {
    my $self = shift;
    my $dbh = $self->_dbh_for_database();
    return $self->_make_iterator_for_fetching_allocations($dbh);
}

my $sql_for_allocations = q(SELECT id, kilobytes_requested FROM disk.allocation ORDER BY id);
sub _make_iterator_for_fetching_allocations {
    my($self, $dbh) = @_;
    my $sth = $dbh->prepare($sql_for_allocations);
    $sth->execute();

    return sub {
        my @row = $sth->fetchrow_array;
        return unless @row;
        return Genome::Disk::StrippedDownAllocation->new(id => $row[0], kilobytes_requested => $row[1]);
    };
}


sub _dbh_for_template {
    my $self = shift;
    return $self->_dbh_for('template');
}

sub _dbh_for_database {
    my $self = shift;
    return $self->_dbh_for('database');
}

sub _dbh_for {
    my($self, $db_or_tmpl) = @_;

    my $db_name = $db_or_tmpl eq 'database'
                    ? $self->database_name
                    : $self->template_name;
    my $db_host = $self->database_server;
    my $db_port = $self->database_port;

    return DBI->connect("dbi:Pg:dbname=${db_name};host=${db_host};port=${db_port}",
                        Genome::Config::get('ds_gmschema_login'),
                        Genome::Config::get('ds_gmschema_auth'),
                        { AutoCommit => 0, RaiseError => 1, PrintError => 0 });
}


sub report_allocations_to_delete {
    my($self, @allocations) = @_;

    my $kb_sum = 0;
    foreach my $alloc ( @allocations ) {
        $kb_sum += $alloc->kilobytes_requested;
    }

    $self->status_message('Removing %d GB in %d allocations.',
                          int($kb_sum / KB_IN_ONE_GB),
                          scalar(@allocations));
}

sub delete_allocations {
    my $self = shift;

}

sub get_template_name_for_database_name {
    my($self, $db_name) = @_;

    my $tmpl_name;
    try {
        my @database_ids = search_databases(name => $db_name);
        unless (@database_ids == 1) {
            die $self->error_message('Expected 1 database named %s but got %d', $db_name, scalar(@database_ids));
        }

        my $database = get_database_by_id($database_ids[0]);
        my $tmpl = get_template_by_id($database->{template_id});
        $tmpl_name = $tmpl->{name};
    };
    return $tmpl_name;
}

package Genome::Disk::StrippedDownAllocation;

use constant required_attrs => qw(id kilobytes_requested);

sub new {
    my($class, %params) = @_;
    foreach my $attr_name ( required_attrs ) {
        unless (exists $params{$attr_name}) {
            Carp::croak("$attr_name is a required atrtibute of ".__PACKAGE__);
        }
    }
    return bless \%params, $class;
}

foreach my $attr_name ( required_attrs ) {
    my $full_name = join('::', __PACKAGE__, $attr_name);
    my $code = Sub::Name::subname $full_name => sub {
        my $self = shift;
        if (@_) {
            $self->{$attr_name} = shift;
        }
        return $self->{$attr_name};
    };
    Sub::Install::install_sub({
        code => $code,
        as => $attr_name,
    });
}

1;
