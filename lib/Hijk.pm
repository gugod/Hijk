package Hijk;
use 5.008;
use strict;
use warnings;
use POSIX;
use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);
our $VERSION = "0.01";

eval {
    require Hijk::HTTP::XS;
    *fetch = \&Hijk::HTTP::XS::fetch;
    1;
} or do {
    *fetch = \&Hijk::pp_fetch;
};

my $SocketCache = {};

sub pp_fetch {
    my $fd = shift || die "need file descriptor";
    my ($head,$neck,$body,$buf) = ("", "${CRLF}${CRLF}");
    my ($block_size, $decapitated, $status_code) = (10240);
    my $header = {};
    do {
        # it blocks until receives at least $block_size
        my $nbytes = POSIX::read($fd, $buf, $block_size);
        if (defined($nbytes)) {
            if ($decapitated) {
                $body .= $buf;
                $block_size -= $nbytes;
            }
            else {
                my $neck_pos = index($buf, $neck);
                if ($neck_pos > 0) {
                    $decapitated = 1;
                    $head .= substr($buf, 0, $neck_pos);
                    $status_code = substr($head, 9, 3);
                    substr($head, 0, index($head, "${CRLF}")+length($CRLF), "");

                    for (split /${CRLF}/o, $head) {
                        my ($key, $value) = split /: /, $_, 2;
                        $header->{$key} = $value;
                    }

                    if ($header->{'Content-Length'}) {
                        $body = substr($buf, $neck_pos + length($neck));
                        $block_size = $header->{'Content-Length'} - length($body);
                    }
                    else {
                        $block_size = 0;
                        $body = "";
                    }
                }
                else {
                    $head = $buf;
                }
            }
        }
        else {
            die "Failed to read http " .( $decapitated ? "body": "head" ). " from socket";
        }
    } while( !$decapitated || $block_size );

    return ($status_code, $body, $header);
}

sub build_http_message {
    my $args = $_[0];
    my $path_and_qs = ($args->{path} || "/") . ( defined($args->{query_string}) ? ("?".$args->{query_string}) : "" );
    return join(
        $CRLF,
        ($args->{method} || "GET")." $path_and_qs HTTP/1.1",
        "Host: $args->{host}",
        $args->{body} ? ("Content-Length: " . length($args->{body})) : (),
        "",
        $args->{body} ? $args->{body} : ()
    ) . $CRLF;
}

sub request {
    my $args = $_[0];
    my $soc = $SocketCache->{"$args->{host};$args->{port};$$"} ||= do {
        my $soc;
        socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die $!;
        connect($soc, sockaddr_in($args->{port}, inet_aton($args->{host}))) || die $!;
        $soc;
    };
    my $r = build_http_message($args);
    die "send error ($r) $!"
        if syswrite($soc,$r) != length($r);

    my ($status,$body) = fetch(fileno($soc));
    return {
        status => $status,
        body => $body
    };
}

1;

__END__

=encoding utf8

=head1 NAME

Hijk - Specialized HTTP client

=head1 SYNOPSIS

    my $res = Hijk::request({
        host => "example.com",
        port => "80",
        path => "/flower",
        query_string => "color=red"
    });

    die unless ($res->{status} == "200"); {

    say $res->{body};

=head1 DESCRIPTION

Hijk is a specialized HTTP Client that does nothing but transporting the
response body back. It does not feature as a "user agent", but as a dumb
client. It is suitble for connecting to data servers transporting via HTTP
rather then web servers.

Most of HTTP features like proxy, redirect, Transfer-Encoding, or SSL are not
supported at all. For those requirements we already have many good HTTP clients
like L<HTTP::Tiny>, L<Furl> or L<LWP::UserAgent>.

=head1 FUNCTIONS

=over 4

=item Hijk::request( $args :HashRef ) :HashRef

This is the only function to be used. It is not exported to its caller namespace
at all. It takes a request arguments in HashRef and returns the response in HashRef.

The C<$args> request arg should contain key-value pairs from the following
table. The value for C<host> and C<port> are mandatory and others are optional
with default values listed below

=over 4

=item host => ...

=item port => ...

=item method => "GET"

=item path => "/"

=item query_string => ""

=item body => ""

=back

Too keep the implementation straight-forward, Hijk does not take full URL string
as input.

The return vaue is a HashRef representing a response. It contains the following
key-value pairs.

=over 4

=item status => :StatusCode

=item body => :Str

=back

For example, to send request to C<http://example.com/flower?color=red>, use the
following code:

    my $res = Hijk::request({
        host => "example.com",
        port => "80",
        path => "/flower",
        query_string => "color=red"
    });
    die "Response is not OK" unless $res->{status} ne "200";

Notice that you do not need to put the leading C<"?"> character in the
C<query_string>. You do, however, need to propery C<uri_escape> the content of
C<query_string>.

All values are assumed to be valid. Hijk simply passthru the values without
validating the content. It is possible that it constructs invalid HTTP Messages.
Users should keep this in mind when using Hijk.

=head1 AUTHORS

=over 4

=item Kang-min Liu <gugod@gugod.org>

=item Borislav Nikolov

=back

=head1 COPYRIGHT

Copyright (c) 2013 Kang-min Liu C<< <gugod@gugod.org> >>.

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
