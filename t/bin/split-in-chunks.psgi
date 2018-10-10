#!/usr/bin/env perl
# need Starman to produce chunked response.
#  starman --worker 4 t/bin/split-in-chunks.psgi
## perl -E 'print "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"' | nc localhost 5000

use strict;
use warnings;

my $epic_graph = <<TEXT;
    If they just went straight they might go far,
    They are strong and brave and true;
    But they're always tired of the things that are,
    And they want the strange and new.
    They say: "Could I find my proper groove,
    What a deep mark I would make!"
    So they chop and change, and each fresh move
    Is only a fresh mistake.
TEXT

sub {
    my $env = shift;

    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type', 'text/plain' ]]);

        while($epic_graph) {
            my $l = rand() * 30 + 1;
            my $chunk = substr($epic_graph, 0, $l, '');
            $writer->write($chunk);
        }
        $writer->close;
    }
}
