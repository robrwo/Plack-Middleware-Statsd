package Plack::Middleware::Statsd;

# ABSTRACT: send statistics to statsd

# RECOMMEND PREREQ:  Net::Statsd::Tiny v0.3.0
# RECOMMEND PREREQ:  HTTP::Status 6.16

use v5.10;

use strict;
use warnings;

use parent qw/ Plack::Middleware /;

use Plack::Util;
use Plack::Util::Accessor qw/ client sample_rate /;
use Time::HiRes;
use Try::Tiny;

our $VERSION = 'v0.3.7';

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

            my $rate = $self->sample_rate;

            $rate = undef if ( defined $rate ) && ( $rate >= 1 );

            my $histogram = $client->can('timing') // $client->can('timing_ms');
            my $increment = $client->can('increment');
            my $set_count = $client->can('set_add');

            my $logger  = $env->{'psgix.logger'};
            my $measure = sub {
                my ( $method, @args ) = @_;
                try {
                    return unless defined $method;
                    $client->$method( grep { defined $_ } @args );
                }
                catch {
                    if ($logger) {
                        $logger->( { message => $_, level => 'error' } );
                    }
                    else {
                        $env->{'psgi.errors'}->print($_);
                    }
                };
            };

            my $elapsed = Time::HiRes::tv_interval($start);

            $measure->(
                $histogram, 'psgi.response.time', $elapsed * 1000, $rate
            );

            if ( defined $env->{CONTENT_LENGTH} ) {
                $measure->(
                    $histogram, 'psgi.request.content-length',
                    $env->{CONTENT_LENGTH}, $rate
                );
            }

            if ( my $method = $env->{REQUEST_METHOD} ) {
                $measure->(
                    $increment, 'psgi.request.method.' . $method, $rate
                );
            }

            if ( my $type = $env->{CONTENT_TYPE} ) {
                $type =~ s#\.#-#g;
                $type =~ s#/#.#g;
                $type =~ s/;.*$//;
                $measure->(
                    $increment, 'psgi.request.content-type.' . $type, $rate
                );

            }

            $measure->(
                $set_count, 'psgi.request.remote_addr', $env->{REMOTE_ADDR}
            ) if $env->{REMOTE_ADDR};

            my $h = Plack::Util::headers( $res->[1] );

            my $xsendfile =
                 $env->{'plack.xsendfile.type'}
              || $ENV{HTTP_X_SENDFILE_TYPE}
              || 'X-Sendfile';

            if ( $h->exists($xsendfile) ) {
                $measure->( $increment, 'psgi.response.x-sendfile' );
            }

            if ( $h->exists('Content-Length') ) {
                my $length = $h->get('Content-Length') || 0;
                $measure->(
                    $histogram, 'psgi.response.content-length', $length
                );
            }

            if ( my $type = $h->get('Content-Type') ) {
                $type =~ s#\.#-#g;
                $type =~ s#/#.#g;
                $type =~ s/;.*$//;
                $measure->(
                    $increment, 'psgi.response.content-type.' . $type, $rate
                );
            }

            $measure->( $increment, 'psgi.response.status.' . $res->[0],
                $rate );

            if (
                  $env->{'psgix.harakiri.supported'}
                ? $env->{'psgix.harakiri'}
                : $env->{'psgix.harakiri.commit'}
              )
            {
                $measure->( $increment, 'psgix.harakiri' );    # rate == 1
            }

            $measure->( $client->can('flush') );

            return;
        }
    );

}

=head1 SYNOPSIS

  use Plack::Builder;
  use Net::Statsd::Tiny;

  builder {

    enable "Statsd",
      client      => Net::Statsd::Tiny->new( ... ),
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

=head2 client

This is a statsd client, such as an instance of L<Net::Statsd::Tiny>.

If one is omitted, then it will default to one defined in the
environment hash at C<psgix.monitor.statsd>.

C<psgix.monitor.statsd> will be set to the current client if it is not
set.

The only restriction on the client is that it has the same API as
L<Net::Statsd::Tiny> or similar modules, by supporting the following
methods:

=over

=item

C<increment>

=item

C<timing_ms> or C<timing>

=item

C<set_add>

=back

This has been tested with L<Net::Statsd::Lite> and
L<Net::Statsd::Client>.

Other statsd client modules may be used via a wrapper class.

=head2 sample_rate

The default sampling rate to be used, which should be a value between
0 and 1.  This will override the default rate of the L</client>, if
there is one.

The default is C<1>.

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

The response time, in ms.

As of v0.3.1, this is no longer rounded up to an integer. If this
causes problems with your statsd daemon, then you may need to use a
subclassed version of your statsd client to work around this.

=item C<psgi.response.x-sendfile>

This counter is incremented when the C<X-Sendfile> header is added.

The header is configured using the C<plack.xsendfile.type> environment
key, ortherwise the C<HTTP_X_SENDFILE_TYPE> environment variable.

See L<Plack::Middleware::XSendfile> for more information.

=item C<psgix.harakiri>

This counter is incremented when the harakiri flag is set.

=back

If you want to rename these, or modify sampling rates, then you will
need to use a wrapper class for the L</client>.

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

=head1 KNOWN ISSUES

=head2 Non-standard HTTP status codes

If your application is returning a status code that is not handled by
L<HTTP::Status>, then the metrics may not be logged for that reponse.

=head2 Support for older Perl versions

This module requires Perl v5.10 or newer.

Pull requests to support older versions of Perl are welcome. See
L</SOURCE>.

=head1 SEE ALSO

L<Net::Statsd::Client>

L<Net::Statsd::Tiny>

L<PSGI>

=head1 append:AUTHOR

The initial development of this module was sponsored by Science Photo
Library L<https://www.sciencephoto.com>.


=cut

1;
