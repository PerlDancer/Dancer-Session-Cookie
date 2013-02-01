package Dancer::Session::Cookie;
use strict;
use warnings;
# ABSTRACT: Encrypted cookie-based session backend for Dancer
# VERSION

use base 'Dancer::Session::Abstract';

use Session::Storage::Secure;
use Crypt::CBC;
use String::CRC32;
use Crypt::Rijndael;

use Dancer ':syntax';
use Storable     ();
use MIME::Base64 ();

# crydec
my $CIPHER = undef;
my $STORE = undef;

# cache session here instead of flushing/reading from cookie all the time
my $SESSION = undef;

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    my $key = setting("session_cookie_key")  # XXX default to smth with warning
      or die "The setting session_cookie_key must be defined";

    my $expires = setting('session_expires');

    $CIPHER = Crypt::CBC->new(
        -key    => $key,
        -cipher => 'Rijndael',
    );

    $STORE = Session::Storage::Secure->new(
        secret_key => $key,
        ( $expires ? (default_duration => $expires) : () ),
    );
}

# return our cached ID if we have it instead of looking in a cookie
sub read_session_id {
    my ($self) = @_;
    return $SESSION->id
      if defined $SESSION;
    return $self->SUPER::read_session_id;
}

sub retrieve {
    my ($class, $id) = @_;
    # if we have a cached session, hand that back instead
    # of decrypting again
    return $SESSION
      if $SESSION && $SESSION->id eq $id;

    my $ses = eval {
        if ( my $hash = $STORE->decode($id) ) {
            # we recover a plain hash, so reconstruct into object
            bless $hash, $class;
        }
        else {
            _old_retrieve($id)
        }
    };

    return $SESSION = $ses;
}

# support decoding old cookies
sub _old_retrieve {
    my ($id) = @_;
    # 1. decrypt and deserialize $id
    my $plain_text = _old_decrypt($id);
    # 2. deserialize
    $plain_text && Storable::thaw($plain_text);
}

sub create {
    my $class = shift;
    # cache the newly created session
    return $SESSION = Dancer::Session::Cookie->new;
}

# we don't write session ID when told; we do it in the after hook
sub write_session_id {}

# we don't flush when we're told; we do it in the after hook
sub flush {}

sub destroy {
    my $self = shift;

    # gross hack; replace guts with new session guts
    %$self = %{ Dancer::Session::Cookie->new };

    return 1;
}

# Copied from Dancer::Session::Abstract::write_session_id and
# refactored for testing
hook 'after' => sub {
    if ( $SESSION ) {
        my $c = Dancer::Cookie->new($SESSION->_cookie_params);
        Dancer::Cookies->set_cookie_object($c->name => $c);
        undef $SESSION; # clear for next request
    }
};

# modified from Dancer::Session::Abstract::write_session_id to add
# support for session_cookie_path
sub _cookie_params {
    my $self = shift;
    my $name = $self->session_name;
    my $expires = setting('session_expires');
    my %cookie = (
        name   => $name,
        value  => $self->_cookie_value($expires),
        path   => setting('session_cookie_path') || '/',
        domain => setting('session_domain'),
        secure => setting('session_secure'),
        http_only => defined(setting("session_is_http_only")) ?
                     setting("session_is_http_only") : 1,
    );
    if (my $expires = setting('session_expires')) {
        # It's # of seconds from the current time
        # Otherwise just feed it through.
        $expires = Dancer::Cookie::_epoch_to_gmtstring(time + $expires) if $expires =~ /^\d+$/;
        $cookie{expires} = $expires;
    }
    return %cookie;
}

# refactored for testing
sub _cookie_value {
    my ($self, $expires) = @_;
    # copy self guts so we aren't serializing a blessed object
    return $STORE->encode({ %$self }, $expires);
}

# legacy algorithm
sub _old_decrypt {
    my $cookie = shift;

    $cookie =~ tr{_*-}{=+/};

    $SIG{__WARN__} = sub {};
    my ($crc32, $plain_text) = unpack "La*",
      $CIPHER->decrypt(MIME::Base64::decode($cookie));
    return $crc32 == String::CRC32::crc32($plain_text) ? $plain_text : undef;
}

1;
__END__

=head1 SYNOPSIS

Your F<config.yml>:

    session: "cookie"
    session_cookie_key: "this random key IS NOT very random"

=head1 DESCRIPTION

This module implements a session engine for sessions stored entirely
in cookies. Usually only B<session id> is stored in cookies and
the session data itself is saved in some external storage, e.g.
database. This module allows to avoid using external storage at
all.

Since server cannot trust any data returned by client in cookies, this
module uses cryptography to ensure integrity and also secrecy. The
data your application stores in sessions is completely protected from
both tampering and analysis on the client-side.

=head1 CONFIGURATION

The setting B<session> should be set to C<cookie> in order to use this session
engine in a Dancer application. See L<Dancer::Config>.

A mandatory setting is needed as well: B<session_cookie_key>, which should
contain a random string of at least 16 characters (shorter keys are
not cryptographically strong using AES in CBC mode).

Here is an example configuration to use in your F<config.yml>:

    session: "cookie"
    session_cookie_key: "kjsdf07234hjf0sdkflj12*&(@*jk"

Compromising B<session_cookie_key> will disclose session data to
clients and proxies or eavesdroppers and will also allow tampering,
for example session theft. So, your F<config.yml> should be kept at
least as secure as your database passwords or even more.

Also, changing B<session_cookie_key> will have an effect of immediate
invalidation of all sessions issued with the old value of key.

B<session_cookie_path> can be used to control the path of the session
cookie.  The default is /.

The global B<session_secure> setting is honoured and a secure (https
only) cookie will be used if set.

=head1 DEPENDENCY

This module depends on L<Session::Storage::Secure>.  Legacy support is provided
using L<Crypt::CBC>, L<Crypt::Rijndael>, L<String::CRC32>, L<Storable> and
L<MIME::Base64>.

=head1 SEE ALSO

See L<Dancer::Session> for details about session usage in route handlers.

See L<Plack::Middleware::Session::Cookie>,
L<Catalyst::Plugin::CookiedSession>, L<Mojolicious::Controller/session> for alternative implementation of this mechanism.

=cut
