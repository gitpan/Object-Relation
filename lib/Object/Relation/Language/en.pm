package Object::Relation::Language::en;

# $Id: en.pm 3076 2006-07-28 17:20:08Z theory $

use strict;

use version;
our $VERSION = version->new('0.1.0');

use base 'Object::Relation::Language';
use encoding 'utf8';

=encoding utf8

=head1 Name

Object::Relation::Language::en - Object::Relation English localization

=head1 Description

This class handles Object::Relation English localization. See
L<Object::Relation::Language|Object::Relation::Language> for a complete description
of the Object::Relation localization interface.

=cut

our %Lexicon;
{
    my %classes = (
        'Object::Relation Base Class' => 'Object::Relation Base Class',
        'Class'              => 'Class',
        'Classes'            => 'Classes',
    );

    my %obj_rel_object_states = (
        'Permanent' => 'Permanent',
        'Active'    => 'Active',
        'Inactive'  => 'Inactive',
        'Deleted'   => 'Deleted',
        'Purged'    => 'Purged',
    );

    my %lexer_parser_messages = (
        'Could not lex search request.  Found bad tokens ([_1])',
        'Could not lex search request. Found bad tokens ([_1])',

        'I don\'t know how to lex a "[_1]"',
        'I don\'t know how to lex a “[_1]”',

        'Could not parse search request:  [_1]',
        'Could not parse search request: [_1]',

        'Could not parse search request',
        'Could not parse search request',

        q{Don't know how to search for ([_1] [_2] [_3] [_4]): [_5]},
        'Don’t know how to search for ([_1] [_2] [_3] [_4]): [_5]',

        'Search parameter "[_1]" must point to an object, not to a scalar "[_2]"',
        'Search parameter “[_1]” must point to an object, not to a scalar “[_2]”',

        'Search parameter "[_1]" is not an object attribute of "[_2]"',
        'Search parameter “[_1]” is not an object attribute of “[_2]”',
    );

    my %search_messages = (
        'BETWEEN searches may only take two values.  You have [_1]',
        'BETWEEN searches may only take two values. You have [_1]',

        'Odd number of constraints in string search:  "[_1]"',
        'Odd number of constraints in string search “[_1]”',

        'Failed to convert IR to where clause.  This should not happen.',
        'Failed to convert IR to where clause. This should not happen.',

        '[_1] does not support full-text searches',
        '[_1] does not support full-text searches',

        'You cannot do GT or LT type searches with non-contiguous dates',
        'You cannot do GT or LT type searches with non-contiguous dates',

        'You cannot do range searches with non-contiguous dates',
        'You cannot do range searches with non-contiguous dates',

        'BETWEEN search dates must have identical segments defined',
        'BETWEEN search dates must have identical segments defined',

        'All types to an ANY search must match',
        'All types to an ANY search must match',

        'BETWEEN searches must be between identical types. You have ([_1]) and ([_2])',
        'BETWEEN searches must be between identical types. You have ([_1]) and ([_2])',

        'BETWEEN searches should have two terms. You have [_1] term(s).',
        'BETWEEN searches should have two terms. You have [_1] term(s).',

        'PANIC: ANY search data is not an array ref. This should never happen.',
        'PANIC: ANY search data is not an array ref. This should never happen.',

        'PANIC: BETWEEN search data is not an array ref. This should never happen.',
        'PANIC: BETWEEN search data is not an array ref. This should never happen.',

        'PANIC: lookup([_1], [_2], [_3]) returned more than one result.',
        'PANIC: lookup([_1], [_2], [_3]) returned more than one result.',

        'I do not recognize the search parameter "[_1]"',
        'I do not recognize the search parameter “[_1]”',
    );

    %Lexicon = (
        %classes,
        %obj_rel_object_states,
        %lexer_parser_messages,
        %search_messages,

        # Exceptions.
        '[_1] is not a Perl module',
        '[_1] is not a Perl module',

        'Value "[_1]" is not a valid [_2] object',
        'Value “[_1]” is not a valid [_2] object',

        'Value "[_1]" is not a UUID',
        'Value “[_1]” is not a UUID',

        'Value "[_1]" is not a valid operator',
        'Value “[_1]” is not a valid operator',

        'Value "[_1]" is not a valid media type',
        'Value “[_1]” is not a valid media type',

        'Attribute "[_1]" must be defined',
        'Attribute “[_1]” must be defined',

        'Attribute "[_1]" can be set only once',
        'Attribute “[_1]” can be set only once',

        'Localization for "[_1]" not found',
        'Localization for “[_1]” not found',

        'Cannot assign to read-only attribute "[_1]"',
        'Cannot assign to read-only attribute “[_1]”',

        'Argument "[_1]" is not a code reference',
        'Argument “[_1]” is not a code reference',

        'Argument "[_1]" is not a valid [_2] object',
        'Argument “[_1]” is not a valid [_2] object',

        'Value "[_1]" is not a string',
        'Value “[_1]” is not a string',

        'Value "[_1]" is not an integer',
        'Value “[_1]” is not an integer',

        'Value "[_1]" is not a whole number',
        'Value “[_1]” is not a whole number',

        'Value "[_1]" is not a positive integer',
        'Value “[_1]” is not a positive integer',

        'Value "[_1]" is not a valid GTIN',
        'Value “[_1]” is not a valid GTIN',

        'Cannot assign permanent state',
        'Cannot assign permanent state',

        'Required argument "[_1]" to [_2] not found',
        'Required argument “[_1]” to [_2] not found',

        'I could not find the class for key "[_1]"',
        'I could not find the class for key “[_1]”',

        'I could not find the attribute "[_1]" in class "[_2]"',
        'I could not find the attribute “[_1]” in class “[_2]”',

        'No such attribute "[_1]" for [_2]',
        'No such attribute “[_1]” for [_2]',

        'Attribute "[_1]" is not unique',
        'Attribute “[_1]” is not unique',

        'Error saving to data store: [_1]',
        'Error saving to data store: [_1]',

        'I could not load the class "[_1]": [_2]',
        'I could not load the class “[_1]”: [_2]',

        'Abstract class "[_1]" must not be used directly',
        'Abstract class “[_1]” must not be used directly',

        '"[_1]" must be overridden in a subclass',
        '“[_1]” must be overridden in a subclass',

        'Unknown import symbol "[_1]"',
        'Unknown import symbol “[_1]”',

        'Unknown attributes to [_1]: [_2]',
        'Unknown attributes to [_1]: [_2]',

        'Invalid duration string: "[_1]"',
        'Invalid duration string: “[_1]”',

        'No duration string passed to bake()',
        'No duration string passed to bake()',

        '[_1] is compiled with [_2] [_3] but we require version [_4]',
        '[_1] is compiled with [_2] [_3] but we require version [_4]',

        'Cannot find the PostgreSQL createlang executable',
        'Cannot find the PostgreSQL createlang executable',

        '[_1] failed: [_2]', # system(foo) failed: $?
        '[_1] failed: [_2]',

        # PostgreSQL setup exceptions.
        'User "[_1]" cannot connect to either "[_2]" or "[_3]"',
        'User “[_1]” cannot connect to either “[_2]” or “[_3]”',

        'The "[_1]" database does not have PL/pgSQL and user "[_2]" cannot add it',
        'The “[_1]” database does not have PL/pgSQL and user “[_2]” cannot add it',

        'User "[_1]" cannot create a database',
        'User “[_1]” cannot create a database',

        'Cannot find createlang; is it in the PATH?',
        'Cannot find createlang; is it in the PATH?',

        'The [_1] server is version [_2] but we require version [_3]',
        'The [_1] server is version [_2] but we require version [_3]',

        'Looks like someone is accessing "[_1]", so I cannot drop that database',
        'Looks like someone is accessing “[_1]”, so I cannot drop that database',

        # PostgreSQL Setup labels.
        'Can we connect as super user?',
        'Can we connect as super user?',

        'Do we have the proper version of PostgreSQL?',
        'Do we have the proper version of PostgreSQL?',

        'Do we have the proper version of SQLite?',
        'Do we have the proper version of SQLite?',

        'Does the database exist?',
        'Does the database exist?',

        'Can we connect as the user?',
        'Can we connect as the user?',

        'Does it have PL/pgSQL?',
        'Does it have PL/pgSQL?',

        'So create the database.',
        'So create the database.',

        'Can we create a database?',
        'Can we create a database?',

        'Does the template database have PL/pgSQL?',
        'Does the template database have PL/pgSQL?',

        'Does the user exist?',
        'Does the user exist?',

        'So find createlang.',
        'So find createlang.',

        'So build the database and grant permissions.',
        'So build the database and grant permissions.',

        'So create the user.',
        'So create the user.',

        'Add PL/pgSQL to the database.',
        'Add PL/pgSQL to the database.',

        'All done!',
        'All done!',

        'Setup failed.',
        'Setup failed.',

        # SQLite Setup messages.
        'Cannot delete "[_1]": [_2]',
        'Cannot delete "[_1]": [_2]',

        # PostgreSQL Setup messages.
        'Yes'    => 'Yes',
        'No'     => 'No',
        'Okay'   => 'Okay',
        'Failed' => 'Failed',

        # Object::Relation::Meta::Class error.
        'No direct attribute "[_1]" to sort by',
        'No direct attribute “[_1]” to sort by',

        # Object::Relation::Meta errors.
        '[_1] cannot extend [_2] because it inherits from it',
        '[_1] cannot extend [_2] because it inherits from it',

        '[_1] can either extend or mediate another class, but not both',
        '[_1] can either extend or mediate another class, but not both',

        # Object::Relation Attribute labels and tips.
        'The globally unique identifier for this object',
        'The globally unique identifier for this object',

        'Name' => 'Name',
        'The name of this object',
        'The name of this object',

        'Description' => 'Description',
        'The description of this object',
        'The description of this object',

        'The state of this object',
        'The state of this object',

        # Data types.
        'UUID' => 'UUID',
        'State' => 'State',
        'String' => 'String',
        'Whole Number' => 'Whole Number',
        'Version' => 'Version',
        'Operator' => 'Operator',
        'Duration' => 'Duration',
        'DateTime' => 'Date and Time',
        'Media Type' => 'Media Type',
    );
}

1;
__END__

##############################################################################

=head1 Copyright and License

Copyright (c) 2004-2006 Kineticode, Inc. <info@obj_relode.com>

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
