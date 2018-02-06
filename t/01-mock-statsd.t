#!perl

use Test::Most;

use HTTP::Request::Common;
use Plack::Builder;
use Plack::Test;

use lib "t/lib";
use MockStatsd;

my $stats = MockStatsd->new;

my $handler = builder {
    enable "Statsd", client => $stats;
    enable "ContentLength";
    enable "Head";

    sub {
        my $env    = shift;
        my $client = $env->{'psgix.monitor.statsd'};
        return [
            $client ? 200 : 202,
            [ 'Content-Type' => 'text/plain; charset=utf8' ], ['Ok']
        ];
    };
};

test_psgi
  app    => $handler,
  client => sub {
    my $cb = shift;

    subtest 'head' => sub {

        my $req = HEAD '/';
        my $res = $cb->($req);

        is $res->code, 200, join( " ", $req->method, $req->uri );

        my @metrics = $stats->reset;

        cmp_deeply \@metrics,
          bag(
            [ 'timing_ms', 'psgi.response.time',           ignore(), ],
            [ 'timing_ms', 'psgi.request.content-length',  0, ],
            [ 'increment', 'psgi.request.method.HEAD', ],
            [ 'set_add',   'psgi.request.remote_addr',     '127.0.0.1', ],
            [ 'timing_ms', 'psgi.response.content-length', 0, ],
            [ 'increment', 'psgi.response.content-type.text.plain', ],
            [ 'increment', 'psgi.response.status.200', ],
          ),
          'expected metrics'
          or note( explain \@metrics );

    };

    subtest 'head' => sub {

        my $req = HEAD '/';
        my $res = $cb->($req);

        is $res->code, 200, join( " ", $req->method, $req->uri );

        my @metrics = $stats->reset;

        cmp_deeply \@metrics,
          bag(
            [ 'timing_ms', 'psgi.response.time',           ignore(), ],
            [ 'timing_ms', 'psgi.request.content-length',  0, ],
            [ 'increment', 'psgi.request.method.HEAD', ],
            [ 'set_add',   'psgi.request.remote_addr',     '127.0.0.1', ],
            [ 'timing_ms', 'psgi.response.content-length', 2, ],
            [ 'increment', 'psgi.response.content-type.text.plain', ],
            [ 'increment', 'psgi.response.status.200', ],
          ),
          'expected metrics'
          or note( explain \@metrics );

    };

  };

done_testing;
