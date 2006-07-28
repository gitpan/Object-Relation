#!/usr/bin/perl -w

# $Id: setup.pl 3074 2006-07-26 20:22:04Z theory $

use strict;
use warnings;
use aliased 'Object::Relation::Setup';
use Test::More;
use aliased 'Test::MockModule';

my $mock = MockModule->new(Setup);
$mock->mock(notify => sub { shift; diag @_ }) if $ENV{TEST_VERBOSE};

my $setup = Setup->new({
    verbose => $ENV{TEST_VERBOSE},
    @ARGV
});

$setup->class_dirs('t/sample/lib');
$setup->setup;
