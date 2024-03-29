package TEST::Object::Relation::Handle;

# $Id: Handle.pm 3074 2006-07-26 20:22:04Z theory $

use strict;
use warnings;

use base 'TEST::Object::Relation';
use Test::More;
use Test::Exception;
use Encode qw(is_utf8);

use Class::Trait qw(
    TEST::Object::Traits::Store
    TEST::Object::Traits::SampleObjects
);

use aliased 'Object::Relation::Handle' => 'Store', ':all';

use aliased 'Object::Relation::DataType::DateTime';
use aliased 'Object::Relation::DataType::DateTime::Incomplete';
use aliased 'Object::Relation::Iterator';
use aliased 'Object::Relation::DataType::State';

use aliased 'TestApp::Simple::One';
use aliased 'TestApp::Simple::Two';    # contains a TestApp::Simple::One object
use aliased 'TestApp::Yello';

__PACKAGE__->SKIP_CLASS(
    $ENV{OBJ_REL_CLASS}
    ? 0
    : 'Not testing live data store',
) if caller;    # so I can run the tests directly from vim
__PACKAGE__->runtests unless caller;

sub purge : Test(9) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;

    my ( $foo, $bar, $baz ) = $test->test_objects;
    is $test->_num_recs('one'), 3,
      'We should start with 3 "one" objects in the data store';
    can_ok $bar, 'purge';
    ok $bar->purge, '... and calling it should succeed';
    $bar->save;
    is $test->_num_recs('one'), 2,
      '... and we should have one fewer "one" objects in the data store';

    #
    # Purging unsaved objects
    #
    my $new_object = One->new;
    ok $new_object->purge->save,
      'Purging an object not in the data store should succeed';
    is $test->_num_recs('one'), 2,
      '... should not change the number of objects in the store';

    #
    # purging contained objects
    #
    my $two_object = Two->new;
    $two_object->name('two_object');
    $two_object->one($foo);
    $two_object->save;
    is $test->_num_recs('two'), 1,
      'We should have the correct number of "two" objects in the data store';
    $two_object->purge->save;
    is $test->_num_recs('two'), 0,
      '... and it should be reduced by one after a purge and save';

    TODO: {
        local $TODO = 'Cascading delete for "has" relationship not implemented';
        is $test->_num_recs('one'), 1,
        '... and its contained object should be deleted, too';
    }
}

sub save : Test(10) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $one = One->new;
    $one->name('Ovid');
    $one->description('test class');

    my $store = Store->new;
    can_ok $store, 'save';
    my $dbh    = $test->dbh;
    my $result =
      $dbh->selectrow_hashref(
        'SELECT id, uuid, name, description, state, bool FROM one');
    ok !$result, 'We should start with a fresh database';
    ok $one->save, 'and saving an object should be successful';
    $result =
      $dbh->selectrow_hashref(
        'SELECT id, uuid, name, description, state, bool FROM one');
    $result->{state} = State->new( $result->{state} );

    # XXX this works, but it might be a bit fragile
    is_deeply $one, $result,
      'and the data should match what we pull from the database';
    is $test->_num_recs('one'), 1, 'and we should have one record in the view';

    my $two = One->new;
    $two->name('bob');
    $two->description('some description');
    $two->save;
    is $test->_num_recs('one'), 2, 'and we should have two records in the view';
    $result =
      $dbh->selectrow_hashref(
'SELECT id, uuid, name, description, state, bool FROM one WHERE name = \'bob\''
      );
    $result->{state} = State->new( $result->{state} );
    is_deeply $two, $result,
      'and the data should match what we pull from the database';
    $two->name('beelzebub');
    $two->save;
    my $uuid = $dbh->quote( $two->uuid );
    $result =
      $dbh->selectrow_hashref(
"SELECT id, uuid, name, description, state, bool FROM one WHERE uuid = $uuid"
      );
    $result->{state} = State->new( $result->{state} );
    is_deeply $two, $result, 'and we should be able to update data';
    is $result->{name}, 'beelzebub', 'and return the correct results';
    is $test->_num_recs('one'), 2, 'without the number of records changing';
}

sub search : Test(19) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'query';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    foreach ( $foo, $bar, $baz ) {
        $_->name( $_->name . chr(0x100) );
        $_->save;
    }
    my $class = $foo->my_class;
    ok my $iterator = $store->query($class),
      'A search with only a class should succeed';
    my @results = $test->_all_items($iterator);
    is @results, 3, 'returning all instances in the class';

    foreach my $result (@results) {
        ok is_utf8( $result->name ),
          '... and the data should be unicode strings';
    }

    ok $iterator = $store->query( $class, name => $foo->name ),
      'and an exact match should succeed';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and the first item should match the correct object';
    ok !$test->force_inflation( $iterator->next ),
      'and there should be the correct number of objects';

    ok $iterator = $store->query( $class, name => $foo->name ),
      'We should also be able to call search as a class method';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and it should return the same results as an instance method';
    ok !$test->force_inflation( $iterator->next ),
      'and there should be the correct number of objects';

    ok $iterator = $store->query( $class, name => ucfirst $foo->name ),
      'Case-insensitive searches should work';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and they should return data even if the case does not match';

    $iterator =
      $store->query( $class, name => $foo->name, description => 'asdf' );
    ok !$test->force_inflation( $iterator->next ),
      'but searching for non-existent values will return no results';
    $foo->description('asdf');
    $foo->save;
    $iterator =
      $store->query( $class, name => $foo->name, description => 'asdf' );
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      '... and it should be the correct results';
}

sub search_from_key : Test(10) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'query';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    foreach ( $foo, $bar, $baz ) {
        $_->name( $_->name . chr(0x100) );
        $_->save;
    }
    my $key = $foo->my_class->key;
    ok my $iterator = $store->query($key),
      'A search with only a class should succeed';
    my @results = $test->_all_items($iterator);
    is @results, 3, 'returning all instances in the class';

    foreach my $result (@results) {
        ok is_utf8( $result->name ),
          '... and the data should be unicode strings';
    }

    ok $iterator = $store->query( $key, name => $foo->name ),
      'and an exact match should succeed';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and the first item should match the correct object';
    ok !$test->force_inflation( $iterator->next ),
      'and there should be the correct number of objects';
}

sub string_search : Test(19) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'query';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    foreach ( $foo, $bar, $baz ) {
        $_->name( $_->name . chr(0x100) );
        $_->save;
    }
    my $class = $foo->my_class;
    ok my $iterator = $store->query( $class, STRING => '' ),
      'A search with only a class should succeed';
    my @results = $test->_all_items($iterator);
    is @results, 3, 'returning all instances in the class';

    foreach my $result (@results) {
        ok is_utf8( $result->name ),
          '... and the data should be unicode strings';
    }

    ok $iterator =
      $store->query( $class, STRING => "name => '@{[$foo->name]}'" ),
      'and an exact match should succeed';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and the first item should match the correct object';
    ok !$test->force_inflation( $iterator->next ),
      'and there should be the correct number of objects';

    ok $iterator =
      $store->query( $class, STRING => "name => '@{[$foo->name]}'" ),
      'We should also be able to call search as a class method';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and it should return the same results as an instance method';
    ok !$test->force_inflation( $iterator->next ),
      'and there should be the correct number of objects';

    ok $iterator =
      $store->query( $class, STRING => "name => '@{[ucfirst $foo->name]}'" ),
      'Case-insensitive searches should work';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and they should return data even if the case does not match';

    $iterator =
      $store->query( $class,
        STRING => "name => '@{[$foo->name]}', description => 'asdf'" );
    ok !$test->force_inflation( $iterator->next ),
      'but searching for non-existent values will return no results';
    $foo->description('asdf');
    $foo->save;
    $iterator =
      $store->query( $class,
        STRING => "name => '@{[$foo->name]}', description => 'asdf'" );
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      '... and it should be the correct results';
}

