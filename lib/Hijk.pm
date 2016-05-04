package Hijk;
use strict;
use warnings;
use Time::HiRes;
use POSIX qw(:errno_h);
use Socket qw(PF_INET SOCK_STREAM pack_sockaddr_in inet_ntoa $CRLF SOL_SOCKET SO_ERROR);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

our $VERSION = "0.26";

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

sub _read_http_message {
    my ($fd, $read_length, $read_timeout, $parse_chunked, $head_as_array, $method) = @_;
    $read_timeout = undef if defined($read_timeout) && $read_timeout <= 0;

    my ($body,$buf,$decapitated,$nbytes,$proto);
    my $status_code = 0;
    my $header = $head_as_array ? [] : {};
    my $no_content_len = 0;
    my $head = "";
    my $method_has_no_content = do { no warnings qw(uninitialized); $method eq "HEAD" };
    my $close_connection;
    vec(my $rin = '', $fd, 1) = 1;
    do {
        return ($close_connection,undef,0,undef,undef, Hijk::Error::READ_TIMEOUT)
            if ((_select($rin, undef, undef, $read_timeout) != 1) || (defined($read_timeout) && $read_timeout <= 0));

        my $nbytes = POSIX::read($fd, $buf, $read_length);
        return ($close_connection, $proto, $status_code, $header, $body)
            if $no_content_len && $decapitated && (!defined($nbytes) || $nbytes == 0);
        if (!defined($nbytes)) {
            next if ($! == EWOULDBLOCK || $! == EAGAIN || $! == EINTR);
            return (
                $close_connection, undef, 0, undef, undef,
                Hijk::Error::RESPONSE_READ_ERROR,
                "Failed to read http " . ($decapitated ? "body": "head") . " from socket",
                $!+0,
                "$!",
            );
        }

        if ($nbytes == 0) {
            return (
                $close_connection, undef, 0, undef, undef,
                Hijk::Error::RESPONSE_BAD_READ_VALUE,
                "Wasn't expecting a 0 byte response for http " . ($decapitated ? "body": "head" ) . ". This shouldn't happen",
            );
        }

        if ($decapitated) {
            $body .= $buf;
            if (!$no_content_len) {
                $read_length -= $nbytes;
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
                $method_has_no_content = 1 if $status_code == 204; # 204 NO CONTENT, see http://tools.ietf.org/html/rfc2616#page-60
                substr($head, 0, index($head, $CRLF) + 2, ""); # 2 = length($CRLF)

                my ($doing_chunked, $content_length, $trailer_mode, $trailer_value_is_true);
                for (split /${CRLF}/o, $head) {
                    my ($key, $value) = split /: /, $_, 2;

                    # Figure this out now so we don't need to scan the
                    # list later under $head_as_array, and just for
                    # simplicity and to avoid duplicating code later
                    # when !$head_as_array.
                    if ($key eq 'Transfer-Encoding' and $value eq 'chunked') {
                        $doing_chunked = 1;
                    } elsif ($key eq 'Content-Length') {
                        $content_length = $value;
                    } elsif ($key eq 'Connection' and $value eq 'close') {
                        $close_connection = 1;
                    } elsif ($key eq 'Trailer' and $value) {
                        $trailer_value_is_true = 1;
                    }

                    if ($head_as_array) {
                        push @$header => $key, $value;
                    } else {
                        $header->{$key} = $value;
                    }
                }

                # We're processing the headers as a stream, and we
                # only want to turn on $trailer_mode if
                # Transfer-Encoding=chunked && Trailer=TRUE. However I
                # don't think there's any guarantee that
                # Transfer-Encoding comes before Trailer, so we're
                # effectively doing a second-pass here.
                if ($doing_chunked and $trailer_value_is_true) {
                    $trailer_mode = 1;
                }

                if ($doing_chunked) {
                    die "PANIC: The experimental Hijk support for chunked transfer encoding needs to be explicitly enabled with parse_chunked => 1"
                        unless $parse_chunked;

                    # if there is chunked encoding we have to ignore content length even if we have it
                    return (
                        $close_connection, $proto, $status_code, $header,
                        _read_chunked_body(
                            $body, $fd, $read_length, $read_timeout,
                            $head_as_array
                              ? $trailer_mode
                              : ($header->{Trailer} ? 1 : 0),
                        ),
                    );
                }

                if (defined $content_length) {
                    if ($content_length == 0) {
                        $read_length = 0;
                    } else {
                        $read_length = $content_length - length($body);
                    }
                } else {
                    $read_length = 10204;
                    $no_content_len = 1;
                }
            }
        }
    } while( !$decapitated || (!$method_has_no_content && ($read_length > 0 || $no_content_len)) );
    return ($close_connection, $proto, $status_code, $header, $body);
}

