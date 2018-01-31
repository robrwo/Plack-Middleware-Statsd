package MockStatsd;

use strict;
use warnings;

use Sub::Util 1.40 qw/ set_subname /;

sub new {
    my $class = shift;
    my $self  = [];
    bless $self, $class;
}

foreach my $name (qw/ increment decrement update timing_ms set_add /) {
    no strict 'refs';
    my $class = __PACKAGE__;
    *{"${class}::${name}"} = set_subname $name => sub {
        my $self = shift;
        push @{$self}, [ $name, @_ ];
    };
}

sub flush {
    my $self = shift;
    ( splice @{$self}, 0 );
}

1;
