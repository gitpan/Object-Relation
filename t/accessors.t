#!/usr/bin/perl -w

# $Id: accessors.t 3074 2006-07-26 20:22:04Z theory $

use strict;
use warnings;
use Test::More tests => 118;
#use Test::More 'no_plan';
use Test::NoWarnings; # Adds an extra test.
use Object::Relation::DataType::State qw(:all);
use Object::Relation::DataType::DateTime;

package Object::Relation::TestAccessors;
use base 'Object::Relation::Base';
use strict;
use Object::Relation::DataType::State qw(:all);

BEGIN {
    Test::More->import;
    # We need to load Object::Relation first, or else things just won't work!
    use_ok('Object::Relation::Base') or die;
    use_ok('Object::Relation::Meta') or die;
}

BEGIN {
    ok( my $cm = Object::Relation::Meta->new(
        key     => 'accessors',
        name    => 'Testing Accessors',
    ), "Create new CM object" );

    ok( $cm->add_constructor(name => 'new'), "Create new() constructor" );

    # Add a READ-only attribute.
    ok( $cm->add_attribute( name     => 'ro',
                            view     => Class::Meta::PUBLIC,
                            type     => 'whole',
                            required => 1,
                            default  => 1,
                            authz    => Class::Meta::READ,
                          ),
        "Add read-only attribute" );

    # Add a READWRITE attribute.
    ok( $cm->add_attribute( name     => 'rw',
                            view     => Class::Meta::PUBLIC,
                            type     => 'whole',
                            required => 1,
                            default  => 3,
                          ),
        "Add READWRITE attribute" );

    # Add a data type with no validation checks.
    ok( Class::Meta::Type->add(
        key     => "nocheck",
        name    => 'nocheck',
        builder => 'Object::Relation::Meta::AccessorBuilder',
    ), "Create nocheck data type" );

    # Add a nocheck attribute.
    ok( $cm->add_attribute( name     => 'nc',
                            view     => Class::Meta::PUBLIC,
                            type     => 'nocheck',
                            default  => 'foo',
                          ),
        "Add nocheck attribute" );
    # Add a READ-only class attribute.
    ok( $cm->add_attribute( name     => 'cro',
                            context  => Class::Meta::CLASS,
                            view     => Class::Meta::PUBLIC,
                            type     => 'whole',
                            required => 1,
                            default  => 1,
                            authz    => Class::Meta::READ,
                          ),
        "Add read-only attribute" );

    # Add a READWRITE attribute.
    ok( $cm->add_attribute( name     => 'crw',
                            context  => Class::Meta::CLASS,
                            view     => Class::Meta::PUBLIC,
                            type     => 'whole',
                            required => 1,
                            default  => 3,
                          ),
        "Add READWRITE attribute" );

    # Add a READWRITE datetime attribute, so we can test the raw accessor.
    ok( $cm->add_attribute( name     => 'date',
                            context  => Class::Meta::OBJECT,
                            view     => Class::Meta::PUBLIC,
                            type     => 'datetime',
                            required => 1,
                          ),
        "Add READWRITE attribute" );

    # Add a nocheck class attribute.
    ok( $cm->add_attribute( name     => 'cnc',
                            context  => Class::Meta::CLASS,
                            view     => Class::Meta::PUBLIC,
                            type     => 'nocheck',
                            default  => 'whee',
                          ),
        "Add nocheck attribute" );


    ok( $cm->build, "Build class" );
}

##############################################################################
# Do the tests.
##############################################################################
package main;
# Instantiate an object and test its accessors.
ok( my $t = Object::Relation::TestAccessors->new,
    'Object::Relation::TestAccessors->new');
ok( my $class = $t->my_class, "Get class object" );

# Try the read-only attribute.
is( $t->ro, 1, "Check ro" );
eval { $t->get_ro };
ok( $@, "Cannot use affordance accessor" );
eval { $t->ro(2) };
ok( $@, "Cannot set ro attribute" );

ok( my $attr = $class->attributes('ro'), "Get ro attribute" );
is( $attr->get($t), 1, "Check ro via attribute object" );
is( $attr->raw($t), 1, "Check ro raw value");
eval { $attr->set($t, 2) };
ok( $@, "Cannot set ro attribute via object" );
eval { $attr->bake($t, 2) };
ok( $@, "Cannot bake ro attribute via object" );

