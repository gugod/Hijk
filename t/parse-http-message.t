#!/usr/bin/env perl
use strict;
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
        'Content-Length: 4',
        'Server: Example',
        '',
        'OHAI'
    );

    print $fh $msg;
    $fh->flush;
    $fh->seek(0, 0);
    fileno($fh);
};

my ($status, $body, $head) = Hijk::pp_fetch($fd);


is $status, 200;
is $body, "OHAI";

TODO: {
    ;
    local $TODO = "requies pp_fetch to return 3 elements.";

    is_deeply $head, {
        "Date" => "Sat, 23 Nov 2013 23:10:28 GMT",
        "Last-Modified" => "Sat, 26 Oct 2013 19:41:47 GMT",
        "ETag" => "4b9d0211dd8a2819866bccff777af225",
        "Content-Type" => "text/html",
        "Content-Length" => "4",
        "Server" => "Example",
    };
};

done_testing;
