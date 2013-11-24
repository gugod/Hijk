package Hijk::HTTP::XS;

use 5.018001;
use strict;
use warnings;
use Carp;

require Exporter;
use AutoLoader;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Hijk::HTTP::XS ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
  fetch
);

our $VERSION = '0.01';

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&Hijk::HTTP::XS::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) { croak $error; }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
#XXX	if ($] >= 5.00561) {
#XXX	    *$AUTOLOAD = sub () { $val };
#XXX	}
#XXX	else {
	    *$AUTOLOAD = sub { $val };
#XXX	}
    }
    goto &$AUTOLOAD;
}

require XSLoader;
XSLoader::load('Hijk::HTTP::XS', $VERSION);

# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
=head1 NAME

Hijk::HTTP::XS - Simple XS http request parser using https://github.com/joyent/http-parser

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);
    use Data::Dumper;
    use Hijk::HTTP::XS qw(fetch);

    my $soc;
    socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die $!;
    connect($soc, sockaddr_in(80, inet_aton('google.com')))   || die $!;
    syswrite($soc,"GET / HTTP1/1.1$CRLF$CRLF")                || die $!;

    my ($status,$body,$headers) = fetch(fileno($soc));
    print Data::Dumper::Dumper([$status,$body,$headers]);

  
=head1 DESCRIPTION
  very simple http request parser, does not support gzip/ssl or anything

=head1 EXPORT

=over 4

=item Hijk::HTTP::XS::fetch($fd) returns ($status,$body,$headers)

the only exported function, parses the http response and returns
status_code,request body, headers hashref. Requires file descriptor
so you just have to pass fileno($socket) to it 

=back

=head1 INSTALL

=over 4

  perl Makefile.PL
  make
  make test
  make install

=back

=head1 AUTHOR

=over 4

=item Kang-min Liu <gugod@gugod.org>

=item Borislav Nikolov <jack@sofialondonmoskva.com>

=back

=head1 COPYRIGHT

Copyright (c) 2013 Borislav Nikolov C<< <jack@sofialondonmoskva.com> >>.

=head1 LICENCE

The MIT License

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut
