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

    # it will block until receives at least 512 bytes
    my $block_size = 512;
    if (POSIX::read($fd, $buf, $block_size)) {
        ($head, $body) = split(/${CRLF}${CRLF}/o, $buf, 2);
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
    }
    else {
        die "Failed to read the first block.";
    }
    return (200, $body);
}

sub request {
    my $args = $_[0];

    my $soc = $SocketCache->{"$args->{host};$args->{port};$$"} ||= do {
        my $soc;
        socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die $!;
        connect($soc, sockaddr_in($args->{port}, inet_aton($args->{host}))) || die $!;
        $soc;
    };
    my $r = join($CRLF,
                 "$args->{method} $args->{path} HTTP/1.1",
                 "Host: $args->{host}",
                 $args->{body} ? ("Content-Length: " . length($args->{body})) : (),
                 "",
                 $args->{body} ? $args->{body} : ()
        ) . $CRLF;
    die "send error ($r) $!"
        if syswrite($soc,$r) != length($r);

    my ($status,$body) = fetch(fileno($soc));
    die "$status: $body"
        unless $status == 200;

    return $body;
}

1;
