#!/usr/bin/env perl
use strict;
use warnings;
use Benchmark;
use Hijk;
use Hijk::HTTP::XS;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request;

my $tiny = HTTP::Tiny->new();
my $req = HTTP::Request->new('GET','http://localhost:9200/_search');
my $body = '{"query":{"match_all":{}}}';
$req->content($body);
my $lwp = LWP::UserAgent->new();

# run with HACKED_REQUEST_PP=1 perl bench-elasticsearch.pl

# current results on Intel(R) Core(TM)2 Duo CPU P8400@2.26GHz with 2gb ram
# and elasticsearch with one index containing ~ 500 small documents:

#Benchmark: timing 10000 iterations of hijk pp, hijk xs, lwp____, tiny___...
#   hijk pp:  4 wallclock secs ( 0.79 usr +  0.20 sys =  0.99 CPU) @ 10101.01/s (n=10000)
#   hijk xs:  3 wallclock secs ( 0.48 usr +  0.30 sys =  0.78 CPU) @ 12820.51/s (n=10000)
#   lwp____: 21 wallclock secs (15.06 usr +  1.91 sys = 16.97 CPU) @ 589.28/s (n=10000)
#   tiny___: 11 wallclock secs ( 6.22 usr +  2.14 sys =  8.36 CPU) @ 1196.17/s (n=10000)


timethese(10_000,{
    'tiny___' => sub {
        my $res = $tiny->get('http://localhost:9200/_search',{content => $body });
    },
    'hijk xs' => sub {
        my $res = Hijk::request({path => "/_search", body => $body,
                                 host => 'localhost',
                                 port => 9200,
                                 fetch => \&Hijk::HTTP::XS::fetch,
                                 method => 'GET'});
    },
    'hijk pp' => sub {
        my $res = Hijk::request({path => "/_search", body => $body,
                                 host => 'localhost',
                                 port => 9200,
                                 method => 'GET'});
    },
    'lwp____' => sub {
        my $res = $lwp->request($req);
    },
});
