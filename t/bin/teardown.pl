#!/usr/bin/perl -w

# $Id: teardown.pl 3074 2006-07-26 20:22:04Z theory $

use strict;
use warnings;
use Object::Relation::Setup;

my $setup = Object::Relation::Setup->new({ @ARGV });
$setup->teardown;
