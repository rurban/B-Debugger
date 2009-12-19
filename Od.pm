package Od;

our $VERSION = '0.10';

use B qw(main_root walkoptree_slow);
use Carp;

sub import {
    my ($class, @options) = @_;
    my $fh;
    my $backend = shift (@options);
    eval q[
	BEGIN { my $compile; }
	CHECK {
	    use B::].$backend.q[ ();
	    if ($@) { croak "use of backend $backend failed: $@"; }
	    $compile = &{"B::${backend}::compile"}(@options);
	    die $compile if ref($compile) ne "CODE";
        }
	INIT {
	    # local $savebackslash = $\; local ($\,$",$,) = (undef,' ','');
	    &$compile();
	}
    ];
    die $@ if $@;
}

1;

__END__

=head1 NAME

Od - Debug a Perl Compiler backend

=head1 SYNOPSIS

	perl -d -MOd=Backend[,OPTIONS] foo.pl

	Od::CODE(0x154c5a0)((eval 9)[lib/Od.pm:33]:25):
	25:                 &$compile();
	DB<1> s
	B::C::CODE(0x12c0aa0)(lib/B/C.pm:3163):
	3163:       return sub { save_main() };
	DB<1> s
	B::C::save_main(lib/B/C.pm:2881):
	2881:     my $warner = $SIG{__WARN__};

=head1 DESCRIPTION

This module is a debugging replacement to L<O>, the B<Perl Compiler> frontend.

It delays the start of the B compiler C<compile> function from the CHECK block
to the INIT block, so that the Perl debugger can be started there.

=head1 AUTHOR

Reini Urban, C<rurban@cpan.org> 2009

=cut
