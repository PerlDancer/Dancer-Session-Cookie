#!/usr/bin/env perl

use strict;
use warnings;

use Test::More import => ["!pass"];

plan skip_all => "Test::TCP required" unless eval {
    require Test::TCP; Test::TCP->import; 1;
};

plan skip_all => "LWP required" unless eval {
    require LWP;
};

test_tcp(
    client => sub {
        my $port = shift;

        require LWP::UserAgent;
        require HTTP::Cookies;

        my $ua = LWP::UserAgent->new;
        my $jar = HTTP::Cookies->new;
        $ua->cookie_jar( $jar );

        my $res = $ua->get("http://127.0.0.1:$port/xxx");
        is $res->content, "/xxx";

    },
    server => sub {
        my $port = shift;

        use Dancer ':tests', ':syntax';

        set port                => $port;
        set appdir              => '';          # quiet warnings not having an appdir
        set access_log          => 0;           # quiet startup banner

        set session_cookie_key  => "John has a long mustache";
        set session             => "cookie";

        get '/b' => sub {
            return session('abc');
        };

        hook 'before' => sub {
            my $a = request->path_info;
            if ( not request->path_info =~ m{^/(a|b|c)} ){
                session abc => $a ;
                return redirect '/b';
            }
        };

        dance;
    }
);

done_testing;

