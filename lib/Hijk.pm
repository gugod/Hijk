package Hijk;
use strict;
use warnings;
use POSIX qw(EINPROGRESS);
use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
our $VERSION = "0.10";

sub Hijk::Error::CONNECT_TIMEOUT () { 1 << 0 } # 1
sub Hijk::Error::READ_TIMEOUT    () { 1 << 1 } # 2
sub Hijk::Error::TIMEOUT         () { Hijk::Error::READ_TIMEOUT() | Hijk::Error::CONNECT_TIMEOUT() } # 3
# sub Hijk::Error::WHATEVER      () { 1 << 2 } # 4

sub fetch {
    my ($fd, $read_timeout,$block_size,$header,$head) = (shift,shift,10240,{},"");
    my ($body,$buf,$decapitated,$nfound,$nbytes,$proto);
    my $status_code = 0;
    $read_timeout /= 1000 if defined $read_timeout;
    vec(my $rin = '', $fd, 1) = 1;
    do {
        if ($read_timeout) {
            $nfound = select($rin, undef, undef, $read_timeout);
            die "select(2) error, errno = $!" if $nfound == -1;
            return (undef,0,undef,undef, Hijk::Error::READ_TIMEOUT) unless $nfound == 1;
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

                if ($header->{'Content-Length'}) {
                    $block_size = $header->{'Content-Length'} - length($body);
                }
                else {
                    $block_size = 0;
                }
            }
        }

    } while( !$decapitated || $block_size > 0 );

    return ($proto, $status_code, $body, $header);
}

sub construct_socket {
    my ($host, $port, $connect_timeout) = @_;
    my $soc;
    socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Failed to construct TCP socket: $!";
    my $flags;
    if ($connect_timeout) {
        $flags = fcntl($soc, F_GETFL, 0) or die "Failed to set fcntl F_GETFL flag for socket connect timeout (before connection): $!";
        fcntl($soc, F_SETFL, $flags | O_NONBLOCK) or die "Failed to set fcntl O_NONBLOCK flag for socket connect timeout: $!";
    }
    my $addr = sockaddr_in($port, inet_aton($host));
    connect($soc, $addr) or do {
        if ($! == EINPROGRESS) {
            vec(my $w = '', fileno($soc), 1) = 1;
            my $n = select(undef, $w, undef, $connect_timeout);
            unless ($n) {
                return (undef, Hijk::Error::CONNECT_TIMEOUT);
            }

            die "select(2) error, errno = $!" if $n < 0;
        } else {
            die "connect(2) error, errno = $!";
        }
    };
    if ($connect_timeout) {
        fcntl($soc, F_SETFL, $flags) or die "Failed to set fcntl F_GETFL flag for socket connect timeout (after connection): $!";
    }

    return $soc;
}

sub build_http_message {
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
    my $cache_key; $cache_key = "$args->{host};$args->{port};$$" if exists $args->{socket_cache};

    my $soc;
    if (defined $cache_key and exists $args->{socket_cache}->{$cache_key}) {
        $soc = $args->{socket_cache}->{$cache_key};
    } else {
        ($soc, my $error) = construct_socket(@$args{qw(host port connect_timeout)});
        return {error => $error} if defined $error; # To maybe return the CONNECT_TIMEOUT
        $args->{socket_cache}->{$cache_key} = $soc if defined $cache_key;
        $args->{on_connect}->() if exists $args->{on_connect};
    }

    my $r = build_http_message($args);
    my $rc = syswrite($soc,$r);
    if (!$rc || $rc != length($r)) {
        delete $args->{socket_cache}->{$cache_key} if defined $cache_key;
        shutdown($soc, 2);
        die "send error ($r) $!";
    }

    my ($proto,$status,$body,$head,$error) = eval {
        fetch(fileno($soc), (($args->{read_timeout} || 0) * 1000));
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

The value of C<connect_timeout> or C<read_timeout> is in seconds, and
is used as the time limit for connecting to the host, and reading from
the socket, respectively. You can't provide a non-zero read timeout
without providing a non-zero connect timeout, as the socket has to be
set up with the C<O_NONBLOCK> flag for the C<read_timeout> to work,
which we only do if we have a C<connect_timeout>. The default value
for both is C<0>, meaning no timeout limit. If the host is really
unreachable or slow, we'll reach the TCP timeout limit before dying.

The optional C<on_connect> callback is intended to be used for you to
figure out from production traffic what you should set the
C<connect_timeout>. I.e. you can start a timer when you call
C<Hijk::request()> that you end when C<on_connect> is called, that's
how long is took us to get a connection, if you start another timer in
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
singleton that we maintain keyed on host/port/pid. Alternatively you
can pass in C<socket_cache> hash of your own which we'll use as the
cache. To completely disable the cache pass in C<undef>.

The return vaue is a HashRef representing a response. It contains the following
key-value pairs.

=over 4

=item proto => :Str

=item status => :StatusCode

=item body => :Str

=item head => :HashRef

=item error => :Int

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

If we had an error we'll include an "error" key whose value is a
bitfield that you can check against Hijk::Error::* constants. Those
are:

=over 4

=item Hijk::Error::CONNECT_TIMEOUT

=item Hijk::Error::READ_TIMEOUT

=item Hijk::Error::TIMEOUT

=back

The Hijk::Error::TIMEOUT constant is the same as
C<Hijk::Error::CONNECT_TIMEOUT | Hijk::Error::READ_TIMEOUT>. It's
there for convenience so you can do:

    .. if exists $res->{error} and $res->{error} & Hijk::Error::TIMEOUT;

Instead of the more verbose:

    .. if exists $res->{error} and $res->{error} & (Hijk::Error::CONNECT_TIMEOUT | Hijk::Error::READ_TIMEOUT)

Hijk C<WILL> call die if any system calls that it executes fail with
errors that aren't covered by C<Hijk::Error::*>, so wrap it in an
C<eval> if you don't want to die in those cases. We just provide
C<Hijk::Error::*> for non-exceptional failures like timeouts, not for
e.g. you trying to connect to a host that doesn't exist or a socket
unexpectedly going away etc.

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