sub squery_string_search : Test(19) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'squery';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    foreach ( $foo, $bar, $baz ) {
        $_->name( $_->name . chr(0x100) );
        $_->save;
    }
    my $class = $foo->my_class;
    ok my $iterator = $store->squery($class),
      'A search with only a class should succeed';
    my @results = $test->_all_items($iterator);
    is @results, 3, 'returning all instances in the class';

    foreach my $result (@results) {
        ok is_utf8( $result->name ),
          '... and the data should be unicode strings';
    }

    ok $iterator = $store->squery( $class, "name => '@{[$foo->name]}'" ),
      'and an exact match should succeed';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and the first item should match the correct object';
    ok !$test->force_inflation( $iterator->next ),
      'and there should be the correct number of objects';

    ok $iterator = $store->squery( $class, "name => '@{[$foo->name]}'" ),
      'We should also be able to call search as a class method';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and it should return the same results as an instance method';
    ok !$test->force_inflation( $iterator->next ),
      'and there should be the correct number of objects';

    ok $iterator =
      $store->squery( $class, "name => '@{[ucfirst $foo->name]}'" ),
      'Case-insensitive searches should work';
    isa_ok $iterator, Iterator, 'and the object it returns';
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      'and they should return data even if the case does not match';

    $iterator =
      $store->squery( $class,
        "name => '@{[$foo->name]}', description => 'asdf'" );
    ok !$test->force_inflation( $iterator->next ),
      'but searching for non-existent values will return no results';
    $foo->description('asdf');
    $foo->save;
    $iterator =
      $store->squery( $class,
        "name => '@{[$foo->name]}', description => 'asdf'" );
    is_deeply $test->force_inflation( $iterator->next ), $foo,
      '... and it should be the correct results';
}

sub unit_constructor : Test(6) {
    my $test = shift;
    ( my $class = ref $test ) =~ s/^TEST:://;
    can_ok $class => 'new';

    throws_ok { Object::Relation::Handle->new({ class => 'Bogus::Class'}) }
      'Object::Relation::Exception::Fatal::InvalidClass',
      '... and trying to load it with a bad class should throw an exception';

    ok my $store = $class->new;
    isa_ok $store, $class;
    isa_ok $store, 'Object::Relation::Handle';

    my $store2 = $class->new;
    isnt "$store", "$store2", '... and a singleton should not be returned';
}

sub search_subs_lex_correctly : Test(47) {
    can_ok Store, 'import';

    # comparison
    foreach my $sub (qw/LIKE GT LT GE LE NE MATCH/) {
        can_ok __PACKAGE__, $sub;
        no strict 'refs';
        my $result = [ $sub->(7)->() ];
        is_deeply $result, [ [ COMPARE => $sub ], [ VALUE => 7 ] ],
          '... and it should return and empty string, its name and args';
        $result = [ NOT( $sub->(7) )->() ];
        is_deeply $result,
          [ [ 'KEYWORD' => 'NOT' ], [ COMPARE => $sub ], [ VALUE => 7 ] ],
          '... and it should return the value passed to it, its  name and args';
    }

    # sorting
    foreach my $sub (qw/ASC DESC/) {
        can_ok __PACKAGE__, $sub;
        no strict 'refs';
        my $result = [ $sub->()->() ];
        is_deeply $result, [$sub], '... and it should return its name and args';
    }

    # logical
    foreach my $sub (qw/AND OR/) {
        can_ok __PACKAGE__, $sub;
        no strict 'refs';
        my $result = [ $sub->(qw/foo bar/)->() ];
        is_deeply $result, [ $sub, [qw/foo bar/] ],
          '... and it should return its name and an array ref of its arguments';
    }
    can_ok __PACKAGE__, 'EQ';
    my $eq = EQ 2;
    is_deeply [ $eq->() ], [ [ COMPARE => 'EQ' ], [ VALUE => 2 ] ],
      '... and a basic EQ should return the correct value';

    is_deeply [ ( EQ [ 2, 3 ] )->() ],
      [
        [ KEYWORD => 'BETWEEN' ],
        [ OP      => '[' ],
        [ VALUE   => 2 ],
        [ OP      => ',' ],
        [ VALUE   => 3 ],
        [ OP      => ']' ],
      ],
      '... and EQ should return BETWEEN if the value is an arrayref';

    is_deeply [ ( NOT EQ 2 )->() ],
      [ [ KEYWORD => 'NOT' ], [ COMPARE => 'EQ' ], [ VALUE => 2 ], ],
      '... EQ should negate itself if NOT is passed as an argument';

    is_deeply [ ( NOT EQ [ 2, 3 ] )->() ],
      [
        [ KEYWORD => 'NOT' ],
        [ KEYWORD => 'BETWEEN' ],
        [ OP      => '[' ],
        [ VALUE   => 2 ],
        [ OP      => ',' ],
        [ VALUE   => 3 ],
        [ OP      => ']' ],
      ],
      '... even if we are doing a BETWEEN search';

    can_ok __PACKAGE__, 'ANY';
    is_deeply [ ANY( 2, 3, 4 )->() ],
      [
        [ KEYWORD => 'ANY' ],
        [ OP      => '(' ],
        [ VALUE   => 2 ],
        [ OP      => ',' ],
        [ VALUE   => 3 ],
        [ OP      => ',' ],
        [ VALUE   => 4 ],
        [ OP      => ')' ],
      ],
      '... and a basic ANY should return the correct value';

    is_deeply [ ( NOT ANY( 2, 3, 4 ) )->() ], [
        [ KEYWORD => 'NOT' ],
        [ KEYWORD => 'ANY' ],
        [ OP      => '(' ],
        [ VALUE   => 2 ],
        [ OP      => ',' ],
        [ VALUE   => 3 ],
        [ OP      => ',' ],
        [ VALUE   => 4 ],
        [ OP      => ')' ],

      ],
      '... even if it is negated';
    can_ok __PACKAGE__, 'BETWEEN';
    throws_ok { ( BETWEEN [ 2, 3, 4 ] )->() }
      'Object::Relation::Exception::Fatal::Search',
'... and BETWEEN searches with other than two values should throw an exception';
    my $between = BETWEEN [ 2, 4 ];
    is_deeply [ $between->() ],
      [
        [ KEYWORD => 'BETWEEN' ],
        [ OP      => '[' ],
        [ VALUE   => 2 ],
        [ OP      => ',' ],
        [ VALUE   => 4 ],
        [ OP      => ']' ],
      ],
      '... and BETWEEN should return the correct value';
    is_deeply [ ( NOT $between)->() ],
      [
        [ KEYWORD => 'NOT' ],
        [ KEYWORD => 'BETWEEN' ],
        [ OP      => '[' ],
        [ VALUE   => 2 ],
        [ OP      => ',' ],
        [ VALUE   => 4 ],
        [ OP      => ']' ],
      ],
      '... even if it is negated';

    can_ok __PACKAGE__, 'NOT';
    my $not = NOT 'foo';
    is_deeply [ $not->() ], [ [ KEYWORD => 'NOT' ], [ VALUE => 'foo' ], ],
      '... NOT searches should negate their meaning and default to EQ';
    $not = NOT [ 'bar', 'baz' ];
    is_deeply [ $not->() ],
      [
        [ KEYWORD => 'NOT' ],
        [ OP      => '[' ],
        [ VALUE   => 'bar' ],
        [ OP      => ',' ],
        [ VALUE   => 'baz' ],
        [ OP      => ']' ],
      ],
      '... but should switch to BETWEEN if negating an array ref';
    $not = NOT BETWEEN [ 'bar', 'baz' ];
    is_deeply [ $not->() ],
      [
        [ KEYWORD => 'NOT' ],
        [ KEYWORD => 'BETWEEN' ],
        [ OP      => '[' ],
        [ VALUE   => 'bar' ],
        [ OP      => ',' ],
        [ VALUE   => 'baz' ],
        [ OP      => ']' ],
      ],
      '... and allow the BETWEEN to be explicitly stated';
    $not = NOT LIKE 'foo%';
    is_deeply [ $not->() ],
      [ [ KEYWORD => 'NOT' ], [ COMPARE => 'LIKE' ], [ VALUE => 'foo%' ], ],
      '... and otherwise should take an extra operator';
}

sub search_incomplete_date_boundaries : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;

    my $june17 = Two->new;
    $june17->name('june17');
    $june17->one->name('june17_one_name');
    $june17->date(
        DateTime->new(
            year  => 1968,
            month => 6,
            day   => 17
        )
    );
    my $june16 = Two->new;
    $june16->name('june16');
    $june16->one->name('june16_one_name');
    $june16->date(
        DateTime->new(
            year  => 1967,
            month => 06,
            day   => 16
        )
    );
    my $july16 = Two->new;
    $july16->name('july16');
    $july16->one->name('july16_one_name');
    $july16->date(
        DateTime->new(
            year  => 1967,
            month => 07,
            day   => 16
        )
    );
    my $store = Store->new;
    $_->save foreach $june17, $june16, $july16;
    my $class    = $june17->my_class;
    my $bad_date = Incomplete->new( month => 6, hour => 23 );

    throws_ok { $store->query( $class, date => GT $bad_date ) }
      'Object::Relation::Exception::Fatal::Unsupported',
      'Non-contiguous dates should throw an exception with GT/LT searches';

    my $bad_date1 = Incomplete->new( month => 7, hour => 22 );
    throws_ok { $store->query( $class, date => [ $bad_date => $bad_date1 ] ) }
      'Object::Relation::Exception::Fatal::Unsupported',
      'Non-contiguous dates should throw an exception with range searches';

    my ( $first, $second ) =
      ( Incomplete->new( month => 6 ), Incomplete->new( day => 3 ) );
    throws_ok { $store->query( $class, date => [ $first => $second ] ) }
      'Object::Relation::Exception::Fatal::Unsupported',
      'BETWEEN search dates without identically defined segments will die';

    my $date1 = Incomplete->new( month => 6, day => 17 );
    my $iterator = $store->query( $class, date => GE $date1 );
    my @results = $test->_all_items($iterator);
    is @results, 2, 'We should be able to search on incomplete dates';
    is_deeply \@results, [ $june17, $july16 ],
      '... and get the correct results';

    throws_ok { $store->query( $class, date => ANY( $date1, {} ) ) }
      'Object::Relation::Exception::Fatal::Search',
      'ANY searches with incomplete dates must have all types matching';
}

