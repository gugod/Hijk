package Hijk;

use strict;
use warnings;
use IO::Socket;

my $SocketCache = {};
sub _socket {
    my $args = shift;
    $SocketCache->{"$args->{host};$args->{port};$$"} ||= IO::Socket::INET->new(
        PeerHost => $args->{host},
        PeerPort => $args->{port},
        Proto    => "tcp",
        Blocking => 1,
        Type     => SOCK_STREAM,
        Timeout  => 60,
    );
}

sub get {
    my $args = $_[0];
    my $soc = _socket($args);
    my $NL = "\015\012";
    syswrite($soc, join(
        $NL,
        "GET $args->{path} HTTP/1.1",
        "Host: $args->{host}",
        $args->{body} ? ("Content-Length: " . length($args->{body})) : (),
        "",
        $args->{body} ? $args->{body} : ()
    ) . $NL);
    my ($head, $body, $buf) = ("")x3;
    my $block_size = 4096;
    if (sysread($soc, $buf, $block_size, 0)) {
        ($head, $body) = split(/${NL}${NL}/, $buf, 2);
        my ($content_length) = $head =~ m/^Content-Length: ([0-9]+)$/m;
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

