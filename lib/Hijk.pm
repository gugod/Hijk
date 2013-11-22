package Hijk;

use strict;
use warnings;
use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton $CRLF);

my $SocketCache = {};

sub request {
    my $args = $_[0];

    my $soc = $SocketCache->{"$args->{host};$args->{port};$$"} ||= do {
        my $soc;
        socket($soc, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
        connect($soc, sockaddr_in($args->{port}, inet_aton($args->{host})));
        $soc;
    };

    syswrite($soc, join(
        $CRLF,
        "$args->{method} $args->{path} HTTP/1.1",
        "Host: $args->{host}",
        $args->{body} ? ("Content-Length: " . length($args->{body})) : (),
        "",
        $args->{body} ? $args->{body} : ()
    ) . $CRLF);
    my ($head, $body, $buf);
    my $block_size = 10240;
    if (sysread($soc, $buf, $block_size, 0)) {
        ($head, $body) = split(/${CRLF}${CRLF}/o, $buf, 2);
        my ($content_length) = $head =~ m/^Content-Length: ([0-9]+)$/om;
        while ( length($body) < $content_length ) {
            my $r = sysread($soc, $body, $block_size, length($body));
            unless($r) {
                last if defined($r);
                die "Failed to read the full response body.";
            }
        }
    }
    else {
        die "Failed to read the first block.";
    }
    return $body;
}

1;

