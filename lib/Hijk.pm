package Hijk;
use strict;
use warnings;
use POSIX qw(:errno_h);
use Socket qw(PF_INET SOCK_STREAM pack_sockaddr_in inet_ntoa $CRLF SOL_SOCKET SO_ERROR);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
our $VERSION = "0.15";

sub Hijk::Error::CONNECT_TIMEOUT         () { 1 << 0 } # 1
sub Hijk::Error::READ_TIMEOUT            () { 1 << 1 } # 2
sub Hijk::Error::TIMEOUT                 () { Hijk::Error::READ_TIMEOUT | Hijk::Error::CONNECT_TIMEOUT } # 3
sub Hijk::Error::CANNOT_RESOLVE          () { 1 << 2 } # 4
sub Hijk::Error::REQUEST_SELECT_ERROR    () { 1 << 3 } # 8
sub Hijk::Error::REQUEST_WRITE_ERROR     () { 1 << 4 } # 16
sub Hijk::Error::REQUEST_ERROR           () { Hijk::Error::REQUEST_SELECT_ERROR |  Hijk::Error::REQUEST_WRITE_ERROR } # 24
sub Hijk::Error::RESPONSE_READ_ERROR     () { 1 << 5 } # 32
sub Hijk::Error::RESPONSE_BAD_READ_VALUE () { 1 << 6 } # 64
sub Hijk::Error::RESPONSE_ERROR          () { Hijk::Error::RESPONSE_READ_ERROR | Hijk::Error::RESPONSE_BAD_READ_VALUE } # 96

sub _selectable_timeout {
    my $t = shift;
    return defined($t) && $t <=0 ? undef : $t;
}

sub _read_http_message {
    my ($fd, $read_timeout, $parse_chunked, $block_size,$header,$head) = (shift,shift,shift,10240,{},"");
    $read_timeout = _selectable_timeout($read_timeout);
    my ($body,$buf,$decapitated,$nbytes,$proto);
    my $status_code = 0;
    my $no_content_len = 0;
    vec(my $rin = '', $fd, 1) = 1;
    do {
        my $nfound = select($rin, undef, undef, $read_timeout);
        return (undef,0,undef,undef, Hijk::Error::READ_TIMEOUT)
            if ($nfound != 1 || (defined($read_timeout) && $read_timeout <= 0));

        my $nbytes = POSIX::read($fd, $buf, $block_size);
        return ($proto, $status_code, $header, $body)
            if $no_content_len && $decapitated && (!defined($nbytes) || $nbytes == 0);
        if (!defined($nbytes)) {
            next if ($! == EWOULDBLOCK || $! == EAGAIN);
            return (
                undef, 0, undef, undef,
                Hijk::Error::RESPONSE_READ_ERROR,
                "Failed to read http " . ($decapitated ? "body": "head") . " from socket",
                $!+0,
                "$!",
            );
        }

        if ($nbytes == 0) {
            return (
                undef, 0, undef, undef,
                Hijk::Error::RESPONSE_BAD_READ_VALUE,
                "Wasn't expecting a 0 byte response for http " . ($decapitated ? "body": "head" ) . ". This shouldn't happen",
            );
        }

        if ($decapitated) {
            $body .= $buf;
            if (!$no_content_len) {
                $block_size -= $nbytes;
            }
        }
        else {
            $head .= $buf;
            my $neck_pos = index($head, "${CRLF}${CRLF}");
            if ($neck_pos > 0) {
                $decapitated = 1;
                $body = substr($head, $neck_pos+4);
                $head = substr($head, 0, $neck_pos);
                $proto = substr($head, 0, 8);
                $status_code = substr($head, 9, 3);
                substr($head, 0, index($head, $CRLF) + 2, ""); # 2 = length($CRLF)

                for (split /${CRLF}/o, $head) {
                    my ($key, $value) = split /: /, $_, 2;
                    $header->{$key} = $value;
                }
                if ($header->{'Transfer-Encoding'} && $header->{'Transfer-Encoding'} eq 'chunked') {
                    die "PANIC: The experimental Hijk support for chunked transfer encoding needs to be explicitly enabled with parse_chunked => 1"
                        unless $parse_chunked;

                    # if there is chunked encoding we have to ignore content lenght even if we have it
                    return ($proto, $status_code, $header, _read_chunked_body($body, $fd, $read_timeout,$header));
                }

                if ($header->{'Content-Length'}) {
                    $block_size = $header->{'Content-Length'} - length($body);
                }
                else {
                    $block_size = 10204;
                    $no_content_len = 1;
                }
            }
        }

    } while( !$decapitated || $block_size > 0 || $no_content_len);
    return ($proto, $status_code, $header, $body);
}

