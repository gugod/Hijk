package Hijk::DEBUG;
use strict;

our $LOGDIR = "/tmp";

sub import {
    my ($caller_class, @args) = @_;
    my %args;
    if (@args % 2 == 0) {
        %args = @args;
    }

    if (exists $args{trace}) {
        $LOGDIR = $args{trace};
    }

    no strict 'refs';
    if (*{"Hijk::request"}{CODE}) {
        die "'use Hijk::DEBUG' must come before 'use Hijk' in order to be effective\n";
    }

    eval'sub Hijk::DEBUG(){1}';
}

sub LOG_CONNECTION {
    my ($cache_key, $direction, $content) = @_;

    $cache_key =~ s{\P{PosixPrint}+}{_}g;
    my $f = join("/", $LOGDIR, $cache_key . "_$direction");

    open my $fh, ">>", $f;
    print $fh $content;
    close($fh);
}

1;

__END__

use Hijk::DEBUG trace => "/tmp/hijk_debug";
