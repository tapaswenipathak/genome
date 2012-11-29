#!/usr/bin/env genome-perl
use strict;
use warnings;
use Test::More tests => 43; 

use above 'Genome';


BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

###

class Genome::Bar { };

###
{
package Genome::Foo;

use Sys::Hostname;

class Genome::Foo {
    is => 'Genome::SoftwareResult::Stageable',
    has_param => [
        p1 => { is => 'Text' },
        p2 => { is => 'Number' },
        p3 => { is => 'Genome::Bar' },
        p4 => { is => 'Number', is_many => 1 },
        p5 => { is => 'Genome::Bar', is_many => 1 },
        p6 => { is => 'Boolean', default_value => 1 },
        initial_du => { is => 'Number', is_optional => 1 },
        realloc_du => { is => 'Number', is_optional => 1 },
    ],
    has_input => [
        i1 => { is => 'Text' },
        i2 => { is => 'Number' },
        i3 => { is => 'Genome::Bar' },
        i4 => { is => 'Number', is_many => 1 },
        i5 => { is => 'Genome::Bar', is_many => 1 },
    ],
    has_metric => [
        # not yet supported
        m1 => { is => 'Text' },
        m2 => { is => 'Number' },
        #m3 => { is => 'Genome::Bar' },
        #m4 => { is => 'Number', is_many => 1 },
        #m5 => { is => 'Genome::Bar', is_many => 1 },
    ],
};

sub create {

    my $class = shift;

    my $self = $class->SUPER::create(@_);

    print "_prepare_staging_directory\n";
    $self->_prepare_staging_directory;

    open(my $fh, '>'.$self->temp_staging_directory.'/test'); 
    print $fh 'hello' x 1000;

    print "_prepare_output_directory\n";
    $self->_prepare_output_directory;
    my ($alloc) = $self->disk_allocations();
    $self->initial_du($alloc->kilobytes_requested());

    print "_promote_data\n";
    $self->_promote_data;
    print "_reallocate_disk_allocation\n";
    $self->_reallocate_disk_allocation; 

    $self->realloc_du($alloc->kilobytes_requested);
    $self->lookup_hash($self->calculate_lookup_hash);

    close($fh);
    return $self;
}

sub resolve_allocation_disk_group_name {
    return 'info_genome_models';
}

sub resolve_allocation_subdirectory {
    my $self = shift;
    my $hostname = hostname;

    my $user = $ENV{'USER'};
    my $base_dir = sprintf("sxresult-%s-%s-%s-%s",           $hostname, $user, $$, $self->id);
    my $directory = join('/', 'build_merged_alignments',$self->id,$base_dir);
    return $directory;
}

sub resolve_module_version { 
    $DB::single = 1;
    shift->Genome::SoftwareResult::resolve_module_version(@_)
}

}

###

use_ok('Genome::SoftwareResult');

my $template = 'Genome-SoftwareResult-'. Genome::Sys->username .'-XXXX';
my $tmp_dir = File::Temp::tempdir($template,CLEANUP => 1);

my @b;
for my $id (-1231, -1232, -1233, -1234) {
    my $bn = Genome::Bar->create(id => $id);
    ok($bn, "made an object to be used as a has-many input and a param");
    push @b, $bn;
}

# this 4th object is used for difference testing below
my $extra_b = pop @b;

my %params = (
    p1 => "phello",
    p2 => 101,
    p3 => $b[0],
    p4 => [1011,1012,1013],
    p5 => \@b,
    
    i1 => "ihello",
    i2 => 102,
    i3 => $b[1],
    i4 => [1021,1022,1023],
    i5 => \@b,
    
    m1 => "mhello",
    m2 => 103,
    #m3 => $b[2],
    #i4 => [1031,1032,1033],
    #i5 => \@b,
);
my $f = Genome::Foo->get_or_create(
    %params,  
);
ok($f, "made a software result");

cmp_ok($f->initial_du,'==',$f->realloc_du,"initial kilobytes_requested matched reallocation size (".$f->initial_du."KB)");

$DB::single = 1;
#print Data::Dumper::Dumper([$f->i4],[$f->i5]);
#exit;

is($f->p1, 'phello', 'p1 text matches');
is($f->p2, 101, 'p2 number matches');
is($f->p3, $b[0], 'p3 object matches');
is_deeply([$f->p4],[1011,1012,1013], 'p4 list of numbers match'); 
is_deeply([$f->p5],\@b, 'p5 list of objects match'); 

is($f->i1, 'ihello', 'i1 text matches');
is($f->i2, 102, 'i2 number matches');
is($f->i3, $b[1], 'i3 object matches');
is_deeply([$f->i4],[1021,1022,1023], 'i4 list of numbers match'); 
is_deeply([$f->i5],\@b, 'i5 list of objects match'); 

is($f->m1, 'mhello', 'm1 text matches');
is($f->m2, 103, 'm2 number matches');
#is($f->m3, $b[2], 'm3 object matches');
#is_deeply([$f->m4],[1031,1032,1033], 'm4 list of numbers match'); 
#is_deeply([$f->m5],\@b, 'm5 list of objects match'); 


eval { 
    #local $ENV{UR_DBI_MONITOR_DML} = 1;
    local $ENV{UR_DBI_NO_COMMIT} = 1; # this is above but just to be sure
    UR::Context->commit; 
};

ok(!$@, "no exception during save (commit disabled)!")
    or diag("exception: $@");

my $prev_id = $f->id;
my $initial_du = $f->initial_du;
my $realloc_du = $f-> realloc_du;
print Data::Dumper::Dumper($f);
for ($f->params, $f->inputs, $f) {
    $_->unload;
}

# do it again with the same params and be sure it shortcuts
my $f2 = Genome::Foo->get_or_create(
    %params,
    initial_du => $initial_du,
    realloc_du => $realloc_du,
);

ok($f2, "got a software result on the second call");
is($f2->id, $prev_id, "the id matches that of the first one");

# do it again with different params and be sure it does NOT shortcut
my %prev_ids = ($f->id => $f, $f2->id => $f2);
for my $p (grep { /^[ip]/ } sort keys %params) {
    my $old = $params{$p};
    
    my $new;
    if ($p =~ /.1/) {
        $new = $old . "changed"
    }
    elsif ($p =~ /.2/) {
        $new = $old + 10000;
    }
    elsif ($p =~ /.3/) {
        if ($old == $b[0]) {
            $new = $b[1]
        }
        else {
            $new = $b[0]
        }
    }
    elsif ($p =~ /.4/) {
        $new = [ $old->[0]+20000, @$old[1,2] ];
    }
    elsif ($p =~ /.5/) {
        $new = [ $extra_b, @$old[1,2] ];
    }

    my %new_params = (%params);
    $new_params{$p} = $new;

    my $new_printable = (ref($new) eq 'ARRAY' ? join(",",@$new) : $new);

    my $alt_obj = Genome::Foo->get_or_create(%new_params);
    ok($alt_obj, "got object for params with altered $p of $new_printable");

    my $new_id = $alt_obj->id;
    ok(!$prev_ids{$new_id}, "new object was created with $new_id, which did not exist previously, for params with altered $p of $new_printable");

    # remember to make sure we don't get the above object again
    $prev_ids{$new_id} = $alt_obj;
}

eval { 
    #local $ENV{UR_DBI_MONITOR_DML} = 1;
    local $ENV{UR_DBI_NO_COMMIT} = 1; # this is above but just to be sure
    UR::Context->commit; 
};

ok(!$@, "no exception during save (commit disabled)!")
    or diag("exception: $@");


