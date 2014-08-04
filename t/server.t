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

sub find_cookie {
  my ($res, $name) = @_;
  $name ||= 'dancer.session';
  my @cookies = $res->header('set-cookie');
  for my $c (@cookies) {
    next unless $c =~ /\Q$name\E/;
    return $c;
  }
  return;
}

sub extract_cookie {
  my ($res, $name) = @_;
  my $c = find_cookie($res, $name) or return;
  my @parts = split /;\s+/, $c;
  my %hash =
    map { my ( $k, $v ) = split /\s*=\s*/; $v ||= 1; ( lc($k), $v ) } @parts;
  $hash{expires} = str2time( $hash{expires} )
    if $hash{expires};
  return \%hash;
}

my @configs = (
    {
        label => 'default config',
        settings => {},
    },
    {
        label => 'alternate name',
        settings => {
            session_name => "my_app_session",
        },
    },
    {
        label => 'expires 300',
        settings => {
            session_expires => 300,
            session_name => undef,
        },
    },
    {
        label => 'expires +1h',
        settings => {
            session_expires => "1 hour",
        },
    },
);

for my $config ( @configs ) {
    my $app = create_app( $config );

            subtest $config->{label} => sub {

                # Simulate two different browsers with two different jars
                my @mechs = map { Test::WWW::Mechanize::PSGI->new( app => $app) } 1..2;

            for my $mech (@mechs) {
                subtest 'one browser' => sub {
                    $mech->get_ok( '/foo' );
                    $mech->content_is( 'hits: 0, last_hit: ');
                    my $cookie = extract_cookie($mech->res, $config->{settings}{session_name});
                    ok $cookie, "session cookie set"
                        or diag explain $mech->res->header('set-cookie');

                    $mech->get_ok( '/bar' );
                    $cookie = extract_cookie($mech->res, $config->{settings}{session_name});
                    $mech->content_is( "hits: 1, last_hit: foo")
                        or diag explain $mech->res->header('set-cookie');

                    $mech->get_ok( '/forward' );
                    $mech->content_is( "hits: 2, last_hit: bar", "session not overwritten" );

                    $mech->get_ok( '/baz' );
                    $mech->content_is("hits: 3, last_hit: whatever");
                }

            }

                $mechs[0]->get_ok( '/wibble' );
                $mechs[0]->content_is("hits: 4, last_hit: baz", "session not overwritten");

                $mechs[0]->get_ok("/clear");
                $mechs[0]->content_is( "hits: 0, last_hit: ", "session destroyed" );
            };
}


sub create_app {
    my $config = shift;

    use Dancer ':tests', ':syntax';

    set apphandler          => 'PSGI';
    set appdir              => $tempdir;
    set access_log          => 0;           # quiet startup banner

    set session_cookie_key  => "John has a long mustache";
    set session             => "cookie";
    set show_traces => 1;
    set warnings => 1;
    set show_errors => 1;

    set %{$config->{settings}} if %{$config->{settings}};

    get "/clear" => sub {
        session "useless" =>  1; # force write/flush
        session->destroy;
        redirect '/postclear';
    };

    get "/forward" => sub {
        session ignore_me => 1;
        forward '/whatever';
    };

    get "/*" => sub {
        my $hits = session("hit_counter") || 0;
        my $last = session("last_hit") || '';

        session hit_counter => $hits + 1;
        session last_hit => (splat)[0];

        return "hits: $hits, last_hit: $last";
    };

    dance;
}

done_testing;