sub _read_chunked_body {
    my ($buf,$fd, $read_timeout,$header) = @_;
    my $chunk_size   = 0;
    my $body         = "";
    my $block_size = 10240;
    my $trailer_mode  = 0;

    vec(my $rin = '', $fd, 1) = 1;
    while(1) {
        # just read a 10k block and process it until it is consumed
        if (length($buf) == 0 || length($buf) < $chunk_size) {
            my $nfound = select($rin, undef, undef, $read_timeout);
            return (undef, Hijk::Error::READ_TIMEOUT)
                if ($nfound != 1 || (defined($read_timeout) && $read_timeout <= 0));
            my $current_buf = "";
            my $nbytes = POSIX::read($fd, $current_buf, $block_size);
            if (!defined($nbytes)) {
                next if ($! == EWOULDBLOCK || $! == EAGAIN);
                return (
                    undef,
                    Hijk::Error::RESPONSE_READ_ERROR,
                    "Failed to chunked http body from socket",
                    $!+0,
                    "$!",
                );
            }

            if ($nbytes == 0) {
                return (
                    undef,
                    Hijk::Error::RESPONSE_BAD_READ_VALUE,
                    "Wasn't expecting a 0 byte response for chunked http body. This shouldn't happen, buf:<$buf>, current_buf:<$current_buf>",
                );
            }

            $buf .= $current_buf;
        }
        if ($trailer_mode) {
            # http://tools.ietf.org/html/rfc2616#section-14.40
            # http://tools.ietf.org/html/rfc2616#section-3.6.1
            #   A server using chunked transfer-coding in a response MUST NOT use the
            #   trailer for any header fields unless at least one of the following is
            #   true:

            #   a)the request included a TE header field that indicates "trailers" is
            #     acceptable in the transfer-coding of the  response, as described in
            #     section 14.39; or,

            #   b)the server is the origin server for the response, the trailer
            #     fields consist entirely of optional metadata, and the recipient
            #     could use the message (in a manner acceptable to the origin server)
            #     without receiving this metadata.  In other words, the origin server
            #     is willing to accept the possibility that the trailer fields might
            #     be silently discarded along the path to the client.

            # in case of trailer mode, we just read everything until the next CRLFCRLF
            my $neck_pos = index($buf, "${CRLF}${CRLF}");
            if ($neck_pos > 0) {
                return $body;
            }
        } else {
            if ($chunk_size > 0 && length($buf) >= $chunk_size) {
                $body .= substr($buf, 0, $chunk_size - 2); # our chunk size includes the CRLF
                $buf = substr($buf, $chunk_size);
                $chunk_size = 0;
            } else {
                my $neck_pos = index($buf, ${CRLF});
                if ($neck_pos > 0) {
                    $chunk_size = hex(substr($buf, 0, $neck_pos));
                    if ($chunk_size == 0) {
                        if ($header->{Trailer}) {
                            $trailer_mode = 1;
                        } else {
                            return $body;
                        }
                    } else {
                        $chunk_size += 2;                  # include the final CRLF
                        $buf = substr($buf, $neck_pos + 2);
                    }
                }
            }
        }
    }
}

