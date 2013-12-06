#!/usr/bin/env perl
use strict;
use warnings;
use Benchmark;
use Hijk;
use Hijk::HTTP::XS;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request;

foreach my $f(qw(1k.img 10k.img 100k.img 1m.img)) {
    my $tiny = HTTP::Tiny->new();
    my $req = HTTP::Request->new('GET',"http://localhost:8080/$f");
    my $lwp = LWP::UserAgent->new();
    timethese(10_000,{
        $f. ' tiny___' => sub {
            my $res = $tiny->get("http://localhost:8080/$f");
        },
        $f . ' hijk xs' => sub {
            my $res = Hijk::request({path => "/$f",
                                     host => 'localhost',
                                     port => 8080,
                                     fetch => \&Hijk::HTTP::XS::fetch,
                                     method => 'GET'});
        },
        $f . ' hijk pp' => sub {
            my $res = Hijk::request({path => "/$f",
                                     host => 'localhost',
                                     port => 8080,
                                     method => 'GET'});
        },
        $f . ' lwp____' => sub {
            my $res = $lwp->request($req);
        },
    });
}
