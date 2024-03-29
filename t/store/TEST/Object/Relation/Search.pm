package TEST::Object::Relation::Search;

# $Id: Search.pm 3074 2006-07-26 20:22:04Z theory $

use strict;
use warnings;

use base 'TEST::Class::Object::Relation';
use Test::More;
use Test::Exception;

use aliased 'Object::Relation::Search';
use aliased 'TestApp::Simple::One';

__PACKAGE__->runtests unless caller;

sub constructor : Test(3) {
    my $test = shift;

    throws_ok { Search->new( unknown_attr => 1 ) }
      'Object::Relation::Exception::Fatal::Search',
      'new() with unknown attributes should throw an exception';

    my %search = (
        param    => 'name',
        operator => 'EQ',
        negated  => 'NOT',
        data     => 'foo',
        class    => Object::Relation::Meta->for_key('one'),
    );
    ok my $search = Search->new(%search),
      '... and creating a new Search object should succeed';
    isa_ok $search, Search, '... and the object it returns';
}

sub methods : Test(16) {
    my $test = shift;

    my %search = (
        param    => 'name',
        operator => 'EQ',
        negated  => 'NOT',
        data     => 'foo',
        class    => Object::Relation::Meta->for_key('one'),
    );
    ok my $search = Search->new(%search),
      'Creating an EQ search should succeed';

    can_ok $search, 'search_method';
    is $search->search_method, '_EQ_SEARCH',
      '... and it should return the correct search method';
    is $search->search_method, '_EQ_SEARCH',
      '... and we should be able to call it twice in a row';    # bug fix

    can_ok $search, 'operator';
    is $search->operator, '!=', '... and it should return the correct operator';

    can_ok $search, 'negated';
    is $search->negated, 'NOT', '... and it should return the correct value';

    can_ok $search, 'original_operator';
    is $search->original_operator, 'EQ',
      '... and we should be able to get the original search operator';

    can_ok $search, 'formatted_data';
    is $search->formatted_data, 'foo',
      '... and it should return the data we are searching for';

    $search{operator} = 'BETWEEN';
    $search{data}     = [ 21, 42 ];

    ok $search = Search->new(%search),
      'Creating a BETWEEN search should succeed';
    is $search->formatted_data, '(21, 42)',
      '... and formatted_data should return data Data::Dumper-formatted';

    $search{data}     = [ 'alpha', 'omega' ];

    ok $search = Search->new(%search),
      'Creating a BETWEEN search should succeed';
    is $search->formatted_data, "('alpha', 'omega')",
      '... and formatted_data should return data Data::Dumper-formatted';
}

1;
