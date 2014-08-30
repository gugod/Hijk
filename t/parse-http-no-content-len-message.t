#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use File::Temp ();
use File::Temp qw/ :seekable /;
use Hijk;

my $fh = File::Temp->new();
my $fd = do {
    local $/ = undef;

    my $msg = join(
        "\x0d\x0a",
        'HTTP/1.1 200 OK',
        'Date: Sat, 23 Nov 2013 23:10:28 GMT',
        'Last-Modified: Sat, 26 Oct 2013 19:41:47 GMT',
        'ETag: "4b9d0211dd8a2819866bccff777af225"',
        'Content-Type: text/html',
        'Server: Example',
        'Connection: close',
        '',
        'a' x 100000
    );
    print $fh $msg;
    $fh->flush;
    $fh->seek(0, 0);
    fileno($fh);
};

my (undef, $proto, $status, $head, $body) = Hijk::_read_http_message($fd, 10240, 0);


is $status, 200;
is_deeply $head, {
    "Date" => "Sat, 23 Nov 2013 23:10:28 GMT",
    "Last-Modified" => "Sat, 26 Oct 2013 19:41:47 GMT",
    "ETag" => '"4b9d0211dd8a2819866bccff777af225"',
    "Content-Type" => "text/html",
    "Server" => "Example",
    "Connection" => "close",
};
is $body, 'a' x 100000;

(undef, $proto, $status, $head, $body, my $error, my $error_message) = Hijk::_read_http_message($fd, 10240);
is $error, Hijk::Error::RESPONSE_BAD_READ_VALUE;
like $error_message, qr/0 byte/;

done_testing;
