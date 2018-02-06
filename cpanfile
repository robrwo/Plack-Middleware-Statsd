requires "POSIX" => "0";
requires "Plack::Middleware" => "0";
requires "Plack::Util" => "0";
requires "Plack::Util::Accessor" => "0";
requires "Time::HiRes" => "0";
requires "Try::Tiny" => "0";
requires "parent" => "0";
requires "perl" => "v5.10.0";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "File::Spec" => "0";
  requires "HTTP::Request::Common" => "0";
  requires "Module::Metadata" => "0";
  requires "Plack::Builder" => "0";
  requires "Plack::Middleware::ContentLength" => "0";
  requires "Plack::Middleware::Head" => "0";
  requires "Plack::Test" => "0";
  requires "Sub::Util" => "1.40";
  requires "Test::Differences" => "0";
  requires "Test::More" => "0";
  requires "Test::Most" => "0";
  requires "lib" => "0";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
};

on 'develop' => sub {
  requires "Pod::Coverage::TrustPod" => "0";
  requires "Test::EOF" => "0";
  requires "Test::EOL" => "0";
  requires "Test::Kwalitee" => "1.21";
  requires "Test::MinimumVersion" => "0";
  requires "Test::More" => "0.88";
  requires "Test::NoTabs" => "0";
  requires "Test::Perl::Critic" => "0";
  requires "Test::Pod" => "1.41";
  requires "Test::Pod::Coverage" => "1.08";
  requires "Test::Portability::Files" => "0";
  requires "Test::TrailingSpace" => "0.0203";
};
