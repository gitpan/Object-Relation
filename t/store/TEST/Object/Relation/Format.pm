package TEST::Object::Relation::Format;

# $Id: Format.pm 3074 2006-07-26 20:22:04Z theory $

use strict;
use warnings;

use base 'TEST::Class::Object::Relation';

use Test::JSON;
use Test::More;
use Test::Exception;

use Class::Trait qw(
  TEST::Object::Traits::Store
  TEST::Object::Traits::SampleObjects
);

use aliased 'Test::MockModule';
use aliased 'Object::Relation::Handle' => 'Store', ':all';
use aliased 'TestApp::Simple::One';
use aliased 'TestApp::Simple::Two';   # contains a TestApp::Simple::One object

use constant FORMAT => 'Object::Relation::Format';
use constant JSON   => FORMAT . '::JSON';

__PACKAGE__->SKIP_CLASS(
    $ENV{OBJ_REL_CLASS}
    ? 0
    : 'Not testing live data store',
) if caller;    # so I can run the tests directly from vim
__PACKAGE__->runtests unless caller;

sub setup : Test(setup) {
    my $test = shift;
    $test->mock_dbh;
    $test->create_test_objects;
}

sub teardown : Test(teardown) {
    my $test = shift;
    $test->unmock_dbh;
}

sub content_type : Test(3) {
    my $test = shift;
    my $formatter = Object::Relation::Format->new( { format => 'xml' } );
    can_ok $formatter, 'content_type';
    is $formatter->content_type, 'text/xml',
      '... and it should return the correct content type';

    $formatter = Object::Relation::Format->new( { format => 'json' } );
    is $formatter->content_type, 'text/plain',
      '... and it should return the correct content type';
}

sub constructor : Test(5) {
    my $test = shift;
    can_ok FORMAT, 'new';
    throws_ok { FORMAT->new } 'Object::Relation::Exception::Fatal',
      '... and trying to create a new formatter without a format should fail';

    throws_ok { FORMAT->new( { format => 'no_such_format' } ) }
      'Object::Relation::Exception::Fatal::InvalidClass',
      '... as should trying to create a new formatter with an invalid class';

    ok my $formatter = FORMAT->new( { format => 'json' } ),
      '... and calling it should succeed';

    isa_ok $formatter, JSON, '... and the object it returns';
}

sub interface : Test(8) {
    my $test      = shift;
    my $formatter = bless {}, FORMAT;

    can_ok $formatter, 'ref_to_format';
    throws_ok { $formatter->ref_to_format }
      'Object::Relation::Exception::Fatal::Unimplemented',
      '... and calling it should fail';

    can_ok $formatter, 'ref_to_format';
    throws_ok { $formatter->ref_to_format }
      'Object::Relation::Exception::Fatal::Unimplemented',
      '... and calling it should fail';

    can_ok $formatter, 'serialize';
    throws_ok { $formatter->serialize } 'Object::Relation::Exception::Fatal',
      '... and calling it should fail';

    can_ok $formatter, 'deserialize';
    throws_ok { $formatter->deserialize } 'Object::Relation::Exception::Fatal',
      '... and calling it should fail';
}

sub to_and_from_hashref : Test(7) {
    my $test      = shift;
    my $formatter = bless {}, FORMAT;

    my ( $foo, $bar, $baz ) = $test->test_objects;
    can_ok $formatter, '_obj_to_hashref';
    ok my $hashref = $formatter->_obj_to_hashref($foo),
      '... and calling it with a valid Object::Relation object should succeed';
    my %expected = (
        bool        => 1,
        Key         => 'one',
        name        => 'foo',
        description => undef,
        uuid        => $foo->uuid,
        state       => 1
    );
    is_deeply $hashref, \%expected,
      '... and it should return the correct hashref';

    can_ok $formatter, '_hashref_to_obj';
    ok my $object = $formatter->_hashref_to_obj($hashref),
      '... and calling it should succeed';
    isa_ok $object, ref $foo, '... and the object it returns';
    $object->{id} = $foo->{id};
    $test->force_inflation($object);
    is_deeply $object, $foo, '... and it should be the correct object';
}

sub expand_ref : Test(9) {
    my $test = shift;

    my $formatter = bless {}, FORMAT;

    my ( $foo, $bar, $baz ) = $test->test_objects;
    can_ok $formatter, 'expand_ref';

    ok my $result = $formatter->expand_ref('Ovid'),
      '... and calling it without a reference should succeed';
    is $result, 'Ovid', '... and return whatever we passed in';

    ok my $ref = $formatter->expand_ref($foo),
      '... and calling it with a valid Object::Relation object should succeed';
    my %expected = (
        bool        => 1,
        Key         => 'one',
        name        => 'foo',
        description => undef,
        uuid        => $foo->uuid,
        state       => 1
    );
    is_deeply $ref, \%expected, '... and it should return the correct ref';

    my @array = ( $foo, $bar, $baz );
    ok $ref = $formatter->expand_ref( \@array ),
      '... and it should be able to properly expand array refs';
    my @expected = (
        {   'bool'        => 1,
            'Key'         => 'one',
            'name'        => 'foo',
            'description' => undef,
            'uuid'        => $foo->uuid,
            'state'       => 1
        },
        {   'bool'        => 1,
            'Key'         => 'one',
            'name'        => 'bar',
            'description' => undef,
            'uuid'        => $bar->uuid,
            'state'       => 1
        },
        {   'bool'        => 1,
            'Key'         => 'one',
            'name'        => 'snorfleglitz',
            'description' => undef,
            'uuid'        => $baz->uuid,
            'state'       => 1
        }
    );
    is_deeply \@array, \@expected, '... and we should get the correct values';

    my %hash = ( foo => $foo, bar => $bar, baz => $baz );
    ok $ref = $formatter->expand_ref( \%hash ),
      '... and it should be able to properly expand hash refs';

    %expected = (
        foo => {
            'bool'        => 1,
            'Key'         => 'one',
            'name'        => 'foo',
            'description' => undef,
            'uuid'        => $foo->uuid,
            'state'       => 1
        },
        bar => {
            'bool'        => 1,
            'Key'         => 'one',
            'name'        => 'bar',
            'description' => undef,
            'uuid'        => $bar->uuid,
            'state'       => 1
        },
        baz => {
            'bool'        => 1,
            'Key'         => 'one',
            'name'        => 'snorfleglitz',
            'description' => undef,
            'uuid'        => $baz->uuid,
            'state'       => 1
        }
    );
    is_deeply $ref, \%expected, '... and we should get the correct values';
}

1;