sub search_incomplete_dates : Test(25) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $theory = Two->new;
    $theory->name('David');
    $theory->one->name('david_one_name');
    $theory->date(
        DateTime->new(
            year  => 1968,
            month => 12,
            day   => 19
        )
    );
    my $ovid = Two->new;
    $ovid->name('Ovid');
    $ovid->one->name('ovid_one_name');
    $ovid->date(
        DateTime->new(
            year  => 1967,
            month => 06,
            day   => 20
        )
    );
    my $usa = Two->new;
    $usa->one->name('usa_one_name');
    $usa->name('USA');
    $usa->date(
        DateTime->new(
            year  => 1976,    # yeah, I know
            month => 7,
            day   => 4,
        )
    );
    my $lil = Two->new;
    $lil->one->name('Lil');
    $lil->name('Lil_one_name');
    $lil->date(
        DateTime->new(
            year  => 1976,
            month => 1,
            day   => 9,
        )
    );
    my $store = Store->new;
    $_->save foreach $theory, $ovid, $usa, $lil;

    my $class    = $ovid->my_class;
    my $june     = Incomplete->new( month => 6 );
    my $iterator = $store->query( $class, date => $june );
    my @results  = $test->_all_items($iterator);
    is @results, 1, 'We should be able to search on incomplete dates';
    is_deeply \@results, [$ovid], '... and get the correct results';

    my $bicentennial = Incomplete->new( year => 1976 );
    $iterator =
      $store->query( $class, date => $bicentennial, { order_by => 'date' } );
    @results = $test->_all_items($iterator);
    is @results, 2, '... even if we have multiple results';
    is_deeply \@results, [ $lil, $usa ],
      '... but they had better be the correct results';

    $bicentennial->set( day => 4 );
    $iterator =
      $store->query( $class, date => $bicentennial, { order_by => 'date' } );
    @results = $test->_all_items($iterator);
    is @results, 1, '... even if we have just a year and a day';
    is_deeply \@results, [$usa],
      '... but they had better be the correct results';

    my $bad_date = Incomplete->new( year => 1776 );
    $iterator = $store->query( $class, date => $bad_date );
    @results = $test->_all_items($iterator);
    ok !@results,
'... but searching in a non-existent date should fail, even if it is an incomplete date';

    $june = Incomplete->new(
        month => '06',
        day   => '16',
    );
    $iterator =
      $store->query( $class, date => GE $june, { order_by => 'date' } );
    @results = $test->_all_items($iterator);
    is @results, 3, 'Incomplete dates should recognize GE';
    is_deeply \@results, [ $ovid, $theory, $usa ],
      '... and get the correct results';

    $june = Incomplete->new( month => 6 );
    $iterator =
      $store->query( $class, date => GT $june, { order_by => 'date' } );
    @results = $test->_all_items($iterator);
    is @results, 2, 'Incomplete dates should recognize GT';
    is_deeply \@results, [ $theory, $usa ], '... and get the correct results';

    $june->set( day => 20 );
    $iterator =
      $store->query( $class, date => LE $june, { order_by => 'date' } );
    @results = $test->_all_items($iterator);
    is @results, 2, 'Incomplete dates should recognize LE';
    is_deeply \@results, [ $ovid, $lil ], '... and get the correct results';

    $iterator =
      $store->query( $class, date => LT $june, { order_by => 'date' } );
    @results = $test->_all_items($iterator);
    is @results, 1, 'Incomplete dates should recognize LT';
    is_deeply \@results, [$lil], '... and get the correct results';
    my $y1968 = Incomplete->new( year => 1968 );
    my $y1966 = Incomplete->new( year => 1966 );
    $iterator = $store->query(
        $class,
        date => LT $y1968,
        date => GT $y1966,
        name => LIKE '%vid',
        { order_by => 'date' }
    );
    @results = $test->_all_items($iterator);
    is @results, 1, 'Incomplete dates should recognize LT';
    is_deeply \@results, [$ovid], '... and get the correct results';
    $iterator = $store->query(
        $class,
        date => [ $y1966    => $y1968 ],
        name => LIKE 'Ovi%',
        { order_by => 'date' }
    );
    @results = $test->_all_items($iterator);
    is @results, 1, 'Incomplete dates should recognize BETWEEN';
    is_deeply \@results, [$ovid], '... and get the correct results';

    $iterator = $store->query(
        $class,
        date => [ $y1966    => $y1968 ],
        name => LIKE '%vid',
        { order_by => 'date' }
    );
    @results = $test->_all_items($iterator);
    is @results, 2,
      'Incomplete dates should recognize BETWEEN with complex queries';
    is_deeply \@results, [ $ovid, $theory ], '... and get the correct results';

    my $date1 = Incomplete->new( month => 6,    day   => 20 );
    my $date2 = Incomplete->new( year  => 1976, month => 1 );
    $iterator = $store->query(
        $class,
        date => ANY( $date1, $date2 ),
        { order_by => 'date' }
    );
    @results = $test->_all_items($iterator);
    is @results, 2,
      'We should be able to search on ANY incomplete dates with ANY';
    is_deeply \@results, [ $ovid, $lil ], '... and get the correct results';

    my $date3 = Incomplete->new( year => 1976, day => 4 );
    $iterator = $store->query(
        $class,
        date => ANY( $date1, $date2, $date3 ),
        { order_by => 'date' }
    );
    @results = $test->_all_items($iterator);
    is @results, 3,
      '... and ANY incomplete searches should allow non-contiguous dates';
    is_deeply \@results, [ $ovid, $lil, $usa ],
      '... and get the correct results';
}

sub string_search_incomplete_dates : Test(25) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $theory = Two->new;
    $theory->name('David');
    $theory->one->name('david_one_name');
    $theory->date(
        DateTime->new(
            year  => 1968,
            month => 12,
            day   => 19
        )
    );
    my $ovid = Two->new;
    $ovid->name('Ovid');
    $ovid->one->name('ovid_one_name');
    $ovid->date(
        DateTime->new(
            year  => 1967,
            month => 06,
            day   => 20
        )
    );
    my $usa = Two->new;
    $usa->one->name('usa_one_name');
    $usa->name('USA');
    $usa->date(
        DateTime->new(
            year  => 1976,    # yeah, I know
            month => 7,
            day   => 4,
        )
    );
    my $lil = Two->new;
    $lil->one->name('Lil');
    $lil->name('Lil_one_name');
    $lil->date(
        DateTime->new(
            year  => 1976,
            month => 1,
            day   => 9,
        )
    );
    my $store = Store->new;
    $_->save foreach $theory, $ovid, $usa, $lil;

    my $class    = $ovid->my_class;
    my $june     = Incomplete->new( month => 6 );
    my $iterator =
      $store->query( $class, STRING => 'date => "xxxx-06-xxTxx:xx:xx"' );
    my @results = $test->_all_items($iterator);
    is @results, 1, 'We should be able to search on incomplete dates';
    is_deeply \@results, [$ovid], '... and get the correct results';

    my $bicentennial = Incomplete->new( year => 1976 );
    $iterator = $store->query(
        $class,
        STRING   => 'date => "1976-xx-xxTxx:xx:xx"',
        order_by => 'date'
    );
    @results = $test->_all_items($iterator);
    is @results, 2, '... even if we have multiple results';
    is_deeply \@results, [ $lil, $usa ],
      '... but they had better be the correct results';

    $bicentennial->set( day => 4 );
    $iterator = $store->query(
        $class,
        STRING   => 'date => "1976-xx-04Txx:xx:xx"',
        order_by => 'date'
    );
    @results = $test->_all_items($iterator);
    is @results, 1, '... even if we have just a year and a day';
    is_deeply \@results, [$usa],
      '... but they had better be the correct results';

    my $bad_date = Incomplete->new( year => 1776 );
    $iterator =
      $store->query( $class, STRING => 'date => "1776-xx-xxTxx:xx:xx"' );
    @results = $test->_all_items($iterator);
    ok !@results,