sub _construct_socket {
    my ($host, $port, $connect_timeout) = @_;

    # If we can't find the IP address there'll be no point in even
    # setting up a socket.
    my $addr;
    {
        my $inet_aton = gethostbyname($host);
        return (undef, {error => Hijk::Error::CANNOT_RESOLVE}) unless defined $inet_aton;
        $addr = pack_sockaddr_in($port, $inet_aton);
    }

    my $tcp_proto = getprotobyname("tcp");
    my $soc;
    socket($soc, PF_INET, SOCK_STREAM, $tcp_proto) || die "Failed to construct TCP socket: $!";
    my $flags = fcntl($soc, F_GETFL, 0) or die "Failed to set fcntl F_GETFL flag: $!";
    fcntl($soc, F_SETFL, $flags | O_NONBLOCK) or die "Failed to set fcntl O_NONBLOCK flag: $!";

    if (!connect($soc, $addr) && $! != EINPROGRESS) {
        die "Failed to connect $!";
    }

    $connect_timeout = _selectable_timeout( $connect_timeout );
    vec(my $rout = '', fileno($soc), 1) = 1;
    my $nfound = select(undef, $rout, undef, $connect_timeout);
    if ($nfound != 1) {
        if (defined($connect_timeout)) {
            return (undef, {error => Hijk::Error::CONNECT_TIMEOUT});
        } else {
            return (
                undef,
                {
                    error         => Hijk::Error::REQUEST_SELECT_ERROR,
                    error_message => "select() error on constructing the socket",
                    errno_number  => $!+0,
                    errno_string  => "$!",
                },
            );
        }
    }

    if ($! = unpack("L", getsockopt($soc, SOL_SOCKET, SO_ERROR))) {
        die $!;
    }

    return $soc;
}