# Try the read/write attribute.
is( $t->rw, 3, "Check rw" );
eval { $t->get_rw };
ok( $@, "Cannot get_rw" );
is( $t->rw(2), $t, "Set rw to 2" );
is( $t->rw, 2, "Check rw for 2" );
eval { $t->set_rw(3) };
ok( $@, "Cannot set_rw" );
ok( $attr = $class->attributes('rw'), "Get rw attribute" );
is( $attr->get($t), 2, "Check rw via attribute object" );
is( $attr->raw($t), 2, "Check rw raw value");
is( $attr->set($t, 3), $t, "Set rw via attribute object" );
is( $attr->get($t), 3, "Check rw via attribute object for new value" );
is( $attr->raw($t), 3, "Check rw raw value for the new value");
is( $attr->bake($t, 4), $t, "Set rw via attribute object bake method" );
is( $attr->get($t), 4, "Check rw via attribute object for new value" );
is( $attr->raw($t), 4, "Check rw raw value for the new value");

# Try nocheck attribute.
is( $t->nc, 'foo', "Check nocheck" );
eval { $t->get_nc };
ok( $@, "Cannot get_nc" );
is( $t->nc('bar'), $t, "Set nocheck" );
is( $t->nc, 'bar', "Check new nocheck value" );
eval { $t->set_nc('bat') };
ok( $@, "Cannot set_nc" );
ok( $attr = $class->attributes('nc'), "Get nc attribute" );
is( $attr->get($t), 'bar', "Check nc via attribute object" );
is( $attr->raw($t), 'bar', "Check nc raw value");
is( $attr->set($t, 'bif'), $t, "Set nc via attribute object" );
is( $attr->get($t), 'bif', "Check nc via attribute object for new value" );
is( $attr->raw($t), 'bif', "Check nc raw value for the new value");
is( $attr->bake($t, 'bam!'), $t, "Set nc via attribute object" );
is( $attr->get($t), 'bam!', "Check nc via attribute object for new value" );
is( $attr->raw($t), 'bam!', "Check nc raw value for the new value");

# Try the read-only class attribute.
is( Object::Relation::TestAccessors->cro, 1, "Check cro" );
eval {Object::Relation::TestAccessors->get_cro };
ok( $@, "Cannot get_cro" );
is( $t->cro, 1, "Check cro via object" );
eval { $t->get_cro };
ok( $@, "Cannot get_cro via object" );
eval { Object::Relation::TestAccessors->cro(2) };
ok( $@, "Cannot set cro attribute" );
ok( $attr = $class->attributes('cro'), "Get cro attribute" );
is( $attr->get('Object::Relation::TestAccessors'), 1,
 "Check cro via attribute object" );
is( $attr->raw('Object::Relation::TestAccessors'), 1, "Check cro raw value");
eval { $attr->set('Object::Relation::TestAccessors', 'fan') };
ok( $@, "Cannot set cro attribute via attribute" );
eval { $attr->bake('Object::Relation::TestAccessors', 'fan') };
ok( $@, "Cannot bake cro attribute via attribute" );

# Try the read/write class attribute.
is( Object::Relation::TestAccessors->crw, 3, "Check crw" );
eval {Object::Relation::TestAccessors->get_crw };
ok( $@, "Cannot get_crw" );
ok( Object::Relation::TestAccessors->crw(2), "Set crw to 2" );
is( Object::Relation::TestAccessors->crw, 2, "Check crw for 2" );
eval { Object::Relation::TestAccessors->set_crw(3) };
ok( $@, "Cannot set_crw" );
is( $t->crw, 2, "Check crw for 2 via object" );
eval { $t->get_crw };
ok( $@, "Cannot get_crw via object" );
ok( $attr = $class->attributes('crw'), "Get crw attribute" );
is( $attr->get('Object::Relation::TestAccessors'), 2,
 "Check crw via attribute object" );
is( $attr->raw('Object::Relation::TestAccessors'), 2, "Check crw raw value");
ok( $attr->set('Object::Relation::TestAccessors', 4),
    "Set crw via attribute object" );
is( $attr->get('Object::Relation::TestAccessors'), 4,
    "Check crw via attribute object for new value" );
is( $attr->raw('Object::Relation::TestAccessors'), 4,
    "Check crw raw value for new value");
is( $attr->get($t), 4,
    "Check crw via attribute object for new value via object" );
is( $attr->raw($t), 4,
    "Check crw raw value via attribute object for new value");

