#!/usr/bin/env perl

use strict;
use warnings;

use Test::More import => ["!pass"];

plan skip_all => "Test::WWW::Mechanize::PSGI required" unless eval {
    require Test::WWW::Mechanize::PSGI;
};

my $app = create_app();

$app->get_ok( '/xxx' );
$app->content_is( '/xxx' );

sub create_app {
    my $app = Test::WWW::Mechanize::PSGI->new( app => do {
    package MyApp;

        use Dancer ':tests', ':syntax';

        set apphandler          => 'PSGI';
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
)}

done_testing;

