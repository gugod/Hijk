#!/usr/bin/env perl
use strict;
use Test::More;
use File::Temp ();
use File::Temp qw/ :seekable /;
use Hijk;
use Test::Exception;

my $fh = File::Temp->new();
my $fd = do {
    local $/ = undef;
    my $data = "4\r\nWiki\r\n5\r\npedia\r\ne\r\n in\r\n\r\nchunks.\r\n0\r\n";

    my $msg = join(
        "\x0d\x0a",
        'HTTP/1.1 200 OK',
        'Last-Modified: Sat, 26 Oct 2013 19:41:47 GMT',
        'ETag: "4b9d0211dd8a2819866bccff777af225"',
        'Content-Type: text/html',
        'Server: Example',
        'Transfer-Encoding: chunked',
        'Trailer: Date',
        'non-sence: ' . 'a' x 20000,
        '',
        $data,
        'Date: Sat, 23 Nov 2013 23:10:28 GMT',
        ''
    );
    print $fh $msg;
    $fh->flush;
    $fh->seek(0, 0);
    fileno($fh);
};
my ($proto, $status, $head, $body) = Hijk::_read_http_message($fd);


is $status, 200;
is $body, "Wikipedia in\r\n\r\nchunks.";

is_deeply $head, {
    "Last-Modified" => "Sat, 26 Oct 2013 19:41:47 GMT",
    "ETag" => '"4b9d0211dd8a2819866bccff777af225"',
    "Content-Type" => "text/html",
    "Server" => "Example",
    'non-sence' => 'a' x 20000,
    "Transfer-Encoding" => "chunked",
    'Trailer' => 'Date',
};
# fetch again without seeking back
# this will force select() to return because there are actually
# 0 bytes to read - so we can simulate connection closed
# from the other end of the socket (like expired keep-alive)
throws_ok {
    my ($proto, $status, $head, $body) = Hijk::_read_http_message($fd);
} qr /0 bytes/i;

done_testing;
