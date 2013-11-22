package Hijk;
use POSIX;
use strict;
use warnings;
use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);

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
    my ($head, $body,$buf);
    my $block_size = 10240;
    while (1) {
        my $tmp;
        my $r = POSIX::read($fd, $tmp, $block_size) || die $!;
        $buf .= $tmp;
        ($head, $body) = split(/${CRLF}${CRLF}/o, $buf, 2);
        if ($body) {
            my ($content_length) = $head =~ m/^Content-Length: ([0-9]+)$/om;
            my $left = $content_length - length($body);
            $buf = "";
            while ($left) {
                my $r = POSIX::read($fd, $buf, $left);
                die "Failed to read the full response body. $! (expected $left got $r)"
                    unless $r;
                $body .= $buf;
                $left -= $r;
            }
            return (200, $body);
        }
    }
}

sub _build_http_message {
    my $args = $_[0];
    my $path_and_qs = $args->{path} . ( defined($args->{query_string}) ? ("?".$args->{query_string}) : "" );
    return join(
        $CRLF,
        "$args->{method} $path_and_qs HTTP/1.1",
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
    my $r = _build_http_message($args);
    die "send error ($r) $!"
        if syswrite($soc,$r) != length($r);

    my ($status,$body) = fetch(fileno($soc));
    die "$status: $body"
        unless $status == 200;

    return $body;
}

1;
