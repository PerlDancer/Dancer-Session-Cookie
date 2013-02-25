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
    test_tcp(
        client => sub {
            my $port = shift;
            subtest $config->{label} => sub {

                my $ua = LWP::UserAgent->new;
                my $cookie;
                # Simulate two different browsers with two different jars
                my @jars = (HTTP::Cookies->new, HTTP::Cookies->new);
                for my $jar (@jars) {
                    $ua->cookie_jar( $jar );

                    my $res = $ua->get("http://127.0.0.1:$port/foo");
                    is $res->content, "hits: 0, last_hit: ";
                    $cookie = extract_cookie($res, $config->{settings}{session_name});
                    ok $cookie, "session cookie set"
                        or diag explain $res->header('set-cookie');

                    $res = $ua->get("http://127.0.0.1:$port/bar");
                    $cookie = extract_cookie($res, $config->{settings}{session_name});
                    is( $res->content, "hits: 1, last_hit: foo")
                        or diag explain $res->header('set-cookie');

                    $res = $ua->get("http://127.0.0.1:$port/forward");
                    is $res->content, "hits: 2, last_hit: bar", "session not overwritten";

                    $res = $ua->get("http://127.0.0.1:$port/baz");
                    is $res->content, "hits: 3, last_hit: whatever";

                }

                $ua->cookie_jar($jars[0]);
                my $res = $ua->get("http://127.0.0.1:$port/wibble");
                is $res->content, "hits: 4, last_hit: baz", "session not overwritten";

                $res = $ua->get("http://127.0.0.1:$port/clear");
                is $res->content, "hits: 0, last_hit: ", "session destroyed";
            };
        },
        server => sub {
            my $port = shift;

            use Dancer ':tests', ':syntax';

            set port                => $port;
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
    );
}

done_testing;
