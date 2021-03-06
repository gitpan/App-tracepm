package App::tracepm::Tracer;

our $VERSION = '0.14'; # VERSION

# saving CORE::GLOBAL::require doesn't work
my $orig_require;

sub import {
    my $self = shift;

    # already installed
    return if $orig_require;

    my $opts = {
        workaround_log4perl => 1,
    };
    if (@_ && ref($_[0]) eq 'HASH') {
        $opts = shift;
    }

    my $file = shift
        or die "Usage: use App::tracerpm::Tracer '/path/to/output'";

    open my($fh), ">", $file or die "Can't open $file: $!";

    #$orig_require = \&CORE::GLOBAL::require;
    *CORE::GLOBAL::require = sub {
        my ($arg) = @_;
        my $caller = caller;
        if ($INC{$arg}) {
            if ($opts->{workaround_log4perl}) {
                # Log4perl <= 1.43 still does 'eval "require $foo" or ...'
                # instead of 'eval "require $foo; 1" or ...' so running will
                # fail. this workaround makes require() return 1.
                return 1 if $caller =~ /^Log::Log4perl/;
            }
            return 0;
        }
        unless ($arg =~ /\A\d/) { # skip 'require 5.xxx'
            print $fh $arg, "\t", $caller, "\n";
        }

        #$orig_require->($arg);
        CORE::require($arg);
    };
}

1;
# ABSTRACT: Trace module require to file

__END__

=pod

=encoding UTF-8

=head1 NAME

App::tracepm::Tracer - Trace module require to file

=head1 VERSION

This document describes version 0.14 of App::tracepm::Tracer (from Perl distribution App-tracepm), released on 2015-01-03.

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

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