'... but searching in a non-existent date should fail, even if it is an incomplete date';

    $june = Incomplete->new(
        month => '06',
        day   => '16',
    );
    $iterator = $store->query(
        $class,
        STRING   => 'date => GE "xxxx-06-16Txx:xx:xx"',
        order_by => 'date'
    );
    @results = $test->_all_items($iterator);
    is @results, 3, 'Incomplete dates should recognize GE';
    is_deeply \@results, [ $ovid, $theory, $usa ],
      '... and get the correct results';

    $june = Incomplete->new( month => 6 );
    $iterator = $store->query(
        $class,
        STRING   => 'date => GT "xxxx-06-xxTxx:xx:xx"',
        order_by => 'date'
    );
    @results = $test->_all_items($iterator);
    is @results, 2, 'Incomplete dates should recognize GT';
    is_deeply \@results, [ $theory, $usa ], '... and get the correct results';

    $june->set( day => 20 );
    $iterator = $store->query(
        $class,
        STRING   => 'date => LE "xxxx-06-20Txx:xx:xx"',
        order_by => 'date'
    );
    @results = $test->_all_items($iterator);
    is @results, 2, 'Incomplete dates should recognize LE';
    is_deeply \@results, [ $ovid, $lil ], '... and get the correct results';

    $iterator = $store->query(
        $class,
        STRING   => 'date => LT "xxxx-06-20Txx:xx:xx"',
        order_by => 'date'
    );
    @results = $test->_all_items($iterator);
    is @results, 1, 'Incomplete dates should recognize LT';
    is_deeply \@results, [$lil], '... and get the correct results';
    my $y1968 = Incomplete->new( year => 1968 );
    my $y1966 = Incomplete->new( year => 1966 );
    $iterator =
      $store->query( $class, STRING => <<'    END_SEARCH', order_by => 'date' );
        date => LT "1968-xx-xxTxx:xx:xx",
        date => GT "1966-xx-xxTxx:xx:xx",
        name => LIKE '%vid',
    END_SEARCH
    @results = $test->_all_items($iterator);
    is @results, 1, 'Incomplete dates should recognize LT';
    is_deeply \@results, [$ovid], '... and get the correct results';

    $iterator =
      $store->query( $class, STRING => <<'    END_SEARCH', order_by => 'date' );
        date => ["1966-xx-xxTxx:xx:xx" => "1968-xx-xxTxx:xx:xx"],
        name => LIKE 'Ovi%',
    END_SEARCH
    @results = $test->_all_items($iterator);
    is @results, 1, 'Incomplete dates should recognize BETWEEN';
    is_deeply \@results, [$ovid], '... and get the correct results';

    $iterator =
      $store->query( $class, STRING => <<'    END_SEARCH', order_by => 'date' );
        date => ["1966-xx-xxTxx:xx:xx" => "1968-xx-xxTxx:xx:xx"],
        name => LIKE '%vid',
    END_SEARCH
    @results = $test->_all_items($iterator);
    is @results, 2,
      'Incomplete dates should recognize BETWEEN with complex queries';
    is_deeply \@results, [ $ovid, $theory ], '... and get the correct results';

    my $date1 = Incomplete->new( month => 6,    day   => 20 );
    my $date2 = Incomplete->new( year  => 1976, month => 1 );
    $iterator =
      $store->query( $class, STRING => <<'    END_SEARCH', order_by => 'date' );
        date => ANY("xxxx-06-20Txx:xx:xx", "1976-01-xxTxx:xx:xx"),
    END_SEARCH
    @results = $test->_all_items($iterator);
    is @results, 2,
      'We should be able to search on ANY incomplete dates with ANY';
    is_deeply \@results, [ $ovid, $lil ], '... and get the correct results';

    my $date3 = Incomplete->new( year => 1976, day => 4 );
    $iterator =
      $store->query( $class, STRING => <<'    END_SEARCH', order_by => 'date' );
        date => ANY(
            "xxxx-06-20Txx:xx:xx",
            "1976-01-xxTxx:xx:xx",
            "1976-xx-04Txx:xx:xx"
        ),
    END_SEARCH
    @results = $test->_all_items($iterator);
    is @results, 3,
      '... and ANY incomplete searches should allow non-contiguous dates';
    is_deeply \@results, [ $ovid, $lil, $usa ],
      '... and get the correct results';
}

sub search_dates : Test(8) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $theory = Two->new;
    $theory->name('David');
    $theory->one->name('david_one_name');
    $theory->date(
        DateTime->new(
            year  => 1968,
            month => 12,
            day   => 19
        )
    );
    my $ovid = Two->new;
    $ovid->name('Ovid');
    $ovid->one->name('ovid_one_name');
    $ovid->date(
        DateTime->new(
            year  => 1967,
            month => 06,
            day   => 20
        )
    );
    my $usa = Two->new;
    $usa->one->name('usa_one_name');
    $usa->name('USA');
    $usa->date(
        DateTime->new(
            year  => 1976,    # yeah, I know
            month => 7,
            day   => 4,
        )
    );
    my $store = Store->new;
    $_->save foreach $theory, $ovid, $usa;

    my $class    = $ovid->my_class;
    my $iterator = $store->query( $class, date => GT $theory->date );
    my @results  = $test->_all_items($iterator);
    is @results, 1, 'We should be able to search on date fields of objects';
    is_deeply \@results, [$usa], '... and get the correct results';

    ok $iterator = $store->query(
        $class,
        date => GE $theory->date,
        { order_by => 'date' }
    );
    @results = $test->_all_items($iterator);
    is @results, 2, 'We should be able to search on date fields of objects';
    is_deeply \@results, [ $theory, $usa ], '... and get the correct results';

    ok $iterator = $store->query( $class, date => $theory->date );
    @results = $test->_all_items($iterator);
    is @results, 1, 'We should be able to search on date fields of objects';
    is_deeply \@results, [$theory], '... and get the correct results';
}

sub string_search_dates : Test(8) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $theory = Two->new;
    $theory->name('David');
    $theory->one->name('david_one_name');
    $theory->date(
        DateTime->new(
            year  => 1968,
            month => 12,
            day   => 19
        )
    );
    my $ovid = Two->new;
    $ovid->name('Ovid');
    $ovid->one->name('ovid_one_name');
    $ovid->date(
        DateTime->new(
            year  => 1967,
            month => 06,
            day   => 20
        )
    );
    my $usa = Two->new;
    $usa->one->name('usa_one_name');
    $usa->name('USA');
    $usa->date(
        DateTime->new(
            year  => 1976,    # yeah, I know
            month => 7,
            day   => 4,
        )
    );
    my $store = Store->new;
    $_->save foreach $theory, $ovid, $usa;

    my $class    = $ovid->my_class;
    my $iterator =
      $store->query( $class, STRING => "date => GT '@{[$theory->date->raw]}'" );
    my @results = $test->_all_items($iterator);
    is @results, 1,
      'We should be able to string search on date fields of objects';
    is_deeply \@results, [$usa], '... and get the correct results';

    ok $iterator = $store->query(
        $class,
        STRING   => "date => GE '@{[$theory->date->raw]}'",
        order_by => 'date'
    );
    @results = $test->_all_items($iterator);
    is @results, 2,
      'We should be able to string search on date fields of objects';
    is_deeply \@results, [ $theory, $usa ], '... and get the correct results';

    ok $iterator =
      $store->query( $class, STRING => "date => '@{[$theory->date]}'" );
    @results = $test->_all_items($iterator);
    is @results, 1,
      'We should be able to string earch on date fields of objects';
    is_deeply \@results, [$theory], '... and get the correct results';
}

sub search_compound : Test(9) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    #$test->clear_database;

    my $store = Store->new;
    can_ok $store, 'query';
    my $foo = Two->new;
    $foo->name('foo');
    $foo->age(13);
    $foo->one->name('foo_name');
    $foo->save;
    my $bar = Two->new;
    $bar->name('bar');
    $bar->age(29);
    $bar->one->name('bar_name');
    $bar->save;
    my $baz = Two->new;
    $baz->age(33);
    $baz->name('snorfleglitz');
    $baz->one->name('snorfleglitz_rulez_d00d');
    $baz->save;
    my $class    = $foo->my_class;
    my $iterator = $store->query( $class, 'one.name' => 'foo_name' );
    my @results  = $test->_all_items($iterator);
    is @results, 1,
      'We should be able to search on the key fields of contained objects';
    is_deeply \@results, [$foo], '... and get the correct results';

    $iterator = $store->query(
        $class,
        'one.name' => LIKE '%name',
        { order_by => 'one.name' }
    );
    @results = $test->_all_items($iterator);
    is @results, 2, '... and we should even be able to order by those fields';
    is_deeply \@results, [ $bar, $foo ], '... and get the correct results';

    my $one = $foo->one;
    $iterator = $store->query( $class, one => $one );
    @results = $test->_all_items($iterator);
    is @results, 1, '... and we should be able to search on just an object';
    is_deeply $results[0], $foo, '... and it should return the correct object';
    $iterator = $store->query(
        $class,
        one => $one,
        OR( 'one.name' => 'bar_name' ),
        { order_by => 'one.name' },
    );
    @results = $test->_all_items($iterator);
    is @results, 2, '... and we should even be able to order by those fields';
    is_deeply \@results, [ $bar, $foo ], '... and get the correct results';
}

