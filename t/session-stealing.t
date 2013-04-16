#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.96 import => ["!pass"];
use File::Temp;
use HTTP::Date qw/str2time/;

plan skip_all => "Test::TCP required" unless eval {
    require Test::TCP; Test::TCP->import; 1;
};

plan skip_all => "LWP required" unless eval {
    require LWP;
    require HTTP::Cookies;
};

my $tempdir = File::Temp->newdir;

test_tcp(
    client => sub {
        my $port = shift;

        # Two different browsers
        my ($one, $two) = (HTTP::Cookies->new, HTTP::Cookies->new);
        my ($ua_one, $ua_two) = (LWP::UserAgent->new, LWP::UserAgent->new);
        $ua_one->cookie_jar($one);
        $ua_two->cookie_jar($two);

        my $res;

        # Set foo to one and two respectively
        $ua_one->get("http://127.0.0.1:$port/?foo=one");
        $ua_two->get("http://127.0.0.1:$port/?foo=two");

        # Retrieve both stored 
        $res = $ua_one->get("http://127.0.0.1:$port/");
        is $res->content, 'one', 'One received for first cookie';

        $res = $ua_two->get("http://127.0.0.1:$port/");
        is $res->content, 'two', 'Two received for second cookie';

        # Die against one and ensure we still get 'two' back for the second
        $ua_one->get("http://127.0.0.1:$port/die");

        $res = $ua_two->get("http://127.0.0.1:$port/");
        is $res->content, 'two', 'Two received after first died';
    },
    server => sub {
        my $port = shift;

        use Dancer ':tests', ':syntax';

        set port                => $port;
        set appdir              => $tempdir;
        set access_log          => 0;           # quiet startup banner

        set session_cookie_key => "John has a long mustache";
        set session            => "cookie";
        set show_traces        => 1;
        set warnings           => 1;
        set show_errors        => 1;

        get '/die' => sub {
            die 'Bad route';
        };

        get '/' => sub {
            if (my $foo = param('foo')) {
                session(foo => $foo);
            }
            return session('foo');
        };

        dance;
    }
);

done_testing;
