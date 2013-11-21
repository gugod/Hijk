package Tijk;

use strict;
use warnings;
use IO::Socket;

my $SocketCache = {};

sub _socket {
    my $args = shift;
    IO::Socket::INET->new(
        PeerHost => $args->{host},
        PeerPort => $args->{port},
        Proto    => "tcp",
        Blocking => 1,
    );
}

sub get {
    my $args = $_[0];
    my $soc = _socket($args);
    my $NL = "\015\012";
    print $soc join(
        $NL,
        "GET $args->{path} HTTP/1.0",
        $args->{body} ? ("Content-Length: " . length($args->{body})) : (),
        "",
        $args->{body} ? $args->{body} : ()
    ) . $NL;
    my ($head, $body, $buf) = ("")x3;
    my $block_size = 4096;
    if (read($soc, $buf, $block_size)) {
        ($head, $body) = split(/${NL}${NL}/, $buf, 2);
        while (1) {
            my $r = read($soc, $buf, $block_size);
            if ($r) {
                $body .= $buf;
            }
            else {
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