sub string_search_compound : Test(9) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $store = Store->new;
    can_ok $store, 'query';
    my $foo = Two->new;
    $foo->name('foo');
    $foo->age(13);
    $foo->one->name('foo_name');
    $foo->save;
    my $bar = Two->new;
    $bar->name('bar');
    $bar->age(29);
    $bar->one->name('bar_name');
    $bar->save;
    my $baz = Two->new;
    $baz->age(33);
    $baz->name('snorfleglitz');
    $baz->one->name('snorfleglitz_rulez_d00d');
    $baz->save;
    my $class    = $foo->my_class;
    my $iterator = $store->query( $class, STRING => "one.name => 'foo_name'" );
    my @results  = $test->_all_items($iterator);
    is @results, 1,
      'We should be able to search on the key fields of contained objects';
    is_deeply \@results, [$foo], '... and get the correct results';

    $iterator = $store->query(
        $class,
        STRING   => "one.name => LIKE '\%name'",
        order_by => 'one.name'
    );
    @results = $test->_all_items($iterator);
    is @results, 2, '... and we should even be able to order by those fields';
    is_deeply \@results, [ $bar, $foo ], '... and get the correct results';

    my $one = $foo->one;
    $iterator =
      $store->query( $class, STRING => "one__id => '@{[$one->{id}]}'" );
    @results = $test->_all_items($iterator);
    is @results, 1, '... and we should be able to search on just an object';
    is_deeply $results[0], $foo, '... and it should return the correct object';
    $iterator = $store->query(
        $class,
        STRING   => "one__id => '@{[$one->{id}]}', OR(one.name => 'bar_name')",
        order_by => 'one.name',
    );
    @results = $test->_all_items($iterator);
    is @results, 2, '... and we should even be able to order by those fields';
    is_deeply \@results, [ $bar, $foo ], '... and get the correct results';
}

sub limit : Test(12) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        {
            limit    => 2,
            order_by => 'name',
        }
      ),
      'A search with a limit should succeed';
    my @results = $test->_all_items($iterator);
    is @results, 2,
      'returning no more than the number of objects specified in the limit';

    $iterator = $store->query(
        $class,
        {
            limit    => 4,
            order_by => 'name',
        }
    );
    @results = $test->_all_items($iterator);
    is @results, 3, 'but no more than the number of objects available';

    $iterator = $store->query(
        $class,
        {
            limit    => 0,
            order_by => 'name',
        }
    );
    @results = $test->_all_items($iterator);
    ok !@results, 'and no objects if the limit is 0';

    for my $letter ( 'a' .. 'z' ) {
        my $object = One->new;
        $object->name($letter);
        $object->save;
    }
    $iterator = $store->query(
        $class,
        {
            limit    => 30,
            order_by => 'name',
        }
    );
    @results = $test->_all_items($iterator);
    is @results, 29,
'We should have all 26 letters of the alphabet plus the original three objects';

    $iterator = $store->query(
        $class,
        name => LIKE '_',
        {
            limit    => 30,
            order_by => 'name',
        }
    );
    @results = $test->_all_items($iterator);
    is @results, 26, 'We should have all 26 letters of the alphabet';

    $iterator = $store->query(
        $class,
        name => LIKE '_',
        {
            limit    => 13,
            order_by => 'name',
        }
    );
    @results = $test->_all_items($iterator);
    is @results, 13, 'We should have 13 letters of the alphabet';
    my @letters = map $_->name => @results;
    is_deeply \@letters, [ 'a' .. 'm' ],
      'and they should be the first 13 letters';

    $iterator = $store->query(
        $class,
        name => LIKE '_',
        {
            limit    => 13,
            order_by => 'name',
            offset   => 13,
        }
    );
    @results = $test->_all_items($iterator);
    is @results, 13, 'We should have 13 letters of the alphabet';
    @letters = map $_->name => @results;
    is_deeply \@letters, [ 'n' .. 'z' ],
      'and they should be the last 13 letters';

    $iterator = $store->query(
        $class,
        name => LIKE '_',
        {
            limit    => 24,
            order_by => 'name',
            offset   => 1,
        }
    );
    @results = $test->_all_items($iterator);
    is @results, 24, 'We should have 24 letters of the alphabet';
    @letters = map $_->name => @results;
    is_deeply \@letters, [ 'b' .. 'y' ],
      'and they should be all but the first and last letters';
}

sub string_limit : Test(12) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        STRING   => '',
        limit    => 2,
        order_by => 'name',
      ),
      'A string search with a limit should succeed';
    my @results = $test->_all_items($iterator);
    is @results, 2,
      'returning no more than the number of objects specified in the limit';

    $iterator = $store->query(
        $class,
        STRING   => '',
        limit    => 4,
        order_by => 'name',
    );
    @results = $test->_all_items($iterator);
    is @results, 3, 'but no more than the number of objects available';

    $iterator = $store->query(
        $class,
        STRING   => '',
        limit    => 0,
        order_by => 'name',
    );
    @results = $test->_all_items($iterator);
    ok !@results, 'and no objects if the limit is 0';

    for my $letter ( 'a' .. 'z' ) {
        my $object = One->new;
        $object->name($letter);
        $object->save;
    }
    $iterator = $store->query(
        $class,
        STRING   => '',
        limit    => 30,
        order_by => 'name',
    );
    @results = $test->_all_items($iterator);
    is @results, 29,
'We should have all 26 letters of the alphabet plus the original three objects';

    $iterator = $store->query(
        $class,
        STRING   => "name => LIKE '_'",
        limit    => 30,
        order_by => 'name',
    );
    @results = $test->_all_items($iterator);
    is @results, 26, 'We should have all 26 letters of the alphabet';

    $iterator = $store->query(
        $class,
        STRING   => "name => LIKE '_'",
        limit    => 13,
        order_by => 'name',
    );
    @results = $test->_all_items($iterator);
    is @results, 13, 'We should have 13 letters of the alphabet';
    my @letters = map $_->name => @results;
    is_deeply \@letters, [ 'a' .. 'm' ],
      'and they should be the first 13 letters';

    $iterator = $store->query(
        $class,
        STRING   => "name => LIKE '_'",
        limit    => 13,
        order_by => 'name',
        offset   => 13,
    );
    @results = $test->_all_items($iterator);
    is @results, 13, 'We should have 13 letters of the alphabet';
    @letters = map $_->name => @results;
    is_deeply \@letters, [ 'n' .. 'z' ],
      'and they should be the last 13 letters';

    $iterator = $store->query(
        $class,
        STRING   => "name => LIKE '_'",
        limit    => 24,
        order_by => 'name',
        offset   => 1,
    );
    @results = $test->_all_items($iterator);
    is @results, 24, 'We should have 24 letters of the alphabet';
    @letters = map $_->name => @results;
    is_deeply \@letters, [ 'b' .. 'y' ],
      'and they should be all but the first and last letters';
}

sub count : Test(15) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'count';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    ok my $count = $store->count($class),
      'A count with only a class should succeed';
    is $count, 3, 'returning a count of all instances';
    ok $count = $store->count( $class, name => 'foo' ),
      'We should be able to count with a simple search';
    is $count, 1, 'returning the correct count';

    ok $count = $store->count( $class, name => GT 'c' ),
      'We should be able to count with any search operators';
    is $count, 2, 'returning the correct count';

    ok !( $count = $store->count( $class, name => 'no such name' ) ),
      'and it should return a false count if nothing matches';

    ok $count = $foo->count, 'A search with only a class should succeed';
    is $count, 3, 'returning a count of all instances';
    ok $count = $foo->count( name => 'foo' ),
      'We should be able to count with a simple search';
    is $count, 1, 'returning the correct count';

    ok $count = $foo->count( name => GT 'c' ),
      'We should be able to count with any search operators';
    is $count, 2, 'returning the correct count';

    ok !( $count = $foo->count( name => 'no such name' ) ),
      'and it should return a false count if nothing matches';
}

