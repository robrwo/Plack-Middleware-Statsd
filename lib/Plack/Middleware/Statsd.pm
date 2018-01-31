package Plack::Middleware::Statsd;

# ABSTRACT: send statistics to statsd

use v5.10;

use strict;
use warnings;

use parent qw/ Plack::Middleware /;

use Plack::Util;
use Plack::Util::Accessor qw/ client sample_rate /;
use POSIX ();
use Time::HiRes;

our $VERSION = 'v0.1.0';

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

            my $elapsed = Time::HiRes::tv_interval($start);

            my $rate = $self->sample_rate // 1;

            $client->timing_ms( 'psgi.response.time',
                POSIX::ceil( $elapsed * 1000 ), $rate );

            if ( defined $env->{CONTENT_LENGTH} ) {
                $client->timing_ms( 'psgi.request.content-length',
                    $env->{CONTENT_LENGTH}, $rate );
            }

            if ( my $method = $env->{REQUEST_METHOD} ) {
                $client->increment( 'psgi.request.method.' . $method, $rate );
            }

            if ( my $type = $env->{CONTENT_TYPE} ) {
                $type =~ s#/#.#g;
                $client->increment( 'psgi.request.content-type.' . $type,
                    $rate );

            }

            $client->set_add( 'psgi.request.remote_addr', $env->{REMOTE_ADDR},
                $rate )
              if $env->{REMOTE_ADDR};

            my $h = Plack::Util::headers( $res->[1] );

            if ( $h->exists('X-Sendfile') ) {    # TODO: configurable
                $client->increment( 'psgi.response.x-sendfile', $rate );
            }

            if ( $h->exists('Content-Length') ) {
                my $length = $h->get('Content-Length') || 0;
                $client->timing_ms( 'psgi.response.content-length',
                    $length, $rate );
            }

            if ( my $type = $h->get('Content-Type') ) {
                $type =~ s#/#.#g;
                $client->increment( 'psgi.response.content-type.' . $type,
                    $rate );
            }

            $client->increment( 'psgi.response.status.' . $res->[0], $rate );

            if (
                  $env->{'psgix.harakiri.supported'}
                ? $env->{'psgix.harakiri'}
                : $env->{'psgix.harakiri.commit'}
              )
            {
                $client->increment( 'psgix.harakiri', $rate );
            }

            return;
        }
    );

}

=head1 SYNOPSIS

  use Plack::Builder;
  use Net::Statsd::Client;

  builder {

    enable "Statsd",
      client      => Net::Statsd::Client->new( ... ),
      sample_rate => 1.0;

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

head2 client

This is a statsd client, such as an L<Net::Statsd::Client> object.

If one is omitted, then it will default to one defined in the
environment hash at C<psgix.monitor.statsd>.

C<psgix.monitor.statsd> will be set to the current client if it is not
set.

The only restriction on the client is that it has the same API as
L<Net::Statsd::Client> by supporting the following methods:

=over

=item

update

=item

increment

=item

decrement

=item

timing_ms

=item

set_add

=back

Other statsd client modules may be used via a wrapper class.

=head2 C<sample_rate>

The default sampling rate to used. This will override the default rate
of the L</client>.

It defaults to C<1>.

=head1 METRICS

The following metrics are logged:

=over

=item psgi.request.method.$METHOD

This increments a counter for the request method.

=item psgi.request.remote_addr

The remote address is added to the set.

=item psgi.request.content-length

The content-length of the request, if it is specified in the header.

This is treated as a timing rather than a counter, so that statistics
can be saved.

=item psgi.response.content-length

The content-length of the response, if it is specified in the header.

This is treated as a timing rather than a counter, so that statistics
can be saved.

=item psgi.response.content-type.$TYPE.$SUBTYPE

A counter for the content type is incremented, e.g. for a JPEG image,
the counter C<psgi.response.content-type.image.jpeg> is incremented.

=item psgi.response.status.$CODE

A counter for the HTTP status code is incremented.

=item psgi.response.time

The response time, in ms (rounded up using C<ceil>).

=back

If you want to rename these, then you will need to use a wrapper
class.

=head1 SEE ALSO

L<Net::Statsd::Client>

L<PSGI>

=head1 append:AUTHOR

The initial development of this module was sponsored by Science Photo
Library L<https://www.sciencephoto.com>.


=cut

1;
