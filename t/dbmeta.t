#!/usr/bin/perl -w

# $Id: dbmeta.t 3074 2006-07-26 20:22:04Z theory $

use strict;
use Test::More tests => 41;
use Test::NoWarnings; # Adds an extra test.

package MyTestThingy;

BEGIN {
    Test::More->import;
    use_ok('Object::Relation::Meta', ':with_dbstore_api') or die;
    use_ok('Object::Relation::Language') or die;
    use_ok('Object::Relation::Language::en_us') or die;
    use_ok('Object::Relation::Meta::Class') or die;
    use_ok('Object::Relation::Meta::Attribute') or die;
    use_ok('Object::Relation::Meta::AccessorBuilder') or die;
    use_ok('Object::Relation::Meta::Widget') or die;
}

BEGIN {
    is( Object::Relation::Meta->class_class, 'Object::Relation::Meta::Class',
        "The class class should be 'Object::Relation::Meta::Class'");
    is( Object::Relation::Meta->attribute_class, 'Object::Relation::Meta::Attribute',
        "The attribute class should be 'Object::Relation::Meta::Attribute'");

    ok my $km = Object::Relation::Meta->new(
        key         => 'thingy',
        name        => 'Thingy',
        plural_name => 'Thingies',
    ), "Create TestThingy class";

    ok $km->add_attribute(
        name          => 'foo',
        type          => 'string',
        label         => 'Foo',
        indexed       => 1,
        on_delete     => 'CASCADE',
        store_default => 'ick',
        widget_meta   => Object::Relation::Meta::Widget->new(
            type => 'text',
            tip  => 'Object::Relation Base Class',
        )
    ), "Add foo attribute";

    ok $km->build, "Build TestThingy class";
}

package MyTestFooey;

BEGIN {
    Test::More->import;
}

BEGIN {
    ok my $km = Object::Relation::Meta->new(
        key         => 'fooey',
        name        => 'Fooey',
        plural_name => 'Fooies',
    ), "Create TestFooey class";

    ok $km->add_attribute(
        name          => 'thingy',
        type          => 'thingy',
        label         => 'Thingy',
        indexed       => 1,
    ), "Add thingy attribute";

    ok $km->build, "Build TestThingy class";
}

# Add new strings to the lexicon.
Object::Relation::Language::en->add_to_lexicon(
  'Thingy'   => 'Thingy',
  'Thingies' => 'Thingies',
  'Foo'      => 'Foo',
  'Fooey'    => 'Fooey',
  'Fooies'    => 'Fooies',
);

package main;
use aliased 'Test::MockModule';

ok my $class = MyTestThingy->my_class, "Get meta class object";
isa_ok $class, 'Object::Relation::Meta::Class';
isa_ok $class, 'Class::Meta::Class';

is $class->key, 'thingy', 'Check key';
is $class->package, 'MyTestThingy', 'Check package';
is $class->name, 'Thingy', 'Check name';
is $class->plural_name, 'Thingies', 'Check plural name';

ok my $attr = $class->attributes('foo'), "Get foo attribute";
isa_ok $attr, 'Object::Relation::Meta::Attribute';
isa_ok $attr, 'Class::Meta::Attribute';
is $attr->name, 'foo', "Check attr name";
is $attr->type, 'string', "Check attr type";
is $attr->label, 'Foo', "Check attr label";
is $attr->indexed, 1, "Indexed should be true";

is $attr->_column, $attr->name,
  'The _column() method should return the column name';
is $attr->_view_column, $attr->name,
  'The _view_column() method should return the view column name';

# Make sure they work when the attribute references another attribute.
my $mock = MockModule->new('Object::Relation::Meta::Attribute');
$mock->mock(references => 1 );
is $attr->_column, $attr->name . '_id',
  'The _column() method should return the reference column name';
is $attr->_view_column, $attr->name . '__id',
  'The _view_column() method should return the reference view column name';
$mock->unmock_all;

ok my $wm = $attr->widget_meta, "Get widget meta object";
isa_ok $wm, 'Object::Relation::Meta::Widget';
isa_ok $wm, 'Widget::Meta';
is $wm->tip, 'Object::Relation Base Class', "Check tip";

ok my $fclass = MyTestFooey->my_class, "Get Fooey class object";
ok $attr = $fclass->attributes('thingy'), "Get thingy attribute";
is $attr->raw({ thingy => bless { id => 10 }, $class->package }), 10,
  "We should get an ID from raw()";
