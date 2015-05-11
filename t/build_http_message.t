#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Hijk;

my $CRLF = "\x0d\x0a";

for my $protocol ("HTTP/1.0", "HTTP/1.1") {
    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com" }),
        "GET / $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "example.com" }),
        "GET / $protocol${CRLF}".
        "Host: example.com${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ method => "HEAD", protocol => $protocol, host => "example.com" }),
        "HEAD / $protocol${CRLF}".
        "Host: example.com${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", port => "8080" }),
        "GET / $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", query_string => "a=b" }),
        "GET /?a=b $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", path => "/flower" }),
        "GET /flower $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", path => "/flower", query_string => "a=b" }),
        "GET /flower?a=b $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", body => "morning" }),
        "GET / $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "Content-Length: 7${CRLF}".
        "${CRLF}".
        "morning";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", body => "0" }),
        "GET / $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "Content-Length: 1${CRLF}".
        "${CRLF}".
        "0";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", head => ["X-Head" => "extra stuff"] }),
        "GET / $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "X-Head: extra stuff${CRLF}".
        "${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", head => ["X-Head" => "extra stuff", "X-Hat" => "ditto"] }),
        "GET / $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "X-Head: extra stuff${CRLF}".
        "X-Hat: ditto${CRLF}${CRLF}";

    is Hijk::_build_http_message({ protocol => $protocol, host => "www.example.com", head => ["X-Head" => "extra stuff"], body => "OHAI" }),
        "GET / $protocol${CRLF}".
        "Host: www.example.com${CRLF}".
        "Content-Length: 4${CRLF}".
        "X-Head: extra stuff${CRLF}".
        "${CRLF}".
        "OHAI${CRLF}";
}

done_testing;