sub count_by_key : Test(8) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'count';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $key = $foo->my_class->key;
    ok my $count = $store->count($key),
      'A search with only a class should succeed';
    is $count, 3, 'returning a count of all instances';
    ok $count = $store->count( $key, name => 'foo' ),
      'We should be able to count with a simple search';
    is $count, 1, 'returning the correct count';

    ok $count = $store->count( $key, name => GT 'c' ),
      'We should be able to count with any search operators';
    is $count, 2, 'returning the correct count';

    ok !( $count = $store->count( $key, name => 'no such name' ) ),
      'and it should return a false count if nothing matches';
}

sub query_uuids : Test(10) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'query_uuids';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    ok my $uuids = $store->query_uuids($class),
      'A search for uuids with only a class should succeed';
    @$uuids = sort @$uuids;
    my @expected = sort map { $_->uuid } $foo, $bar, $baz;
    is_deeply $uuids, \@expected,
      'and it should return the correct list of uuids';

    ok $uuids = $store->query_uuids( $class, name => 'foo' ),
      'We should be able to search uuids with a simple search';
    is_deeply $uuids, [ $foo->uuid ], 'and return the correct uuids';

    ok $uuids =
      $store->query_uuids( $class, name => GT 'c', { order_by => 'name' } ),
      'We should be able to search uuids with any search operators';
    is_deeply $uuids, [ $foo->uuid, $baz->uuid ],
      'and return the correct uuids';

    $uuids = $store->query_uuids( $class, name => 'no such name' );
    is_deeply $uuids, [], 'and it should return nothing if nothing matches';

    ok my @uuids =
      $store->query_uuids( $class, name => GT 'c', { order_by => 'name' } ),
      'query_uuids should behave correctly in list context';
    is_deeply \@uuids, [ $foo->uuid, $baz->uuid ],
      'and return the correct uuids';
}

sub query_uuids_by_key : Test(10) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'query_uuids';
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $key = $foo->my_class->key;
    ok my $uuids = $store->query_uuids($key),
      'A search for uuids with only a class should succeed';
    @$uuids = sort @$uuids;
    my @expected = sort map { $_->uuid } $foo, $bar, $baz;
    is_deeply $uuids, \@expected,
      'and it should return the correct list of uuids';

    ok $uuids = $store->query_uuids( $key, name => 'foo' ),
      'We should be able to search uuids with a simple search';
    is_deeply $uuids, [ $foo->uuid ], 'and return the correct uuids';

    ok $uuids =
      $store->query_uuids( $key, name => GT 'c', { order_by => 'name' } ),
      'We should be able to search uuids with any search operators';
    is_deeply $uuids, [ $foo->uuid, $baz->uuid ],
      'and return the correct uuids';

    $uuids = $store->query_uuids( $key, name => 'no such name' );
    is_deeply $uuids, [], 'and it should return nothing if nothing matches';

    ok my @uuids =
      $store->query_uuids( $key, name => GT 'c', { order_by => 'name' } ),
      'query_uuids should behave correctly in list context';
    is_deeply \@uuids, [ $foo->uuid, $baz->uuid ],
      'and return the correct uuids';
}

sub search_or : Test(13) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => 'foo',
        OR( name => LIKE 'snorf%' ),
        { order_by => 'name', sort_order => DESC }
    );
    my @items = $test->_all_items($iterator);
    is @items, 2, 'OR should return the correct number of items';
    is_deeply \@items, [ $baz, $foo ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        name => 'foo',
        OR( description => NOT undef ),
        { order_by => 'name', sort_order => DESC }
    );
    @items = $test->_all_items($iterator);
    is @items, 1, 'OR matches should return the correct number of items';
    is_deeply \@items, [$foo], 'and should include the correct items';

    $bar->description('giggling pastries');
    $bar->save;
    ok $iterator = $store->query(
        $class,
        name => 'foo',
        OR( description => NOT undef ),
        { order_by => 'name', sort_order => DESC }
    );
    @items = $test->_all_items($iterator);
    is @items, 2, 'OR matches should return the correct number of items';
    is_deeply \@items, [ $foo, $bar ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        name           => 'foo',
        OR description => NOT undef,
    );
    @items = sort { $a->name cmp $b->name } $test->_all_items($iterator);
    is @items, 2, 'OR should succeed even without parens';
    is_deeply \@items, [ $bar, $foo ], 'and should include the correct items';

    throws_ok {
        $iterator = $store->query(
            $class,
            name => 'foo',
            OR
              description => NOT undef,
            { order_by => 'name' }
        )
      } 'Object::Relation::Exception::Fatal::Search',
      'but it will choke without parens if you pass constraints';
}

sub search_and : Test(15) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        AND( name => 'foo', name => LIKE 'snorf%' ),
        { order_by => 'name', sort_order => DESC }
    );
    my @items = $test->_all_items($iterator);
    is @items, 0, 'AND should return the correct number of items';
    is_deeply \@items, [], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        AND( name => 'foo', description => NOT undef ),
        { order_by => 'name', sort_order => DESC }
    );
    @items = $test->_all_items($iterator);
    is @items, 0, 'AND matches should return the correct number of items';
    is_deeply \@items, [], 'and should include the correct items';

    $bar->description('giggling pastries');
    $bar->save;
    ok $iterator = $store->query(
        $class,
        AND( name => 'bar', description => NOT undef ),
        { order_by => 'name', sort_order => DESC }
    );
    @items = $test->_all_items($iterator);
    is @items, 1, 'OR matches should return the correct number of items';
    is_deeply \@items, [$bar], 'and should include the correct items';

    $foo->description('We Want Revolution');
    $foo->save;
    ok $iterator = $store->query(
        $class,
        AND( description => NOT undef, OR( name => 'foo', name => 'bar' ) ),
        { order_by => 'name', sort_order => DESC }
    );
    @items = $test->_all_items($iterator);
    is @items, 2,
      'ComplexAND/OR matches should return the correct number of items';
    is_deeply \@items, [ $foo, $bar ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        description => NOT undef,
        OR( name => 'foo', name => 'bar' ),
        { order_by => 'name', sort_order => DESC }
    );
    is @items, 2,
      'ComplexAND/OR matches should return the correct number of items';
    is_deeply \@items, [ $foo, $bar ], 'and should include the correct items';
}

sub search_overloaded : Test(11) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    {

        package Test::String;
        use overload '""' => \&to_string;
        sub new { my ( $pkg, $val ) = @_; bless \$val => $pkg; }
        sub to_string { ${ $_[0] } }
    }
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;

    $bar->description('giggling pastries');
    $bar->save;
    my $bname = Test::String->new('bar');
    ok my $iterator = $store->query(
        $class,
        AND( name => $bname, description => NOT undef ),
        { order_by => 'name', sort_order => DESC }
    );
    my @items = $test->_all_items($iterator);
    is @items, 1, 'OR matches should return the correct number of items';
    is_deeply \@items, [$bar], 'and should include the correct items';

    $foo->description('We Want Revolution');
    $foo->save;
    ok $iterator = $store->query(
        $class,
        AND( description => NOT undef, OR( name => 'foo', name => $bname ) ),
        { order_by => 'name', sort_order => DESC }
    );
    @items = $test->_all_items($iterator);
    is @items, 2,
      'ComplexAND/OR matches should return the correct number of items';
    is_deeply \@items, [ $foo, $bar ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        description => NOT undef,
        OR( name => 'foo', name => $bname ),
        { order_by => 'name', sort_order => DESC }
    );
    is @items, 2,
      'ComplexAND/OR matches should return the correct number of items';
    is_deeply \@items, [ $foo, $bar ], 'and should include the correct items';

    {

        package Test::Number;
        use overload '""' => \&to_string;
        sub new { my ( $pkg, $val ) = @_; bless \$val => $pkg; }
        sub to_string { ${ $_[0] } }
    }
    $foo = Two->new;
    $foo->name('foo');
    $foo->age(13);
    $foo->one->name('foo_name');
    $foo->save;
    $bar = Two->new;
    $bar->name('bar');
    $bar->age(29);
    $bar->one->name('bar_name');
    $bar->save;
    $baz = Two->new;
    $baz->age(33);
    $baz->name('snorfleglitz');
    $baz->one->name('snorfleglitz_rulez_d00d');
    $baz->save;
    $class = $foo->my_class;
    my $twelve = Test::Number->new(12);
    my $thirty = Test::Number->new(30);
    $iterator = $store->query(
        $class,
        age => [ $twelve => $thirty ],
        { order_by => 'age' }
    );
    my @results = $test->_all_items($iterator);
    is @results, 2,
      'Searching on a range should return the correct number of results';

    #@results = sort { $a->age <=> $b->age } @results;
    is_deeply \@results, [ $foo, $bar ], '... and the correct results';
}

