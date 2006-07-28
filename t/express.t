#!/usr/bin/perl -w

# $Id: express.t 3074 2006-07-26 20:22:04Z theory $

use strict;
use Test::More tests => 18;

##############################################################################
# Test basic functionality.
TESTPKG: {
    package My::Test;
    use Test::More;
    BEGIN {
        use_ok 'Object::Relation' or die;
    }

    BEGIN {
        ok meta(   test => () ), 'Create class';
        ok has(    foo  => () ), 'Create "foo" attribute';
        ok build, 'Build class';;

        ok !defined &meta,   'meta should no longer be defined';
        ok !defined &ctor,   'ctor should no longer be defined';
        ok !defined &has,    'has should no longer be defined';
        ok !defined &method, 'method should no longer be defined';
        ok !defined &build,  'build should no longer be defined';
    }
}

ok my $meta = +My::Test->my_class, 'Get the Test meta object';
isa_ok $meta, 'Object::Relation::Meta::Class', 'it';
isa_ok $meta, 'Class::Meta::Class', 'it';
ok my $attr = $meta->attributes('foo'), 'Get "foo" attribute';
isa_ok $attr, 'Object::Relation::Meta::Attribute', 'it';
is $attr->type, 'string', 'Its type should be "string"';

ok my $obj = My::Test->new, 'Construct My::Test object';
isa_ok $obj, 'My::Test', 'it';
isa_ok $obj, 'Object::Relation::Base', 'it';
