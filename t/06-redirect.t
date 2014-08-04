#!/usr/bin/env perl

use strict;
use warnings;

use Test::More import => ["!pass"];

plan skip_all => "Test::WWW::Mechanize::PSGI required" unless eval {
    require Test::WWW::Mechanize::PSGI;
};

plan skip_all => "LWP required" unless eval {
    require LWP;
};

{
    package MyApp;

    use Dancer ':tests', ':syntax';

    set appdir              => '';          # quiet warnings not having an appdir
    set access_log          => 0;           # quiet startup banner

    set session_cookie_key  => "John has a long mustache";
    set session             => "cookie";

    hook before => sub { 
        if ( !session('uid') 
            && request->path_info !~ m{^/login} 
        ) {
            return redirect '/login/';
        }
    };

    get '/logout/?' => sub {
        session 'uid'     => undef;
        session->destroy;
        return redirect '/';
    };

    any '/login/?' => sub {
        return redirect '/' if session('uid');

        return 'ok' if session('login');
        session 'login' => undef;
        return 'login page';
    };
}


my $app = Test::WWW::Mechanize::PSGI->new(
    app => Dancer::Handler->psgi_app
);

$app->get_ok( '/' );
$app->content_is( 'login page' );

done_testing;

