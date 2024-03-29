#!/usr/bin/perl -w

# $Id: pod_coverage.t 3074 2006-07-26 20:22:04Z theory $

use strict;
use Test::More;
use Class::Std;   # Avoid warnings;
use Class::Trait; # Avoid warnings;

eval "use Test::Pod::Coverage 0.08";
plan skip_all => "Test::Pod::Coverage required for testing POD coverage" if $@;

my $aliased = qr/^[[:upper:]][[:alpha:]]*$/;
my @modules =  Test::Pod::Coverage::all_modules();
plan tests => scalar @modules;

foreach my $module (@modules) {
    pod_coverage_ok( $module, { trustme => [ $aliased ] } );
}
