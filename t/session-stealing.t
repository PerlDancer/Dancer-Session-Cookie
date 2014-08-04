#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.96 import => ["!pass"];
use File::Temp;
use HTTP::Date qw/str2time/;

plan skip_all => "Test::WWW::Mechanize::PSGI required" unless eval {
    require Test::WWW::Mechanize::PSGI;
};

my $tempdir = File::Temp->newdir;

my $app = build_app();

# Two different browsers
my @mechs = map { new_mech($app) } 1..2;

    # Set foo to one and two respectively
    $mechs[0]->get_ok( '/?foo=one' );
    $mechs[1]->get_ok( '/?foo=two' );

    # Retrieve both stored 
    $mechs[0]->get_ok('/');
    $mechs[0]->content_is('one');

    $mechs[1]->get_ok('/');
    $mechs[1]->content_is('two');

    $mechs[0]->get( '/die' );
    is $mechs[0]->status => 500, "we died";

    $mechs[1]->get_ok('/');
    $mechs[1]->content_is( 'two', 'Two received after first died' );

sub new_mech { 
    Test::WWW::Mechanize::PSGI->new( app => shift );
}

sub build_app {
    return Test::WWW::Mechanize::PSGI->new( app => do {

        package MyApp;

        use Dancer ':tests', ':syntax';

        set apphandler          => 'PSGI';
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

        return dance;
    }
);
}

done_testing;
