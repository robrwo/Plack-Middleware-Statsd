package Plack::Middleware::Statsd;

# ABSTRACT: send statistics to statsd

use v5.10;

use strict;
use warnings;

use parent qw/ Plack::Middleware /;

use Plack::Util;
use Plack::Util::Accessor qw/ client /;
use POSIX ();
use Time::HiRes;

our $VERSION = 'v0.2.1';

sub call {
    my ( $self, $env ) = @_;

    my $client = $self->client // $env->{'psgix.monitor.statsd'};
    $env->{'psgix.monitor.statsd'} //= $client;

    my $start = [Time::HiRes::gettimeofday];
    my $res   = $self->app->($env);

    return Plack::Util::response_cb(
        $res,
        sub {
            my $res = shift;

            return unless $client;

            my $histogram = $client->can('timing') // $client->can('timing_ms');

            my $elapsed = Time::HiRes::tv_interval($start);

            $client->$histogram( 'psgi.response.time',
                POSIX::ceil( $elapsed * 1000 ) );

            if ( defined $env->{CONTENT_LENGTH} ) {
                $client->$histogram( 'psgi.request.content-length',
                    $env->{CONTENT_LENGTH} );
            }

            if ( my $method = $env->{REQUEST_METHOD} ) {
                $client->increment( 'psgi.request.method.' . $method );
            }

            if ( my $type = $env->{CONTENT_TYPE} ) {
                $type =~ s#/#.#g;
                $type =~ s/;.*$//;
                $client->increment( 'psgi.request.content-type.' . $type );

            }

            $client->set_add( 'psgi.request.remote_addr', $env->{REMOTE_ADDR} )
              if $env->{REMOTE_ADDR};

            my $h = Plack::Util::headers( $res->[1] );

            my $xsendfile =
                 $env->{'plack.xsendfile.type'}
              || $ENV{HTTP_X_SENDFILE_TYPE}
              || 'X-Sendfile';

            if ( $h->exists($xsendfile) ) {
                $client->increment('psgi.response.x-sendfile');
            }

            if ( $h->exists('Content-Length') ) {
                my $length = $h->get('Content-Length') || 0;
                $client->$histogram( 'psgi.response.content-length', $length );
            }

            if ( my $type = $h->get('Content-Type') ) {
                $type =~ s#/#.#g;
                $type =~ s/;.*$//;
                $client->increment( 'psgi.response.content-type.' . $type );
            }

            $client->increment( 'psgi.response.status.' . $res->[0] );

            if (
                  $env->{'psgix.harakiri.supported'}
                ? $env->{'psgix.harakiri'}
                : $env->{'psgix.harakiri.commit'}
              )
            {
                $client->increment('psgix.harakiri');
            }

            $client->flush if $client->can('flush');

            return;
        }
    );

}

=head1 SYNOPSIS

  use Plack::Builder;
  use Net::Statsd::Client;

  builder {

    enable "Statsd",
      client      => Net::Statsd::Client->new( ... );

    ...

    sub {
      my ($env) = @_;

      # Send statistics via other middleware

      if (my $stats = $env->{'psgix.monitor.statsd'}) {

        $stats->increment('myapp.wibble');

      }


    };

  };

=head1 DESCRIPTION

This middleware gathers metrics from the application send sends them
to a statsd server.

=head1 ATTRIBUTES

=head2 client

This is a statsd client, such as an L<Net::Statsd::Client> object.

If one is omitted, then it will default to one defined in the
environment hash at C<psgix.monitor.statsd>.

C<psgix.monitor.statsd> will be set to the current client if it is not
set.

The only restriction on the client is that it has the same API as
L<Net::Statsd::Client> or similar modules, by supporting the following
methods:

=over

=item

C<increment>

=item

C<timing_ms> or C<timing>

=item

C<set_add>

=back

Other statsd client modules may be used via a wrapper class.

=head1 METRICS

The following metrics are logged:

=over

=item C<psgi.request.method.$METHOD>

This increments a counter for the request method.

=item C<psgi.request.remote_addr>

The remote address is added to the set.

=item C<psgi.request.content-length>

The content-length of the request, if it is specified in the header.

This is treated as a timing rather than a counter, so that statistics
can be saved.

=item C<psgi.request.content-type.$TYPE.$SUBTYPE>

A counter for the content type of request bodies is incremented, e.g.
C<psgi.request.content-type.application.x-www-form-urlencoded>.

Any modifiers in the type, e.g. C<charset>, will be ignored.

=item C<psgi.response.content-length>

The content-length of the response, if it is specified in the header.

This is treated as a timing rather than a counter, so that statistics
can be saved.

=item C<psgi.response.content-type.$TYPE.$SUBTYPE>

A counter for the content type is incremented, e.g. for a JPEG image,
the counter C<psgi.response.content-type.image.jpeg> is incremented.

Any modifiers in the type, e.g. C<charset>, will be ignored.

=item C<psgi.response.status.$CODE>

A counter for the HTTP status code is incremented.

=item C<psgi.response.time>

The response time, in ms (rounded up using C<ceil>).

=item C<psgi.response.x-sendfile>

This counter is incremented when the C<X-Sendfile> header is added.

The header is configured using the C<plack.xsendfile.type> environment
key, ortherwise the C<HTTP_X_SENDFILE_TYPE> environment variable.

See L<Plack::Middleware::XSendfile> for more information.

=item C<psgix.harakiri>

This counter is incremented when the harakiri flag is set.

=back

If you want to rename these, then you will need to use a wrapper
class for the L</client>.

=head1 EXAMPLES

=head2 Using from Catalyst

You can access the configured statsd client from L<Catalyst>:

  sub finalize {
    my $c = shift;

    if (my $statsd = $c->req->env->{'psgix.monitor.statsd'}) {
      ...


    }

    $c->next::method(@_);
  }

=head1 SEE ALSO

L<Net::Statsd::Client>

L<Net::Statsd::Tiny>

L<PSGI>

=head1 append:AUTHOR

The initial development of this module was sponsored by Science Photo
Library L<https://www.sciencephoto.com>.


=cut

1;
