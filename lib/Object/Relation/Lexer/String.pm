package Object::Relation::Lexer::String;

# $Id: String.pm 3076 2006-07-28 17:20:08Z theory $

=head1 Name

Object::Relation::Lexer::String - Lexer for Object::Relation search strings

=head1 Synopsis

  use Object::Relation::Lexer::String qw/string_lexer_stream/;
  my $stream = string_lexer_stream(<<'END_QUERY');
    name => NOT LIKE 'foo%',
    OR (age => GE 21)
  END_QUERY

=head1 Description

This package will lex the a string that uses the
L<Object::Relation::Handle|Object::Relation::Handle> search operators and return a data structure
that a Object::Relation parser can parse.

See L<Object::Relation::Parser::DB|Object::Relation::Parser::DB> for an example.

=cut

use strict;
use warnings;

use version;
our $VERSION = version->new('0.1.0');

use Object::Relation::Exceptions qw/throw_search/;
use HOP::Stream               qw/node iterator_to_stream/;
use HOP::Lexer                qw/make_lexer/;
use Carp                      qw/croak/;

use Exporter::Tidy            default => [qw/string_lexer_stream/];
use Regexp::Common;
use Text::ParseWords;

my $QUOTED  = $RE{quoted};
my $NUM     = $RE{num}{real};
my $VALUE   = qr/(?!\.(?!\d))(?:$QUOTED|$NUM)/;
my $COMPARE = qr/(?:LIKE|GT|LT|GE|LE|NE|MATCH|EQ)/;

my @TOKENS = (
    [
        'VALUE',    # value before keyword
        $VALUE,
        sub { [ $_[0], _strip_quotes( $_[1] ) ] }
    ],
    [ 'UNDEF',     'undef'                            ],

    # compare && keyword before identifier
    [ 'COMPARE',    $COMPARE                          ],
    [ 'KEYWORD',    qr/(?:BETWEEN|AND|OR|ANY|NOT)/    ],
    [ 'IDENTIFIER', qr/[[:alpha:]][.[:word:]]*/       ],
    [ 'WHITESPACE', qr/\s*/,               sub { () } ],
    [ 'OP',         qr/(?:[,\]\[()]|=>)/              ],
);

sub _search_tokens { @TOKENS }

sub _lex {
    my @search = @_;
    my $lexer = make_lexer( sub { shift @search }, @TOKENS );
    my @tokens;
    while ( my $token = $lexer->() ) {
        push @tokens => $token;
    }
    if ( my @bad_tokens = grep { ! ref $_ } @tokens ) {
        throw_search [
            "Could not lex search request.  Found bad tokens ([_1])",
            join ', ' => @bad_tokens
        ];
    }
    return \@tokens;
}

sub _strip_quotes {    # naive
    my $string = shift;
    # Must have the same character at the beginning and end of the string.
    $string =~ s/^(['"`])(.*)\1$/$2/;
    # Strip out escapes.
    $string =~ s/\\\\/\\/g;
    $string =~ s/\\([^\/])/$1/g;
    return $string;
}

=head3 string_lexer_stream;

  my $stream = string_lexer_stream(\@search_parameters);

This function, exported on demand, is the only function publicly useful in
this module. It takes search parameters as described in the
L<Object::Relation::Handle|Object::Relation::Handle> documentation, formatted as a string, and
returns a token stream that Object::Relation parsers should be able to turn into an
intermediate representation.

=cut

sub string_lexer_stream {
    my @input = @_;
    my $input = sub { shift @input };
    return iterator_to_stream( make_lexer( $input, _search_tokens() ) );
}

1;

__END__

##############################################################################

=head1 Copyright and License

Copyright (c) 2004-2006 Kineticode, Inc. <info@obj_relode.com>

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
