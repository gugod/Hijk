#!/usr/bin/env perl
use strict;
use warnings;
use Benchmark ':all';
use Hijk;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request;

my $tiny = HTTP::Tiny->new();
my $req = HTTP::Request->new('GET','http://localhost:9200/_search');
my $body = '{"query":{"match_all":{}}}';
$req->content($body);
my $lwp = LWP::UserAgent->new();

# current results on Intel(R) Core(TM)2 Duo CPU P8400@2.26GHz with 2gb ram
# and elasticsearch with one index containing ~ 500 small documents:

#           Rate lwp____ tiny___ hijk pp hijk xs
#lwp____   593/s      --    -52%    -94%    -95%
#tiny___  1235/s    108%      --    -88%    -90%
#hijk pp 10101/s   1602%    718%      --    -22%
#hijk xs 12987/s   2088%    952%     29%      --

cmpthese(10_000,{
    'tiny___' => sub {
        my $res = $tiny->get('http://localhost:9200/_search',{content => $body });
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