sub lookup : Test(8) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $one = One->new;
    $one->name('Ovid');
    $one->description('test class');
    my $store = Store->new;
    $one->save;

    my $two = One->new;
    $two->name('divO');
    $two->description('ssalc tset');
    $two->save;
    can_ok $store, 'lookup';
    my $thing = $store->lookup( $two->my_class, uuid => $two->uuid );
    is_deeply $test->force_inflation($thing), $two,
      'and it should return the correct object';

    foreach my $method (qw/name description uuid state/) {
        is $thing->$method, $two->$method, "$method() should behave the same";
    }
    throws_ok { $store->lookup( $two->my_class, 'no_such_attribute' => 1 ) }
      'Object::Relation::Exception::Fatal::Attribute',
      'but it should croak if you search for a non-existent attribute';
    throws_ok { $store->lookup( $two->my_class, 'name' => 1 ) }
      'Object::Relation::Exception::Fatal::Attribute',
      'or if you search on a non-unique field';
}

sub lookup_by_key : Test(8) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    $test->clear_database;
    my $one = One->new;
    $one->name('Ovid');
    $one->description('test class');
    my $store = Store->new;
    $one->save;

    my $two = One->new;
    $two->name('divO');
    $two->description('ssalc tset');
    $two->save;
    can_ok $store, 'lookup';
    my $key = $two->my_class->key;
    my $thing = $store->lookup( $key, uuid => $two->uuid );
    is_deeply $test->force_inflation($thing), $two,
      'and it should return the correct object';

    foreach my $method (qw/name description uuid state/) {
        is $thing->$method, $two->$method, "$method() should behave the same";
    }
    throws_ok { $store->lookup( $key, 'no_such_attribute' => 1 ) }
      'Object::Relation::Exception::Fatal::Attribute',
      'but it should croak if you search for a non-existent attribute';
    throws_ok { $store->lookup( $key, 'name' => 1 ) }
      'Object::Relation::Exception::Fatal::Attribute',
      'or if you search on a non-unique field';
}

sub search_between : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class    = $foo->my_class;
    my $store    = Store->new;
    my $iterator = $store->query( $class, name => [ 'b' => 'g' ] );

    my @iterator = $test->_all_items($iterator);
    is @iterator, 2, 'and return the correct number of matches';
    @iterator = sort { $a->name cmp $b->name } @iterator;
    is_deeply \@iterator, [ $bar, $foo ], 'and the correct objects';

    $iterator = $store->query( $class, name => [ 'f' => 's' ] );
    @iterator = $test->_all_items($iterator);
    is @iterator, 1,
      'and a BETWEEN match should return the correct number of objects';
    is_deeply $iterator[0], $foo, '... and they should be the correct ones';

    $iterator = $store->query(
        $class,
        name => NOT [ 'f' => 's' ],
        { order_by => 'name' }
    );
    @iterator = $test->_all_items($iterator);
    is @iterator, 2, 'A NOT BETWEEN should return the correct number of items.';
    is_deeply \@iterator, [ $bar, $baz ], 'and the should be the correct items';
}

sub search_gt : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => GT 'c',
        { order_by => 'name' }
      ),
      'We should be able to do a GT search';
    my @items = $test->_all_items($iterator);
    is @items, 2, 'and get the proper number of items';
    is_deeply \@items, [ $foo, $baz ], 'not to mention the correct items';

    ok $iterator = $store->query(
        $class,
        name => NOT GT 'c',
        { order_by => 'name' }
      ),
      'We should be able to do a NOT GT search';
    @items = $test->_all_items($iterator);
    is @items, 1, 'and get the proper number of items';
    is_deeply \@items, [$bar], 'not to mention the correct items';
}

sub search_lt : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => LT 's',
        { order_by => 'name' }
      ),
      'We should be able to do an LT search';
    my @items = $test->_all_items($iterator);
    is @items, 2, 'and get the proper number of items';
    is_deeply \@items, [ $bar, $foo ], 'not to mention the correct items';

    ok $iterator = $store->query(
        $class,
        name => NOT LT 's',
        { order_by => 'name' }
      ),
      'We should be able to do a NOT LT search';
    @items = $test->_all_items($iterator);
    is @items, 1, 'and get the proper number of items';
    is_deeply \@items, [$baz], 'not to mention the correct items';
}

sub search_eq : Test(14) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => EQ 's',
        { order_by => 'name' }
      ),
      'We should be able to do an EQ search';
    my @items = $test->_all_items($iterator);
    is @items, 0, 'and we should get nothing if we do a bad match';

    ok $iterator = $store->query(
        $class,
        name => EQ 'foo',
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 1,
      'but EQ should also function as syntactic sugar for $key => $value';
    is_deeply $items[0], $foo, 'and return the correct results';
    ok $iterator = $store->query(
        $class,
        name => NOT EQ 'foo',
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 2, 'NOT EQ should also work as expected';
    is_deeply \@items, [ $bar, $baz ], 'and return the correct results';

    ok $iterator = $store->query(
        $class,
        name => NE 'foo',
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 2, 'NE should also work as expected';
    is_deeply \@items, [ $bar, $baz ], 'and return the correct results';

    $store = Store->new;
    ok $iterator = $store->query(
        $class,
        name => NOT 'foo',
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 2, '"name => NOT $value" should also work as expected';
    is_deeply \@items, [ $bar, $baz ], 'and return the correct results';
}

sub search_ge : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => GE 'f',
        { order_by => 'name' }
    );
    my @items = $test->_all_items($iterator);
    is @items, 2, 'and GE should return the correct number of items';
    is_deeply \@items, [ $foo, $baz ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        name => NOT GE 'f',
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 1, 'NOT GE should return the correct number of items';
    is_deeply \@items, [$bar], 'and should include the correct items';
}

sub search_le : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => LE 'foo',
        { order_by => 'name' }
    );
    my @items = $test->_all_items($iterator);
    is @items, 2, 'and LE should return the correct number of items';
    is_deeply \@items, [ $bar, $foo ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        name => NOT LE 'foo',
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 1, 'NOT LE should return the correct number of items';
    is_deeply \@items, [$baz], 'and should include the correct items';
}

sub search_like : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => LIKE 'f%',
        { order_by => 'name' }
      ),
      'and calling search should succeed';
    my @items = $test->_all_items($iterator);
    is @items, 1, 'and LIKE should return the correct number of items';
    is_deeply \@items, [$foo], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        name => NOT LIKE 'f%',
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 2, 'NOT LIKE should return the correct number of items';
    is_deeply \@items, [ $bar, $baz ], 'and should include the correct items';
}

sub search_null : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    $foo->description('this is a description');
    my $store = Store->new;
    $foo->save;
    my $class = $foo->my_class;

    ok my $iterator = $store->query(
        $class,
        description => undef,
        { order_by => 'name' }
    );
    my @items = $test->_all_items($iterator);
    is @items, 2, '"undef" should return the correct number of items';
    is_deeply \@items, [ $bar, $baz ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        description => NOT undef,
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 1, '"NOT undef" should return the correct number of items';
    is_deeply \@items, [$foo], 'and should include the correct items';
}

sub search_in : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my ( $foo, $bar, $baz ) = $test->test_objects;
    my $class = $foo->my_class;
    my $store = Store->new;
    ok my $iterator = $store->query(
        $class,
        name => ANY(qw/foo bar/),
        { order_by => 'name' }
    );
    my @items = $test->_all_items($iterator);
    is @items, 2, 'ANY should return the correct number of items';
    is_deeply \@items, [ $bar, $foo ], 'and should include the correct items';

    ok $iterator = $store->query(
        $class,
        name => NOT ANY(qw/foo bar/),
        { order_by => 'name' }
    );
    @items = $test->_all_items($iterator);
    is @items, 1, 'NOT ANY should return the correct number of items';
    is_deeply \@items, [$baz], 'and should include the correct items';
}

sub save_compound : Test(3) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $store = Store->new;
    can_ok $store, 'query';
    my $foo = Two->new;
    $foo->name('foo');
    $foo->age(13);
    $foo->one->name('foo_name');
    $foo->save;
    my $bar = Two->new;
    $bar->name('bar');
    $bar->age(29);
    $bar->one->name('bar_name');
    $bar->save;
    my $baz = Two->new;
    $baz->age(33);
    $baz->name('snorfleglitz');
    $baz->one->name('snorfleglitz_rulez_d00d');
    $baz->save;
    my $class    = $foo->my_class;
    my $iterator = $store->query( $class, age => [ 12 => 30 ] );
    my @results  = $test->_all_items($iterator);
    is @results, 2,
      'Searching on a range should return the correct number of results';
    @results = sort { $a->age <=> $b->age } @results;
    is_deeply \@results, [ $foo, $bar ], '... and the correct results';
}

