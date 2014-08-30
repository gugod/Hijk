#!/usr/bin/env perl
use strict;
use Test::More;
use File::Temp ();
use File::Temp qw/ :seekable /;
use Hijk;

my $fh = File::Temp->new();
my $fd = do {
    local $/ = undef;
    my $data = "4\r\nWiki\r\n5\r\npedia\r\ne\r\n in\r\n\r\nchunks.\r\n0\r\n\r\n";

    my $msg = join(
        "\x0d\x0a",
        'HTTP/1.1 200 OK',
        'Date: Sat, 23 Nov 2013 23:10:28 GMT',
        'Last-Modified: Sat, 26 Oct 2013 19:41:47 GMT',
        'ETag: "4b9d0211dd8a2819866bccff777af225"',
        'Content-Type: text/html',
        'Server: Example',
        'Transfer-Encoding: chunked',
        'non-sence: ' . 'a' x 20000,
        '',
        $data
    );
    print $fh $msg;
    $fh->flush;
    $fh->seek(0, 0);
    fileno($fh);
};

my (undef, $proto, $status, $head, $body) = Hijk::_read_http_message($fd, undef, 1);


is $status, 200;
is $body, "Wikipedia in\r\n\r\nchunks.";

is_deeply $head, {
    "Date" => "Sat, 23 Nov 2013 23:10:28 GMT",
    "Last-Modified" => "Sat, 26 Oct 2013 19:41:47 GMT",
    "ETag" => '"4b9d0211dd8a2819866bccff777af225"',
    "Content-Type" => "text/html",
    "Server" => "Example",
    'non-sence' => 'a' x 20000,
    "Transfer-Encoding" => "chunked",
};

# fetch again without seeking back
# this will force select() to return because there are actually
# 0 bytes to read - so we can simulate connection closed 
# from the other end of the socket (like expired keep-alive)
my (undef, $proto, $status, $head, $body, $error, $error_message) = Hijk::_read_http_message($fd);
is $error, Hijk::Error::RESPONSE_BAD_READ_VALUE;
like $error_message, qr/0 byte/;

done_testing;
