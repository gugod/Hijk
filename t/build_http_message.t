#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Hijk;

my $http_message;

is Hijk::build_http_message({ host => "www.example.com" }),
    "GET / HTTP/1.1\x0d\x0aHost: www.example.com\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "example.com" }),
    "GET / HTTP/1.1\x0d\x0aHost: example.com\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", port => "8080" }),
    "GET / HTTP/1.1\x0d\x0aHost: www.example.com\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", query_string => "a=b" }),
    "GET /?a=b HTTP/1.1\x0d\x0aHost: www.example.com\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", path => "/flower" }),
    "GET /flower HTTP/1.1\x0d\x0aHost: www.example.com\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", path => "/flower", query_string => "a=b" }),
    "GET /flower?a=b HTTP/1.1\x0d\x0aHost: www.example.com\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", body => "morning" }),
    "GET / HTTP/1.1\x0d\x0a".
    "Host: www.example.com\x0d\x0a".
    "Content-Length: 7\x0d\x0a\x0d\x0a".
    "morning\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", head => ["X-Head" => "extra stuff"] }),
    "GET / HTTP/1.1\x0d\x0a".
    "Host: www.example.com\x0d\x0a".
    "X-Head: extra stuff\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", head => ["X-Head" => "extra stuff", "X-Hat" => "ditto"] }),
    "GET / HTTP/1.1\x0d\x0a".
    "Host: www.example.com\x0d\x0a".
    "X-Head: extra stuff\x0d\x0a".
    "X-Hat: ditto\x0d\x0a\x0d\x0a";

is Hijk::build_http_message({ host => "www.example.com", head => ["X-Head" => "extra stuff"], body => "OHAI" }),
    "GET / HTTP/1.1\x0d\x0a".
    "Host: www.example.com\x0d\x0a".
    "Content-Length: 4\x0d\x0a".
    "X-Head: extra stuff\x0d\x0a".
    "\x0d\x0a".
    "OHAI\x0d\x0a";

done_testing;
