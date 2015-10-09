#!/usr/bin/env perl
use strict;
use warnings;

sub {
    my $env = shift;
    my ($gimme_content_length) = $env->{QUERY_STRING} =~ m/\Agimme_content_length=([01])\z/;
    my $hello_world = "Hello world";
    return [
        $gimme_content_length ? 200 : 204,
        [],
        [$gimme_content_length ? $hello_world : undef],
    ];
}
