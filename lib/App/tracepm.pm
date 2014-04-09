package App::tracepm;

use 5.010001;
use strict;
use warnings;
#use experimental 'smartmatch';
use Log::Any '$log';

use File::Temp qw(tempfile);
use Module::CoreList;
use SHARYANTO::Module::Util qw(is_xs);
use version;

our $VERSION = '0.02'; # VERSION

our %SPEC;

our $tablespec = {
    fields => {
        module  => {schema=>'str*' , pos=>0},
        require => {schema=>'str*' , pos=>1},
        seq     => {schema=>'int*' , pos=>2},
        is_xs   => {schema=>'bool' , pos=>3},
        is_core => {schema=>'bool*', pos=>4},
    },
    pk => 'module',
};

$SPEC{tracepm} = {
    v => 1.1,
    args => {
        script => {
            summary => 'Path to script file (script to be packed)',
            schema => ['str*'],
            req => 1,
            pos => 0,
        },
        method => {
            summary => 'Tracing method to use',
            schema => ['str*', in=>[qw/fatpacker require/]],
            default => 'fatpacker',
            description => <<'_',

There are two tracing methods that can be used. The first (and default) is
`fatpacker`, using `fatpacker trace`. This method runs the script using `perl
-c` option then collect the populated `%INC`. Only modules loaded during compile
time are detected.

The second method (`require`) runs your script normally, but replaces
`CORE::GLOBAL::require()` with a routine that logs the require() argument to the
log file. Modules loaded during runtime is also logged. But some modules might
not work, specifically modules that also overrides require() (there should be
only a handful of modules that do this though).

_
        },
        args => {
            summary => 'Script arguments',
            schema => ['array*' => of => 'str*'],
            req => 0,
            pos => 1,
            greedy => 0,
        },
        perl_version => {
            summary => 'Perl version, defaults to current running version',
            description => <<'_',

This is for determining which module is core (the list differs from version to
version. See Module::CoreList for more details.

_
            schema => ['str*'],
            cmdline_aliases => { V=>{} },
        },
        use => {
            summary => 'Additional modules to "use"',
            schema => ['array*' => of => 'str*'],
            description => <<'_',

This is like running:

    perl -MModule1 -MModule2 script.pl

_
        },
        detail => {
            summary => 'Whether to return records instead of just module names',
            schema => ['bool' => default=>0],
            tags => ['category:field-selection'],
        },
        core => {
            summary => 'Filter only modules that are in core',
            schema  => 'bool',
            tags => ['category:filtering'],
        },
        xs => {
            summary => 'Filter only modules that are XS modules',
            schema  => 'bool',
            tags => ['category:filtering'],
        },
        # fields
    },
    result => {
        table => { spec=>$tablespec },
    },
};
sub tracepm {
    my %args = @_;

    my $method = $args{method};
    my $plver = version->parse($args{perl_version} // $^V);

    my ($outfh, $outf) = tempfile();

    if ($method eq 'fatpacker') {
        require App::FatPacker;
        my $fp = App::FatPacker->new;
        $fp->trace(
            output => ">>$outf",
            use    => $args{use},
            args   => [$args{script}, @{$args{args} // []}],
        );
    } else {
        system($^X,
               "-MApp::tracepm::Tracer=$outf",
               (map {"-M$_"} @{$args{use} // []}),
               $args{script}, @{$args{args} // []},
           );
    }

    open my($fh), "<", $outf
        or die "Can't open trace output: $!";

    my @res;
    my $i = 0;
    while (<$fh>) {
        chomp;
        $log->trace("got line: $_");
        $i++;
        my $r = {seq=>$i, require=>$_};

        unless (/(.+)\.pm\z/) {
            warn "Skipped non-pm entry: $_\n";
            next;
        }

        my $mod = $1; $mod =~ s!/!::!g;
        $r->{module} = $mod;

        if ($args{detail} || defined($args{core})) {
            my $is_core = Module::CoreList::is_core($mod, undef, $plver);
            next if defined($args{core}) && ($args{core} xor $is_core);
            $r->{is_core} = $is_core;
        }

        if ($args{detail} || defined($args{xs})) {
            my $is_xs = is_xs($mod);
            next if defined($args{xs}) && (
                !defined($is_xs) || ($args{xs} xor $is_xs));
            $r->{is_xs} = $is_xs;
        }

        push @res, $r;
    }

    unlink $outf;

    unless ($args{detail}) {
        @res = map {$_->{module}} @res;
    }

    my $ff = $tablespec->{fields};
    my @ff = sort {$ff->{$a}{pos} <=> $ff->{$b}{pos}} keys %$ff;
    [200, "OK", \@res, {"table.fields" => \@ff}];
}

1;
# ABSTRACT: Trace dependencies of your Perl script file

__END__

=pod

=encoding UTF-8

=head1 NAME

App::tracepm - Trace dependencies of your Perl script file

=head1 VERSION

version 0.02

=head1 SYNOPSIS

This distribution provides command-line utility called L<tracepm>.

=head1 FUNCTIONS


=head2 tracepm(%args) -> [status, msg, result, meta]

Arguments ('*' denotes required arguments):

=over 4

=item * B<args> => I<array>

Script arguments.

=item * B<core> => I<bool>

Filter only modules that are in core.

=item * B<detail> => I<bool> (default: 0)

Whether to return records instead of just module names.

=item * B<method> => I<str> (default: "fatpacker")

Tracing method to use.

There are two tracing methods that can be used. The first (and default) is
C<fatpacker>, using C<fatpacker trace>. This method runs the script using C<perl
-c> option then collect the populated C<%INC>. Only modules loaded during compile
time are detected.

The second method (C<require>) runs your script normally, but replaces
C<CORE::GLOBAL::require()> with a routine that logs the require() argument to the
log file. Modules loaded during runtime is also logged. But some modules might
not work, specifically modules that also overrides require() (there should be
only a handful of modules that do this though).

=item * B<perl_version> => I<str>

Perl version, defaults to current running version.

This is for determining which module is core (the list differs from version to
version. See Module::CoreList for more details.

=item * B<script>* => I<str>

Path to script file (script to be packed).

=item * B<use> => I<array>

Additional modules to "use".

This is like running:

    perl -MModule1 -MModule2 script.pl

=item * B<xs> => I<bool>

Filter only modules that are XS modules.

=back

Return value:

Returns an enveloped result (an array).

First element (status) is an integer containing HTTP status code
(200 means OK, 4xx caller error, 5xx function error). Second element
(msg) is a string containing error message, or 'OK' if status is
200. Third element (result) is optional, the actual result. Fourth
element (meta) is called result metadata and is optional, a hash
that contains extra information.

=for Pod::Coverage ^()$

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/App-tracepm>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-App-tracepm>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=App-tracepm>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