sub order_by : Test(4) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $foo   = Two->new;
    my $store = Store->new;
    $foo->name('foo');
    $foo->age(29);
    $foo->one->name('foo_name');
    $foo->save;

    my $bar = Two->new;
    $bar->name('foo');
    $bar->age(13);
    $bar->one->name('bar_name');
    $bar->save;

    my $baz = Two->new;
    $baz->age(33);
    $baz->name('snorfleglitz');
    $baz->one->name('snorfleglitz_rulez_d00d');
    $baz->save;
    my $class    = $foo->my_class;
    my $iterator = $store->query( $class, { order_by => 'name' } );
    my @results  = $test->_all_items($iterator);
    if ( $results[0]->age < $results[1]->age ) {
        @results[ 0, 1 ] = @results[ 1, 0 ];
    }
    is_deeply \@results, [ $foo, $bar, $baz ],
      'order_by constraints should work properly';

    # XXX don't forgot about ordering by non-existent attributes
    $iterator = $store->query( $class, { order_by => [ 'name', 'age' ] } );
    @results = $test->_all_items($iterator);
    is_deeply \@results, [ $bar, $foo, $baz ],
      'even if we have more than one order_by constraint';

    $iterator = $store->query(
        $class,
        {
            order_by => [qw/name age/],
            sort_order => [ ASC, DESC ],
        }
    );
    @results = $test->_all_items($iterator);
    is_deeply \@results, [ $foo, $bar, $baz ],
      'and we should be able to handle multiple sort parameters';

    $iterator =
      $store->query( $class, { order_by => 'age', sort_order => DESC } );
    @results = $test->_all_items($iterator);
    is_deeply \@results, [ $baz, $foo, $bar ],
      'and we can combine single items order_by and sort parameters';
}

sub string_order_by : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $foo   = Two->new;
    my $store = Store->new;
    $foo->name('foo');
    $foo->age(29);
    $foo->one->name('foo_name');
    $foo->save;

    my $bar = Two->new;
    $bar->name('foo');
    $bar->age(13);
    $bar->one->name('bar_name');
    $bar->save;

    my $baz = Two->new;
    $baz->age(33);
    $baz->name('snorfleglitz');
    $baz->one->name('snorfleglitz_rulez_d00d');
    $baz->save;
    my $class = $foo->my_class;

    throws_ok {
        $store->query(
            $class,
            STRING   => '',
            order_by => 'name',
            'sort_order'
        );
      } 'Object::Relation::Exception::Fatal::Search',
      'An odd number of constraints should throw an exception';
    my $iterator = $store->query(
        $class,
        STRING   => '',
        order_by => 'name'
    );
    my @results = $test->_all_items($iterator);

    if ( $results[0]->age < $results[1]->age ) {
        @results[ 0, 1 ] = @results[ 1, 0 ];
    }
    is_deeply \@results, [ $foo, $bar, $baz ],
      'String order_by constraints should work properly';

    # XXX don't forgot about ordering by non-existent attributes
    $iterator = $store->query(
        $class,
        STRING   => '',
        order_by => 'name',
        order_by => 'age',
    );
    @results = $test->_all_items($iterator);
    is_deeply \@results, [ $bar, $foo, $baz ],
      'even if we have more than one order_by constraint';

    $iterator = $store->query(
        $class,
        STRING     => '',
        order_by   => 'name',
        sort_order => 'ASC',
        order_by   => 'age',
        sort_order => 'DESC',
    );
    @results = $test->_all_items($iterator);
    is_deeply \@results, [ $foo, $bar, $baz ],
      'and we should be able to handle multiple sort parameters';

    $iterator = $store->query(
        $class,
        STRING     => '',
        order_by   => 'name',
        order_by   => 'age',
        sort_order => 'ASC',
        sort_order => 'DESC',
    );
    @results = $test->_all_items($iterator);
    is_deeply \@results, [ $foo, $bar, $baz ],
'... even if they do not immediately follow the corresponding order_by param';

    $iterator = $store->query(
        $class,
        STRING     => '',
        order_by   => 'age',
        sort_order => 'DESC'
    );
    @results = $test->_all_items($iterator);
    is_deeply \@results, [ $baz, $foo, $bar ],
      'and we can combine single items order_by and sort parameters';
}

sub joins : Test(6) {
    my $test = shift;
    return 'abtract_class' unless $test->_should_run;
    my $yello = Yello->new( age => 32 );
    my $coll = $yello->ones;
    my @ones = map { One->new( name => $_ ) } qw/uno dos tres/;
    $yello->ones( $coll->from_list( { list => \@ones } ) );
    $yello->save;
    my $yello_2 = Yello->new( age => 19 );
    $yello_2->save;

    ok my $iterator = One->query(
        'yello.uuid' => $yello->uuid,
        { order_by => 'one.name' }
    ), 'Searching collection objects on a parent UUID should succeed';

    my @results = $test->_all_items($iterator);
    is scalar @results, 3, '... and return the correct number of results';

    is_deeply [map { $_->name } @results ], [qw/dos tres uno/],
        '... and return the correct objects';

    ok $iterator = Yello->query( 'one.name' => 'uno' ),
        'Searching parent objects on collection attributes should succeed';

    @results = $test->_all_items($iterator);
    is scalar @results, 1, '... and return the correct number of results';

    is_deeply [map { $_->uuid } @results ], [ $yello->uuid ],
        '... and return the correct objects';
}

sub collections : Test(39) {
    my $self = shift;
    return unless $self->_should_run;
    ok my $yello = Yello->new( age => 32 ), 'Create new Yello';
    ok my $coll = $yello->ones, 'Get ones collection';
    my @names = qw/uno dos tres/;
    my @ones = map { One->new( name => $_ ) } @names;
    ok $coll->assign(@ones), 'Assign three ones to the collection';
    ok $yello->save, 'Save the yello object';

    ok $yello = Yello->lookup( uuid => $yello->uuid ),
        'Look up the yello object in the database';
    ok $coll = $yello->ones, 'Grab the ones collection';
    is $coll->size, 3, 'The collection should have three items';
    is_deeply [ map { $_->name } $coll->all ], [@names],
        'And they should be in the proper order';
    ok $coll->add(One->new( name => 'quatre')),
        'Add another item to the collection';
    is $coll->size, 4, 'The size should now be four';
    is $coll->get(3)->name, 'quatre', 'The new one should be the fourth';
    ok $yello->save, 'Save the yello object again';

    ok $yello = Yello->lookup( uuid => $yello->uuid ),
        'Look up the yello object again in the database';
    ok $coll = $yello->ones, 'Grab the ones collection';
    is $coll->size, 4, 'The collection should have four items';
    is_deeply [ map { $_->name } $coll->all ], [@names, 'quatre'],
        'And they should be in the proper order';
    ok $coll->remove($coll->get(0), $coll->get(3)),
        'Remove two items from the collection';
    is $coll->size, 2, 'The size should now be two';
    is_deeply [ map { $_->name } $coll->all ], [@names[1..2]],
        'The remaining items should still be in order';
    ok $yello->save, 'Save the yello object again';

    ok $yello = Yello->lookup( uuid => $yello->uuid ),
        'Look up the yello object again in the database';
    ok $coll = $yello->ones, 'Grab the ones collection';
    is $coll->size, 2, 'The collection should still have two items';
    is_deeply [ map { $_->name } $coll->all ], [@names[1..2]],
        'They should be in order';
    ok $coll->assign(One->new(name => 'foo')),
        'Assign a single item to the collection';
    is $coll->size, 1, 'The collection should now have only one object';
    is_deeply [ map { $_->name } $coll->all ], ['foo'],
        'And it should be the correct object';
    ok $coll->is_assigned, 'is_assigned() should return true';
    ok $yello->save, 'Save the yello object again';

    ok $yello = Yello->lookup( uuid => $yello->uuid ),
        'Look up the yello object again in the database';
    ok $coll = $yello->ones, 'Grab the ones collection';
    is $coll->size, 1, 'The collection should still have one item';
    is_deeply [ map { $_->name } $coll->all ], ['foo'],
        'And it should be the correct item';
    ok $coll->clear, 'Clear the collection';
    is $coll->size, 0, 'The collection should have no items';
    ok $yello->save, 'Save the yello object again';

    ok $yello = Yello->lookup( uuid => $yello->uuid ),
        'Look up the yello object again in the database';
    ok $coll = $yello->ones, 'Grab the ones collection';
    is $coll->size, 0, 'The collection should still have no items';
}

1;
