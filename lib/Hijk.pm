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
    my ($head,$neck,$body,$buf) = ("", "${CRLF}${CRLF}");
    my ($block_size, $content_length, $decapitated, $status_code) = (10240);

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
                    ($content_length) = $head =~ m< ${CRLF} Content-Length:\ ([0-9]+) (?:${CRLF}|\z)  >oxi;
                    if ($content_length) {
                        $body = substr($buf, $neck_pos + length($neck));
                        $block_size = $content_length - length($body);
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

    return ($status_code, $body);
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
    return {
        status => $status,
        body => $body
    };
}

1;
