package Hijk::HTTP::XS;
use strict;
use warnings;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Hijk::HTTP::XS', $VERSION);

{
    no warnings 'redefine';
     *Hijk::fetch = \&Hijk::HTTP::XS::fetch;
}

1;
__END__

=head1 NAME

Hijk::HTTP::XS - Simple XS http response parser using https://github.com/joyent/http-parser

=head1 SYNOPSIS

Use L<Hijk> with this XS version of http message parser:

    use Hijk;
    require Hijk::HTTP::XS;

Or directly use it to parse it out of a fd:

    use strict;
    use warnings;
    use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);
    use Data::Dumper;
    use Hijk::HTTP::XS;

    my $soc;
    socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die $!;
    connect($soc, sockaddr_in(80, inet_aton('google.com')))   || die $!;
    syswrite($soc,"GET / HTTP1/1.1$CRLF$CRLF")                || die $!;

    my ($status,$body,$headers) = Hijk::HTTP::XS::fetch(fileno($soc));
    print Data::Dumper::Dumper([$status,$body,$headers]);

=head1 DESCRIPTION

This is a very simple HTTP fetcher, it does not support fancy things
like gzip, ssl etc.
anything

=head1 FUNCTIONS

=head2 fetch

    Hijk::HTTP::XS::fetch($fd) returns ($status,$body,$headers)

Parses the http response and returns status_code,request body, headers
hashref. Requires file descriptor so you just have to pass
fileno($socket) to it

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
