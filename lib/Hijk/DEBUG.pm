package Hijk::DEBUG;
use strict;

our $LOGDIR = "/tmp";

sub import {
    no strict 'refs';
    if (*{"Hijk::request"}{CODE}) {
        die "Hijk::DEBUG must be used before Hijk to be effective\n";
    }

    eval'sub Hijk::DEBUG(){1}';
}

sub LOG {
    print STDERR $_[0] . "\n";
}

1;
