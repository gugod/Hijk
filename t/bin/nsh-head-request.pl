#!/usr/bin/env perl

use strict;
use warnings;

use parent 'Net::Server::HTTP';


my $port = $ARGV[0] // '3000';
__PACKAGE__->run( port => $port );;

sub process_http_request {
    my $self = shift;

    my ($gimme) = ($self->{request_info}{'query_string'} ||'') =~ m'gimme_content_length=(1?)$';

    if ($gimme) {
        print "Content-type: text/plain\n";
        print "Content-Length: 11\n\n";
    } else {
        print "Content-type: text/plain\n\n";
    }

    if ($self->{request_info}{request_method} ne 'HEAD') {
        print "Hello World\n";
    }
}