# Try nocheck class attribute.
is( Object::Relation::TestAccessors->cnc, 'whee', "Check class nocheck" );
eval { Object::Relation::TestAccessors->get_cnc };
ok( $@, "Cannot get_cnc" );
ok( Object::Relation::TestAccessors->cnc('fun'), "Set class nocheck" );
is( Object::Relation::TestAccessors->cnc, 'fun', "Check new class nocheck value" );
eval { Object::Relation::TestAccessors->set_cnc('fug') };
ok( $@, "Cannot set_cnc" );
is( $t->cnc, 'fun', "Check new class nocheck value via object" );
eval { $t->get_cnc };
ok( $@, "Cannot get_cnc via object" );
ok( $attr = $class->attributes('cnc'), "Get cnc attribute" );
is( $attr->get('Object::Relation::TestAccessors'), 'fun',
 "Check cnc via attribute object" );
is( $attr->raw('Object::Relation::TestAccessors'), 'fun',
 "Check cnc raw value via attribute object" );
ok( $attr->set('Object::Relation::TestAccessors', 'fan'),
    "Set cnc via attribute object" );
is( $attr->get('Object::Relation::TestAccessors'), 'fan',
    "Check cnc via attribute object for new value" );
is( $attr->raw('Object::Relation::TestAccessors'), 'fan',
 "Check cnc raw value via attribute object for new value" );
is( $attr->get($t), 'fan',
    "Check cnc via attribute object for new value via object" );
is( $attr->raw($t), 'fan',
 "Check cnc raw value via attribute object for new value via object" );

ok( $attr->bake('Object::Relation::TestAccessors', 'Wheeze Chiz'),
    "Set cnc via attribute object" );
is( $attr->get('Object::Relation::TestAccessors'), 'Wheeze Chiz',
    "Check cnc via attribute object for new value" );
is( $attr->raw('Object::Relation::TestAccessors'), 'Wheeze Chiz',
 "Check cnc raw value via attribute object for new value" );
is( $attr->get($t), 'Wheeze Chiz',
    "Check cnc via attribute object for new value via object" );
is( $attr->raw($t), 'Wheeze Chiz',
 "Check cnc raw value via attribute object for new value via object" );

# Now test the state attribute, especially for its raw value, which will
# be different. overload::StrVal($k2)
my $active_str = overload::StrVal(ACTIVE);
my $inactive_str = overload::StrVal(INACTIVE);

is( overload::StrVal($t->state), $active_str,
    "Check state for ACTIVE object" );
is( $t->state(INACTIVE), $t, "Set state to INACTIVE" );
is( overload::StrVal($t->state), $inactive_str,
    "Check state for INACTIVE object" );
ok( $attr = $class->attributes('state'), "Get state attribute" );
is( overload::StrVal($attr->get($t)), $inactive_str,
    "Check state via attribute object" );
is( $attr->raw($t), 0, "Check state raw value");
is( $attr->set($t, ACTIVE), $t, "Set state via attribute object" );
is( overload::StrVal($attr->get($t)), $active_str,
    "Check state via attribute object for new value" );
is( $attr->raw($t), 1, "Check state raw value for the new value");
is( $attr->bake($t, 0), $t, "Thaw state via attribute object" );
is( overload::StrVal($attr->get($t)), $inactive_str,
    "Check state via attribute object for new value" );
is( $attr->raw($t), 0, "Check state raw value for the new value");

# test the datetime attribute to ensure it works.
my $date = Object::Relation::DataType::DateTime->bake('1964-10-16T16:12:47.0');
is $t->date($date), $t, 'Set date';
is $t->date->raw, '1964-10-16T16:12:47', 'Check date string is correct';
ok $attr = $class->attributes('date'), 'Get date attribute';
is $attr->get($t)->raw, '1964-10-16T16:12:47', 'Check date returns microseconds';
is $attr->raw($t), '1964-10-16T16:12:47', 'Check attr->raw date does not return microseconds';
$date = Object::Relation::DataType::DateTime->bake('2005-10-16T16:12:47.0');
is $attr->set($t, $date), $t, 'Set date via attribute object';
is $attr->raw($t), '2005-10-16T16:12:47', 'Check date returns new value';
is $attr->bake($t, '2000-01-01T00:00:00'), $t, 'Thaw date via attribute object';
is $attr->raw($t), '2000-01-01T00:00:00', 'And make sure it returns the right value';
