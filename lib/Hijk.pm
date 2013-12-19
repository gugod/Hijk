package Hijk;
use strict;
use warnings;
use POSIX qw(EINPROGRESS);
use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
our $VERSION = "0.09";
my $SocketCache = {};

sub Hijk::Error::CONNECT_TIMEOUT () { 1 << 0 } # 1
sub Hijk::Error::READ_TIMEOUT    () { 1 << 1 } # 2
sub Hijk::Error::TIMEOUT         () { Hijk::Error::READ_TIMEOUT() | Hijk::Error::CONNECT_TIMEOUT() } # 3
# sub Hijk::Error::WHATEVER      () { 1 << 2 } # 4

sub pp_fetch {
    my $fd = shift || die "need file descriptor";
    my ($timeout,$block_size,$header,$head,$body,$buf,$decapitated,$nfound,$nbytes) = (shift,10240,{},"");
    my $status_code = 0;
    $timeout /= 1000 if defined $timeout;
    vec(my $rin = '', $fd, 1) = 1;
    do {
        if ($timeout) {
            $nfound = select($rin, undef, undef, $timeout);
            die "select(2) error, errno = $!" if $nfound == -1;
            return (0,undef,undef, Hijk::Error::READ_TIMEOUT) unless $nfound == 1;
        }

        $nbytes = POSIX::read($fd, $buf, $block_size);

        die "Failed to read http " .( $decapitated ? "body": "head" ). " from socket. errno = $!"
            unless defined $nbytes;

        die "Failed to read http " .( $decapitated ? "body": "head" ). " from socket. Got 0 bytes back, which shouldn't happen"
            if $nbytes == 0;

        if ($decapitated) {
            $body .= $buf;
            $block_size -= $nbytes;
        }
        else {
            my $neck_pos = index($buf, "${CRLF}${CRLF}");
            if ($neck_pos > 0) {
                $decapitated = 1;
                $head .= substr($buf, 0, $neck_pos);
                $status_code = substr($head, 9, 3);
                substr($head, 0, index($head, $CRLF) + 2, ""); # 2 = length($CRLF)

                for (split /${CRLF}/o, $head) {
                    my ($key, $value) = split /: /, $_, 2;
                    $header->{$key} = $value;
                }

                if ($header->{'Content-Length'}) {
                    $body = substr($buf, $neck_pos + 4); # 4 = length("${CRLF}${CRLF}")
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

    } while( !$decapitated || $block_size > 0 );

    return ($status_code, $body, $header);
}

*fetch = \&pp_fetch;

sub build_http_message {
    my $args = $_[0];
    my $path_and_qs = ($args->{path} || "/") . ( defined($args->{query_string}) ? ("?".$args->{query_string}) : "" );
    return join(
        $CRLF,
        ($args->{method} || "GET")." $path_and_qs HTTP/1.1",
        "Host: $args->{host}",
        $args->{body} ? ("Content-Length: " . length($args->{body})) : (),
        $args->{head} ? (
            map {
                $args->{head}[2*$_] . ": " . $args->{head}[2*$_+1]
            } 0..$#{$args->{head}}/2
        ) : (),
        "",
        $args->{body} ? $args->{body} : ()
    ) . $CRLF;
}

sub request {
    my $args = $_[0];
    my $key = "$args->{host};$args->{port};$$";

    my $soc = $SocketCache->{$key} ||= do {
        my ($soc, $flags, $addr);
        $addr = sockaddr_in($args->{port}, inet_aton($args->{host}));
        socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die $!;
        if ($args->{timeout}) {
            $flags = fcntl($soc, F_GETFL, 0) or die $!;
            fcntl($soc, F_SETFL, $flags | O_NONBLOCK) or die $!;
        }
        connect($soc, $addr) or do {
            if ($! == EINPROGRESS) {
                vec(my $w = '', fileno($soc), 1) = 1;
                my $n = select(undef, $w, undef, $args->{timeout}) or return {
                    error => Hijk::Error::CONNECT_TIMEOUT
                };

                die "select(2) error, errno = $!" if $n < 0;
            }
            else {
                die "connect(2) error, errno = $!";
            }
        };
        if ($args->{timeout}) {
            fcntl($soc, F_SETFL, $flags) or die $!;
        }
        $soc;
    };
    my $r = build_http_message($args);
    my $rc = syswrite($soc,$r);
    if (!$rc || $rc != length($r)) {
        __disconnect($key);
        die "send error ($r) $!";
    }

    my ($status,$body,$head,$error) = eval {
        Hijk::fetch(fileno($soc), (($args->{timeout} || 0) * 1000));
    } or do {
        my $err = $@ || "zombie error";
        __disconnect($key);
        die $err;
    };

    if ($status == 0 || ($head->{Connection} && $head->{Connection} eq 'close')) {
        __disconnect($key);
    }
    return {
        status => $status,
        head => $head,
        body => $body,
        defined($error) ? ( error => $error ) : (),
    };
}

sub __disconnect {
    shutdown(delete $SocketCache->{$_[0]}, 2);
}

1;

__END__

=encoding utf8

=head1 NAME

Hijk - Specialized HTTP client

=head1 SYNOPSIS

A simple GET request:

    use Hijk;
    my $res = Hijk::request({
        method       => "GET",
        host         => "example.com",
        port         => "80",
        path         => "/flower",
        query_string => "color=red"
    });

    if (exists $res->{error} and $res->{error} & Hijk::Error::TIMEOUT) {
        die "Oh noes we had some sort of timeout";
    }

    die unless ($res->{status} == "200");

    say $res->{body};

A POST request, you have to manually set the appropriate headers, URI
escape your values etc.

    use Hijk;
    use URI::Escape qw(uri_escape);

    my $res = Hijk::request({
        method       => "POST",
        host         => "example.com",
        port         => "80",
        path         => "/new",
        head         => [ "Content-Type" => "application/x-www-form-urlencoded" ],
        query_string => "type=flower&bucket=the%20one%20out%20back",
        body         => "description=" . uri_escape("Another flower, let's hope it's exciting"),
    });

    die unless ($res->{status} == "200");

=head1 DESCRIPTION

Hijk is a specialized HTTP Client that does nothing but transporting the
response body back. It does not feature as a "user agent", but as a dumb
client. It is suitble for connecting to data servers transporting via HTTP
rather then web servers.

Most of HTTP features like proxy, redirect, Transfer-Encoding, or SSL are not
supported at all. For those requirements we already have many good HTTP clients
like L<HTTP::Tiny>, L<Furl> or L<LWP::UserAgent>.

=head1 FUNCTIONS

=head2 Hijk::request( $args :HashRef ) :HashRef

This is the only function to be used. It is not exported to its caller namespace
at all. It takes a request arguments in HashRef and returns the response in HashRef.

The C<$args> request arg should be a HashRef containing key-value pairs from the
following list. The value for C<host> and C<port> are mandatory and others are
optional with default values listed below

    host         => ...,
    port         => ...,
    timeout      => 0,
    method       => "GET",
    path         => "/",
    query_string => "",
    head         => [],
    body         => "",

Too keep the implementation minimal, Hijk does not take full URL string as
input. User who need to parse URL string could use L<URI> modules.

The value of C<head> is an ArrayRef of key-value pairs instead of HashRef, this way
the order of headers can be maintained. For example:

    head => [
        "Content-Type" => "application/json",
        "X-Requested-With" => "Hijk",
    ]

... will produce these request headers:

    Content-Type: application/json
    X-Requested-With: Hijk

Again, there are no extra character-escaping filter within Hijk.

The value of C<timeout> is in seconds, and is used as the time limit for both
connecting to the host, and reading from the socket. The default value C<0>
means that there is no timeout limit. If the host is really unreachable, it will
reach the system TCP timeout limit then dies.

The return vaue is a HashRef representing a response. It contains the following
key-value pairs.

=over 4

=item status => :StatusCode

=item body => :Str

=item head => :HashRef

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

Noticed that the C<head> in the response is a HashRef rather then an ArrayRef.
This makes it easier to retrieve specific header fields.

We currently don't support returning a body without a Content-Length
header, bodies B<MUST> have an accompanying Content-Length or we won't
pick them up.

=head1 AUTHORS

=over 4

=item Kang-min Liu <gugod@gugod.org>

=item Borislav Nikolov <jack@sofialondonmoskva.com>

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