sub _build_http_message {
    my $args = $_[0];
    my $path_and_qs = ($args->{path} || "/") . ( defined($args->{query_string}) ? ("?".$args->{query_string}) : "" );
    return join(
        $CRLF,
        ($args->{method} || "GET")." $path_and_qs " . ($args->{protocol} || "HTTP/1.1"),
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

our $SOCKET_CACHE = {};

sub request {
    my $args = $_[0];

    # Backwards compatibility for code that provided the old timeout
    # argument.
    $args->{connect_timeout} = $args->{read_timeout} = $args->{timeout} if exists $args->{timeout};

    # Ditto for providing a default socket cache, allow for setting it
    # to "socket_cache => undef" to disable the cache.
    $args->{socket_cache} = $SOCKET_CACHE unless exists $args->{socket_cache};

    # Use $; so we can use the $socket_cache->{$$, $host, $port}
    # idiom to access the cache.
    my $cache_key; $cache_key = join($;, $$, @$args{qw(host port)}) if defined $args->{socket_cache};

    my $soc;
    if (defined $cache_key and exists $args->{socket_cache}->{$cache_key}) {
        $soc = $args->{socket_cache}->{$cache_key};
    } else {
        ($soc, my $error) = _construct_socket(@$args{qw(host port connect_timeout)});
        return $error if $error;
        $args->{socket_cache}->{$cache_key} = $soc if defined $cache_key;
        $args->{on_connect}->() if exists $args->{on_connect};
    }

    my $r = _build_http_message($args);
    my $total = length($r);
    my $left = $total;

    vec(my $rout = '', fileno($soc), 1) = 1;
    while ($left > 0) {
        my $nfound = select(undef, $rout, undef, undef);

        if ($nfound != 1) {
            delete $args->{socket_cache}->{$cache_key} if defined $cache_key;
            return {
                error         => Hijk::Error::REQUEST_SELECT_ERROR,
                error_message => "Got error on select() before the write() when while writing the HTTP request the socket",
                errno_number  => $!+0,
                errno_string  => "$!",
            };
        }

        my $rc = syswrite($soc,$r,$left, $total - $left);
        if (!defined($rc)) {
            next if ($! == EWOULDBLOCK || $! == EAGAIN);
            delete $args->{socket_cache}->{$cache_key} if defined $cache_key;
            shutdown($soc, 2);
            return {
                error         => Hijk::Error::REQUEST_WRITE_ERROR,
                error_message => "Got error trying to write the HTTP request with write() to the socket",
                errno_number  => $!+0,
                errno_string  => "$!",
            };
        }
        $left -= $rc;
    }

    my ($proto,$status,$head,$body,$error,$error_message,$errno_number,$errno_string);
    eval {
        ($proto,$status,$head,$body,$error,$error_message,$errno_number,$errno_string) =
        _read_http_message(fileno($soc), $args->{read_timeout}, $args->{parse_chunked});
        1;
    } or do {
        my $err = $@ || "zombie error";
        delete $args->{socket_cache}->{$cache_key} if defined $cache_key;
        shutdown($soc, 2);
        die $err;
    };

    if ($status == 0
        # We always close connections for 1.0 because some servers LIE
        # and say that they're 1.0 but don't close the connection on
        # us! An example of this. Test::HTTP::Server (used by the
        # ShardedKV::Storage::Rest tests) is an example of such a
        # server. In either case we can't cache a connection for a 1.0
        # server anyway, so BEGONE!
        or (defined $proto and $proto eq 'HTTP/1.0')
        or ($head->{Connection} && $head->{Connection} eq 'close')) {
        delete $args->{socket_cache}->{$cache_key} if defined $cache_key;
        shutdown($soc, 2);
    }
    return {
        proto => $proto,
        status => $status,
        head => $head,
        body => $body,
        defined($error) ? ( error => $error ) : (),
        defined($error_message) ? ( error_message => $error_message ) : (),
        defined($errno_number) ? ( errno_number => $errno_number ) : (),
        defined($errno_string) ? ( errno_string => $errno_string ) : (),
    };
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

Hijk is a specialized HTTP Client that does nothing but transport the
response body back. It does not feature as a "user agent", but as a dumb
client. It is suitable for connecting to data servers transporting via HTTP
rather then web servers.

Most of HTTP features like proxy, redirect, Transfer-Encoding, or SSL are not
supported at all. For those requirements we already have many good HTTP clients
like L<HTTP::Tiny>, L<Furl> or L<LWP::UserAgent>.


=head1 FUNCTION: Hijk::request( $args :HashRef ) :HashRef

C<Hijk::request> is the only function to be used. It is not exported to its
caller namespace at all. It takes a request arguments in HashRef and returns the
response in HashRef.

The C<$args> request arg should be a HashRef containing key-value pairs from the
following list. The value for C<host> and C<port> are mandatory and others are
optional with default values listed below

    protocol        => "HTTP/1.1", # (or "HTTP/1.0")
    host            => ...,
    port            => ...,
    connect_timeout => 0,
    read_timeout    => 0,
    method          => "GET",
    path            => "/",
    query_string    => "",
    head            => [],
    body            => "",
    socket_cache    => {}, # (undef to disable, or \my %your_socket_cache)
    on_connect      => undef, # (or sub { ... })
    parse_chunked   => 0,

To keep the implementation minimal, Hijk does not take full URL string as
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

Again, there are no extra character-escaping filters within Hijk.

The value of C<connect_timeout> or C<read_timeout> is in seconds, and
is used as the time limit for connecting and writing to the host, and
reading from the socket, respectively. The default value for both is
C<0>, meaning no timeout limit. If the host is really unreachable or
slow, we'll reach the TCP timeout limit before dying.

The optional C<on_connect> callback is intended to be used for you to
figure out from production traffic what you should set the
C<connect_timeout>. I.e. you can start a timer when you call
C<Hijk::request()> that you end when C<on_connect> is called, that's
how long it took us to get a connection. If you start another timer in
that callback that you end when C<Hijk::request()> returns to you
that'll give you how long it took to send/receive data after we
constructed the socket, i.e. it'll help you to tweak your
C<read_timeout>. The C<on_connect> callback is provided with no
arguments, and is called in void context.

The default C<protocol> is C<HTTP/1.1>, but you can also specify
C<HTTP/1.0>. The advantage of using HTTP/1.1 is support for
keep-alive, which matters a lot in environments where the connection
setup represents non-trivial overhead. Sometimes that overhead is
negligible (e.g. on Linux talking to an nginx on the local network),
and keeping open connections down and reducing complexity is more
important, in those cases you can use C<HTTP/1.0>.

By default we will provide a C<socket_cache> for you which is a global
singleton that we maintain keyed on C<join($;, $$, $host, $port)>.
Alternatively you can pass in C<socket_cache> hash of your own which
we'll use as the cache. To completely disable the cache pass in
C<undef>.

We have experimental support for parsing chunked responses
encoding. historically Hijk didn't support this at all and if you
wanted to use it with e.g. nginx you had to add
C<chunked_transfer_encoding off> to its config file. Because you may
just want to do that instead of having Hijk do more work to parse this
out with a more complex and experimental codepath you have to
explicitly enable it with C<parse_chunked>. Otherwise Hijk will die
when it encounters chunked responses. The C<parse_chunked> option may
be turned on by default in the future.

The return value is a HashRef representing a response. It contains the following
key-value pairs.

    proto         => :Str
    status        => :StatusCode
    body          => :Str
    head          => :HashRef
    error         => :Int
    error_message => :Str
    errno_number  => :Int
    errno_string  => :Str

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
C<query_string>. You do, however, need to properly C<uri_escape> the content of
C<query_string>.

All values are assumed to be valid. Hijk simply passes the values through without
validating the content. It is possible that it constructs invalid HTTP Messages.
Users should keep this in mind when using Hijk.

Noticed that the C<head> in the response is a HashRef rather then an ArrayRef.
This makes it easier to retrieve specific header fields.

We currently don't support servers returning a http body without an accompanying
C<Content-Length> header; bodies B<MUST> have a C<Content-Length> or we won't pick
them up.

=head1 ERROR CODES

If we had an error we'll include an "error" key whose value is a
bitfield that you can check against Hijk::Error::* constants. Those
are:

=over 4

=item Hijk::Error::CONNECT_TIMEOUT

=item Hijk::Error::READ_TIMEOUT

=item Hijk::Error::TIMEOUT

=item Hijk::Error::CANNOT_RESOLVE

=item Hijk::Error::REQUEST_SELECT_ERROR

=item Hijk::Error::REQUEST_WRITE_ERROR

=item Hijk::Error::REQUEST_ERROR

=item Hijk::Error::RESPONSE_READ_ERROR

=item Hijk::Error::RESPONSE_BAD_READ_VALUE

=item Hijk::Error::RESPONSE_ERROR

=back

In addition we might return C<error_message>, C<errno_number> and
C<errno_string> keys, see the discussion of C<Hijk::Error::REQUEST_*>
and C<Hijk::Error::RESPONSE_*> errors below.

The C<Hijk::Error::TIMEOUT> constant is the same as
C<Hijk::Error::CONNECT_TIMEOUT | Hijk::Error::READ_TIMEOUT>. It's
there for convenience so you can do:

    .. if exists $res->{error} and $res->{error} & Hijk::Error::TIMEOUT;

Instead of the more verbose:

    .. if exists $res->{error} and $res->{error} & (Hijk::Error::CONNECT_TIMEOUT | Hijk::Error::READ_TIMEOUT)

We'll return C<Hijk::Error::CANNOT_RESOLVE> if we can't
C<gethostbyname()> the host you've provided.

If we fail to do a C<select()> or C<write()> during when sending the
response we'll return C<Hijk::Error::REQUEST_SELECT_ERROR> or
C<Hijk::Error::REQUEST_WRITE_ERROR>, respectively. similar to
C<Hijk::Error::TIMEOUT> the C<Hijk::Error::REQUEST_ERROR> constant is
a union of these two and any other request errors we might add in the
future.

When we're getting the response back we'll return
C<Hijk::Error::RESPONSE_READ_ERROR> when we can't C<read()> the
response, and C<Hijk::Error::RESPONSE_BAD_READ_VALUE> when the value
we got from C<read()> is C<0>. The C<Hijk::Error::RESPONSE_ERROR>
constant is a union of these two and any other response errors we
might add in the future.

Some of these C<Hijk::Error::REQUEST_*> and C<Hijk::Error::RESPONSE_*>
errors are re-thrown errors from system calls. In that case we'll also
pass along C<error_message> which is a short human readable error
message about the error, and C<errno_number> & C<errno_string>, which
are C<$!+0> and C<"$!"> at the time we had the error.

Hijk might encounter other errors during the course of the request and
C<WILL> call C<die> if that happens, so if you don't want your program
to stop when a request like that fails wrap it in C<eval>.

Having said that the point of the C<Hijk::Error::*> interface is that
all errors that happen during normal operation, i.e. making valid
requests against servers where you can have issues like timeouts,
network blips or the server thread on the other end being suddenly
kill -9'd should be caught, categorized and returned in a structural
way by Hijk.

We're not currently aware of any issues that occur in such normal
operations that aren't classified as a C<Hijk::Error::*>, and if we
find new issues that fit the criteria above we'll likely just make a
new C<Hijk::Error::*> for it.

We're just not trying to guarantee that the library can never C<die>,
and aren't trying to catch truly exceptional issues like
e.g. C<fcntl()> failing on a valid socket.

=head1 AUTHORS

=over 4

=item Kang-min Liu <gugod@gugod.org>

=item Ævar Arnfjörð Bjarmason <avar@cpan.org>

=item Borislav Nikolov <jack@sofialondonmoskva.com>

=item Damian Gryski <damian@gryski.com>

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
