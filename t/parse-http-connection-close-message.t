#!/usr/bin/env perl
use strict;
use Test::More;
use Test::Exception;

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
        ''
    );
    print $fh $msg;
    $fh->flush;
    $fh->seek(0, 0);
    fileno($fh);
};

my ($proto, $status, $body, $head) = Hijk::fetch($fd,0);


is $status, 200;
is $body, "";

is_deeply $head, {
    "Date" => "Sat, 23 Nov 2013 23:10:28 GMT",
    "Last-Modified" => "Sat, 26 Oct 2013 19:41:47 GMT",
    "ETag" => '"4b9d0211dd8a2819866bccff777af225"',
    "Content-Type" => "text/html",
    "Server" => "Example",
    "Connection" => "close",
};

throws_ok {
    my ($proto, $status, $body, $head) = Hijk::fetch($fd,0);
} qr /0 bytes/;

done_testing;
