#!/usr/bin/env perl
use strict;
use warnings;
use Benchmark;
use Hijk;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request;

my $tiny = HTTP::Tiny->new();
my $req = HTTP::Request->new('GET','http://localhost:9200/_search');
$req->content(q!{"query":{"match_all":{}}}!);
my $lwp = LWP::UserAgent->new();

# run with HACKED_REQUEST_PP=1 perl bench-elasticsearch.pl

# current results on Intel(R) Core(TM)2 Duo CPU P8400@2.26GHz with 2gb ram
# and elasticsearch with one index containing ~ 500 small documents:

# Benchmark: timing 100000 iterations of hijk pp, hijk xs, lwp____, tiny___...
#   hijk pp: 34 wallclock secs ( 6.45 usr +  3.02 sys =  9.47 CPU) @ 10559.66/s (n=100000)
#   hijk xs: 32 wallclock secs ( 4.38 usr +  3.38 sys =  7.76 CPU) @ 12886.60/s (n=100000)
#   lwp____: 200 wallclock secs (147.66 usr + 18.68 sys = 166.34 CPU) @ 601.18/s (n=100000)
#   tiny___: 112 wallclock secs (61.56 usr + 21.15 sys = 82.71 CPU) @ 1209.04/s (n=100000)


timethese(1_00_000,{
    'tiny___' => sub {
        my $res = $tiny->get('http://localhost:9200/_search',{content => '{"query":{"match_all":{}}}' });
    },
    'hijk xs' => sub {
        my $res = Hijk::request({path => "/_search", body => q!{"query":{"match_all":{}}}!,
                                 host => 'localhost',
                                 port => 9200,
                                 method => 'GET'});
    },
    ($ENV{HACKED_REQUEST_PP} ? (
    'hijk pp' => sub {
        my $res = Hijk::request_pp({path => "/_search", body => q!{"query":{"match_all":{}}}!,
                                 host => 'localhost',
                                 port => 9200,
                                 method => 'GET'});
    }
    ) : ()),
    'lwp____' => sub {
        my $res = $lwp->request($req);
    },

});
