#!perl

use utf8;

use Test::Most;

use HTTP::Request;
use HTTP::Request::Common;
use Plack::Builder;
use Plack::MIME;
use Plack::Test;

use lib "t/lib";
use MockStatsd;

my $stats = MockStatsd->new;

my @logs;

my $handler = builder {

    enable sub {
        my $app = shift;
        sub {
            my $env = shift;
            $env->{'psgix.logger'} = sub { push @logs, shift };
            return $app->($env);
        };
    };

    enable "Statsd", client => $stats;
    enable "ContentLength";
    enable "Head";

    sub {
        my $env    = shift;
        my $path   = $env->{PATH_INFO};
        my $type   = Plack::MIME->mime_type($path);
        my $client = $env->{'psgix.monitor.statsd'};
        my $code   = $env->{REQUEST_METHOD} =~ /^\w+$/a ? 200 : 405;
        return [
            $client ? $code : 500,
            [ 'Content-Type' => $type || 'text/plain; charset=utf8' ], ['Ok']
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
            [ 'set_add',   'psgi.worker.pid', $$ ],
          ),
          'expected metrics'
          or note( explain \@metrics );

        is_deeply \@logs, [], 'nothing logged';

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
            [ 'timing_ms', 'psgi.response.content-length', 0, ],
            [ 'increment', 'psgi.response.content-type.text.plain', ],
            [ 'increment', 'psgi.response.status.200', ],
            [ 'set_add',   'psgi.worker.pid', $$ ],
          ),
          'expected metrics'
          or note( explain \@metrics );

        is_deeply \@logs, [], 'nothing logged';

    };

    subtest 'errors' => sub {

        my $req = POST '/',
          Content_Type => 'text/x-something',
          Content      => "Some data";

        my $res = $cb->($req);

        is $res->code, 200, join( " ", $req->method, $req->uri );

        my @metrics = $stats->reset;

        cmp_deeply \@metrics, bag(
            [ 'timing_ms', 'psgi.response.time',          ignore(), ],
            [ 'timing_ms', 'psgi.request.content-length', 9, ],
            [ 'increment', 'psgi.request.content-type.text.x-something', ],

            # Note: the mock class throws an error so no method is logged
            [ 'set_add',   'psgi.request.remote_addr',     '127.0.0.1', ],
            [ 'timing_ms', 'psgi.response.content-length', 2, ],
            [ 'increment', 'psgi.response.content-type.text.plain', ],
            [ 'increment', 'psgi.response.status.200', ],
            [ 'set_add',   'psgi.worker.pid', $$ ],
          ),
          'expected metrics'
          or note( explain \@metrics );

        cmp_deeply \@logs,
          [
            {
                level   => 'error',
                message => re('^Error at t/lib/MockStatsd\.pm line \d+'),
            }
          ],
          'errors logged'
          or note( explain \@logs );

        @logs = ();
    };

    subtest 'head (favicon.ico)' => sub {

        my $req = HEAD '/favicon.ico';
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
            [ 'increment', 'psgi.response.content-type.image.vnd-microsoft-icon', ],
            [ 'increment', 'psgi.response.status.200', ],
            [ 'set_add',   'psgi.worker.pid', $$ ],
          ),
          'expected metrics'
          or note( explain \@metrics );

        is_deeply \@logs, [], 'nothing logged'
            or note( explain \@logs);

    };


    subtest 'bad method' => sub {

        my $req = HTTP::Request->new( "SPỌRK" => '/' );

        my $res = $cb->($req);

        is $res->code, 405, 'unsupported method';

        my @metrics = $stats->reset;

        cmp_deeply \@metrics,
          bag(
            [ 'timing_ms', 'psgi.response.time',          ignore(), ],
            [ 'timing_ms', 'psgi.request.content-length', 0, ],
            [ 'increment', 'psgi.request.method.other', ],
            [ 'set_add',   'psgi.request.remote_addr',     '127.0.0.1', ],
            [ 'set_add',   'psgi.worker.pid',              ignore() ],
            [ 'timing_ms', 'psgi.response.content-length', 2, ],
            [ 'increment', 'psgi.response.content-type.text.plain', ],
            [ 'increment', 'psgi.response.status.405', ],
          ),
          'expected metrics'
          or note( explain \@metrics );

        cmp_deeply \@logs, [], 'no errors logged'
          or note( explain \@logs );

        @logs = ();
    };


  };

done_testing;
