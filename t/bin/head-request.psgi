#!/usr/bin/env perl
use strict;
use warnings;

sub {
    my $env = shift;
    my ($gimme_content_length) = $env->{QUERY_STRING} =~ m/\Agimme_content_length=([01])\z/;

    my $hello_world = "Hello world";
    my $content_length = length($hello_world);
    if ($env->{REQUEST_METHOD} eq 'HEAD') {
        $hello_world = '';
    }

    return [
        200,
        [
            ($gimme_content_length
             ? ( 'Content-Length' => length($hello_world) )
             : ()),
        ],
        [$hello_world],
    ];
}