sub _read_chunked_body {
    my ($buf,$fd,$read_length,$read_timeout,$true_trailer_header) = @_;
    my $chunk_size   = 0;
    my $body         = "";
    my $trailer_mode = 0;
    my $wait_for_last_clrf = 0;
    vec(my $rin = '', $fd, 1) = 1;
    while(1) {
        # just read a 10k block and process it until it is consumed
        if (length($buf) < 3 || length($buf) < $chunk_size || $wait_for_last_clrf > 0) {
            return (undef, Hijk::Error::READ_TIMEOUT)
                if ((_select($rin, undef, undef, $read_timeout) != 1) || (defined($read_timeout) && $read_timeout <= 0));
            my $current_buf = "";
            my $nbytes = POSIX::read($fd, $current_buf, $read_length);
            if (!defined($nbytes)) {
                next if ($! == EWOULDBLOCK || $! == EAGAIN || $! == EINTR);
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

        if ($wait_for_last_clrf > 0) {
            $wait_for_last_clrf -= length($buf);
            return $body if ($wait_for_last_clrf <= 0);
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
                $body .= substr($buf, 0, $chunk_size - 2); # our chunk size includes the following CRLF
                $buf = substr($buf, $chunk_size);
                $chunk_size = 0;
            } else {
                my $neck_pos = index($buf, ${CRLF});
                if ($neck_pos > 0) {
                    $chunk_size = hex(substr($buf, 0, $neck_pos));
                    if ($chunk_size == 0) {
                        if ($true_trailer_header) {
                            $trailer_mode = 1;
                        } else {
                            $buf = substr($buf, $neck_pos + 2);
                            # in case we are missing the ending CLRF, we have to wait for it
                            # otherwise it is left int he socket
                            if (length($buf) < 2) {
                                $wait_for_last_clrf = 2 - length($buf);
                            } else {
                                return $body;
                            }
                        }
                    } else {
                        $chunk_size += 2; # include the following CRLF
                        $buf = substr($buf, $neck_pos + 2);
                    }
                } elsif($neck_pos == 0) {
                    return (
                        undef,
                        Hijk::Error::RESPONSE_BAD_READ_VALUE,
                        "Wasn't expecting CLRF without chunk size. This shouldn't happen, buf:<$buf>",
                    );
                }
            }
        }
    }
}

sub _construct_socket {
    my ($host, $port, $connect_timeout) = @_;


    # If we can't find the IP address there'll be no point in even
    # setting up a socket.
    my $ip_aton = gethostbyname($host);
    return (undef, {error => Hijk::Error::CANNOT_RESOLVE}) unless defined $ip_aton;

    my $addr = pack_sockaddr_in($port, $ip_aton);

    my $tcp_proto = getprotobyname("tcp");
    my $soc;
    socket($soc, PF_INET, SOCK_STREAM, $tcp_proto) || die "Failed to construct TCP socket: $!";
    my $flags = fcntl($soc, F_GETFL, 0) or die "Failed to set fcntl F_GETFL flag: $!";
    fcntl($soc, F_SETFL, $flags | O_NONBLOCK) or die "Failed to set fcntl O_NONBLOCK flag: $!";

    if (!connect($soc, $addr) && $! != EINPROGRESS) {
        my $ip = inet_ntoa($ip_aton);
        die "Failed to connect (host=$host, ip=$ip, port=$port) : $!";
    }

    $connect_timeout = undef if defined($connect_timeout) && $connect_timeout <= 0;
    vec(my $rout = '', fileno($soc), 1) = 1;
    if (_select(undef, $rout, undef, $connect_timeout) != 1) {
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
        my $ip = inet_ntoa($ip_aton);
        die "Failed to connect (host=$host, ip=$ip, port=$port) : $!";
    }

    return $soc;
}

sub _build_http_message {
    my $args = $_[0];
    my $path_and_qs = ($args->{path} || "/") . ( defined($args->{query_string}) ? ("?".$args->{query_string}) : "" );
    return join(
        $CRLF,
        ($args->{method} || "GET")." $path_and_qs " . ($args->{protocol} || "HTTP/1.1"),
        ($args->{no_default_host_header}
         ? ()
         : ("Host: $args->{host}")),
        defined($args->{body}) ? ("Content-Length: " . length($args->{body})) : (),
        ($args->{head} and @{$args->{head}}) ? (
            map {
                $args->{head}[2*$_] . ": " . $args->{head}[2*$_+1]
            } 0..$#{$args->{head}}/2
        ) : (),
        ""
    ) . $CRLF . (defined($args->{body}) ? $args->{body} : "");
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

    # Provide a default for the read_length option
    $args->{read_length} = 10 * 2 ** 10 unless exists $args->{read_length};

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
        if (_select(undef, $rout, undef, undef) != 1) {
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
            next if ($! == EWOULDBLOCK || $! == EAGAIN || $! == EINTR);
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

    my ($close_connection,$proto,$status,$head,$body,$error,$error_message,$errno_number,$errno_string);
    eval {
        ($close_connection,$proto,$status,$head,$body,$error,$error_message,$errno_number,$errno_string) =
        _read_http_message(fileno($soc), @$args{qw(read_length read_timeout parse_chunked head_as_array method)});
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
        or $close_connection
        or (defined $proto and $proto eq 'HTTP/1.0')) {
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

sub _select {
    my ($rbits, $wbits, $ebits, $timeout) = @_;
    while (1) {
        my $start = Time::HiRes::time();
        my $nfound = select($rbits, $wbits, $ebits, $timeout);
        if ($nfound == -1 && $! == EINTR) {
            $timeout -= Time::HiRes::time() - $start if $timeout;
            next;
        }
        return $nfound;
    }
}

1;

__END__

=encoding utf8

=head1 NAME

Hijk - Fast & minimal low-level HTTP client

=head1 SYNOPSIS

A simple GET request:

    use Hijk ();
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

    die "Expecting a successful response" unless $res->{status} == 200;

    say $res->{body};

A POST request, you have to manually set the appropriate headers, URI
escape your values etc.

    use Hijk ();
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

    die "Expecting a successful response" unless $res->{status} == 200;

=head1 DESCRIPTION

Hijk is a fast & minimal low-level HTTP client intended to be used
where you control both the client and the server, e.g. for talking to
some internal service from a frontend user-facing web application.

It is C<NOT> a general HTTP user agent, it doesn't support redirects,
proxies, SSL and any number of other advanced HTTP features like (in
roughly descending order of feature completeness) L<LWP::UserAgent>,
L<WWW::Curl>, L<HTTP::Tiny>, L<HTTP::Lite> or L<Furl>. This library is
basically one step above manually talking HTTP over sockets.

Having said that it's lightning fast and extensively used in
production at L<Booking.com|https://www.booking.com> where it's used
as the go-to transport layer for talking to internal services. It uses
non-blocking sockets and correctly handles all combinations of
connect/read timeouts and other issues you might encounter from
various combinations of parts of your system going down or becoming
otherwise unavailable.

=head1 FUNCTION: Hijk::request( $args :HashRef ) :HashRef

C<Hijk::request> is the only function you should use. It (or anything
else in this package for that matter) is not exported, so you have to
use the fully qualified name.

It takes a C<HashRef> of arguments and either dies or returns a
C<HashRef> as a response.

The C<HashRef> argument to it must contain some of the key-value pairs
from the following list. The value for C<host> and C<port> are
mandatory, but others are optional with default values listed below.

    protocol               => "HTTP/1.1", # (or "HTTP/1.0")
    host                   => ...,
    port                   => ...,
    connect_timeout        => undef,
    read_timeout           => undef,
    read_length            => 10240,
    method                 => "GET",
    path                   => "/",
    query_string           => "",
    head                   => [],
    body                   => "",
    socket_cache           => \%Hijk::SOCKET_CACHE, # (undef to disable, or \my %your_socket_cache)
    on_connect             => undef, # (or sub { ... })
    parse_chunked          => 0,
    head_as_array          => 0,
    no_default_host_header => 1,

Notice how Hijk does not take a full URI string as input, you have to
specify the individual parts of the URL. Users who need to parse an
existing URI string to produce a request should use the L<URI> module
to do so.

The value of C<head> is an C<ArrayRef> of key-value pairs instead of a
C<HashRef>, this way you can decide in which order the headers are
sent, and you can send the same header name multiple times. For
example:

    head => [
        "Content-Type" => "application/json",
        "X-Requested-With" => "Hijk",
    ]

Will produce these request headers:

    Content-Type: application/json
    X-Requested-With: Hijk

In addition Hijk will provide a C<Host> header for you by default with
the C<host> value you pass to C<request()>. To suppress this (e.g. to
send custom C<Host> requests) pass a true value to the
C<no_default_host_header> option and provide your own C<Host> header
in the C<head> C<ArrayRef> (or don't, if you want to construct a
C<Host>-less request knock yourself out...).

Hijk doesn't escape any values for you, it just passes them through
as-is. You can easily produce invalid requests if e.g. any of these
strings contain a newline, or aren't otherwise properly escaped.

The value of C<connect_timeout> or C<read_timeout> is in floating
point seconds, and is used as the time limit for connecting to the
host, and reading the response back from it, respectively. The default
value for both is C<undef>, meaning no timeout limit. If you don't
supply these timeouts and the host really is unreachable or slow,
we'll reach the TCP timeout limit before returning some other error to
you.

The default C<protocol> is C<HTTP/1.1>, but you can also specify
C<HTTP/1.0>. The advantage of using C<HTTP/1.1> is support for
keep-alive, which matters a lot in environments where the connection
setup represents non-trivial overhead. Sometimes that overhead is
negligible (e.g. on Linux talking to an nginx on the local network),
and keeping open connections down and reducing complexity is more
important, in those cases you can either use C<HTTP/1.0>, or specify
C<Connection: close> in the request, but just using C<HTTP/1.0> is an
easy way to accomplish the same thing.

By default we will provide a C<socket_cache> for you which is a global
singleton that we maintain keyed on C<join($;, $$, $host, $port)>.
Alternatively you can pass in C<socket_cache> hash of your own which
we'll use as the cache. To completely disable the cache pass in
C<undef>.

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

We have experimental support for parsing chunked responses
encoding. historically Hijk didn't support this at all and if you
wanted to use it with e.g. nginx you had to add
C<chunked_transfer_encoding off> to the nginx config file.

Since you may just want to do that instead of having Hijk do more work
to parse this out with a more complex and experimental codepath you
have to explicitly enable it with C<parse_chunked>. Otherwise Hijk
will die when it encounters chunked responses. The C<parse_chunked>
option may be turned on by default in the future.

The return value is a C<HashRef> representing a response. It contains
the following key-value pairs.

    proto         => :Str
    status        => :StatusCode
    body          => :Str
    head          => :HashRef (or :ArrayRef with "head_as_array")
    error         => :PositiveInt
    error_message => :Str
    errno_number  => :Int
    errno_string  => :Str

For example, to send a request to
C<http://example.com/flower?color=red>, pass the following parameters:

    my $res = Hijk::request({
        host         => "example.com",
        port         => "80",
        path         => "/flower",
        query_string => "color=red"
    });
    die "Response is not OK" unless $res->{status} == 200;

Notice that you do not need to put the leading C<"?"> character in the
C<query_string>. You do, however, need to properly C<uri_escape> the content of
C<query_string>.

Again, Hijk doesn't escape any values for you, so these values B<MUST>
be properly escaped before being passed in, unless you want to issue
invalid requests.

By default the C<head> in the response is a C<HashRef> rather then an
C<ArrayRef>. This makes it easier to retrieve specific header fields,
but it means that we'll clobber any duplicated header names with the
most recently seen header value. To get the returned headers as an
C<ArrayRef> instead specify C<head_as_array>.

If you want to fiddle with the C<read_length> value it controls how
much we C<POSIX::read($fd, $buf, $read_length)> at a time.

We currently don't support servers returning a http body without an accompanying
C<Content-Length> header; bodies B<MUST> have a C<Content-Length> or we won't pick
them up.

=head1 ERROR CODES

If we had a recoverable error we'll include an "error" key whose value
is a bitfield that you can check against Hijk::Error::*
constants. Those are:

    Hijk::Error::CONNECT_TIMEOUT
    Hijk::Error::READ_TIMEOUT
    Hijk::Error::TIMEOUT
    Hijk::Error::CANNOT_RESOLVE
    Hijk::Error::REQUEST_SELECT_ERROR
    Hijk::Error::REQUEST_WRITE_ERROR
    Hijk::Error::REQUEST_ERROR
    Hijk::Error::RESPONSE_READ_ERROR
    Hijk::Error::RESPONSE_BAD_READ_VALUE
    Hijk::Error::RESPONSE_ERROR

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
C<Hijk::Error::REQUEST_WRITE_ERROR>, respectively. Similarly to
C<Hijk::Error::TIMEOUT> the C<Hijk::Error::REQUEST_ERROR> constant is
a union of these two, and any other request errors we might add in the
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
message about the error, as well as C<errno_number> & C<errno_string>,
which are C<$!+0> and C<"$!"> at the time we had the error.

Hijk might encounter other errors during the course of the request and
B<WILL> call C<die> if that happens, so if you don't want your program
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
