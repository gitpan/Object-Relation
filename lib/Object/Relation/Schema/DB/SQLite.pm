package Object::Relation::Schema::DB::SQLite;

# $Id: SQLite.pm 3076 2006-07-28 17:20:08Z theory $

use strict;

use version;
our $VERSION = version->new('0.1.0');

use base 'Object::Relation::Schema::DB';
use Object::Relation::Meta;
use List::Util qw(first);
use Carp;

=head1 Name

Object::Relation::Schema::DB::SQLite - Object::Relation SQLite data store schema generation

=head1 Synopsis

  use Object::Relation::Schema;
  my $kbs = Object::Relation::Schema->new;
  $kbs->generate_to_file($file_name);

=head1 Description

This module generates and outputs to a file the schema information necessary
to create a SQLite data store for a Object::Relation application. See
L<Object::Relation::Schema|Object::Relation::Schema> and
L<Object::Relation::Schema::DB|Object::Relation::Schema::DB> for more information.

=cut

##############################################################################

##############################################################################
# Instance Interface
##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 column_type

  my $type = $kbs->column_type($attr);

Pass in a Object::Relation::Meta::Attribute::Schema object to get back the SQLite
column type to be used for the attribute. The column types are optimized for
the best correspondence between the attribute types and the types supported by
SQLite (relatively speaking, of course, since SQLite's data types are actually
dynamic).

=cut

my %types = (
    attribute  => 'TEXT',
    binary     => 'BLOB',
    boolean    => 'SMALLINT',
    datetime   => 'DATETIME',
    duration   => 'TEXT',
    gtin       => 'INTEGER',
    integer    => 'INTEGER',
    media_type => 'TEXT',
    operator   => 'TEXT',
    posint     => 'INTEGER',
    state      => 'INTEGER',
    string     => 'TEXT COLLATE nocase',
    uuid       => 'TEXT',
    version    => 'TEXT',
    whole      => 'INTEGER',
);

sub column_type {
    my ($self, $attr) = @_;
    my $type = $attr->type;
    return $types{$type} if $types{$type};
    croak "No such data type: $type" unless Object::Relation::Meta->for_key($type);
    return "INTEGER";
}

##############################################################################

=head3 index_for_attr

  my $index = $kbs->index_for_attr($class, $attr);

Returns the SQL that declares an SQL index. This implementation overrides that
in L<Object::Relation::Schema::DB|Object::Relation::Schema::DB> to remove the
C<UNIQUE> keyword from the declaration if the attribute in question is unique
but not distinct. The difference is that a unique attribute is unique only
relative to the C<state> attribute. A unique attribute can have more than one
instance of a given value as long as no more than one of them also has a state
greater than -1. For SQLite, this is handled by triggers.

=cut

sub index_for_attr {
    my ($self, $class, $attr) = @_;
    my $sql = $self->SUPER::index_for_attr($class => $attr);
    return $sql if $attr->distinct || !$attr->unique;
    # UNIQUE is handled by a constraint.
    $sql =~ s/UNIQUE\s+//;
    return $sql;
}

##############################################################################

=head3 constraints_for_class

  my @constraint_sql = $kbs->constraints_for_class($class);

Returns the SQL statements to create all of the constraints for the class
described by the Object::Relation::Meta::Class::Schema object passed as the sole
argument.

The constraint statements returned may include one or more of the following:

=over

=item *

A trigger to ensure that the value of a C<state> attribute is a valid state.

=item *

"Once triggers", which prevent a value from being changed in a column after
the first time it has been set to a non-C<NULL> value.

=item *

"Boolean triggers", which ensures that the value of a boolean column is either
0 or 1.

=item *

A foreign key constraint from the primary key column to the table for a
concrete parent class.

=item *

Foreign key constraints to the tables for contained (referenced) objects.

=item *

"Unique triggers," which ensure that the value of a unique column is indeed
unique.

=back

=cut

sub constraints_for_class {
    my ($self, $class) = @_;

    # Start with any state, boolean, once, and unique triggers.
    my @cons = (
        $self->state_trigger(       $class ),
        $self->numeric_triggers(    $class ),
        $self->boolean_triggers(    $class ),
        $self->once_triggers(       $class ),
        $self->unique_triggers(     $class ),
        $self->operator_triggers(   $class ),
        $self->media_type_triggers( $class ),
        $self->attribute_triggers(  $class ),
        $self->version_triggers(    $class ),
        $self->gtin_triggers(       $class ),
   );

    # Add FK constraint for subclasses from id column to the parent table.
    if (my $parent = $class->parent) {
        push @cons, $self->_generate_fk($class, 'id', $parent)
    }

    # Add foreign keys for any attributes that reference other objects.
    for my $attr ($class->ref_attributes) {
        next if $attr->acts_as;
        my $ref = $attr->references or next;
        push @cons, $self->_generate_fk($class, $attr, $ref);
    }
    push @cons, $self->_generate_collection_constraints( $class );
    return @cons;
}

##############################################################################

=head3 state_trigger

  my @state_triggers = $kbs->state_trigger($class);

Returns SQLite triggers to validate that the value of a state column in the
table representing the contents of the class represented by the
Object::Relation::Meta::Class::Schema object passed as the sole argument. If the class
does not have a state attribute (because it inherits the state from a concrete
parent class), C<state_trigger()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub state_trigger {
    my ($self, $class) = @_;
    $self->_domain_triggers($class, state => '%s NOT BETWEEN -1 AND 2');
}

##############################################################################

=head3 numeric_triggers

  my @numeric_triggers = $kbs->numeric_triggers($class);

Returns the SQLite triggers to validate the values of any numeric type
attributes (whole numbers or positive integers) in the class. If the class has
no numeric attributes C<numeric_triggers()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub numeric_triggers {
    my ($self, $class) = @_;
    return
        $self->_domain_triggers($class, whole  => '%s < 0'),
        $self->_domain_triggers($class, posint => '%s <= 0' ),
    ;
}

##############################################################################

=head3 boolean_triggers

  my @boolean_triggers = $kbs->boolean_triggers($class);

Returns the SQLite triggers to validate the values of any boolean type
attributes in the class are stored as either 0 or 1 (zero or one) in their
columns in the database. If the class has no boolean attributes
C<boolean_triggers()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub boolean_triggers {
    my ($self, $class) = @_;
    $self->_domain_triggers($class, boolean => '%s NOT IN (1, 0)');
}

##############################################################################

=head3 once_triggers_sql

  my $once_triggers_sql_body = $kbs->once_triggers_sql(
    $key, $attr, $table, $constraint,
  );

This method is called by C<once_triggers()> to generate database specific
rules, functions, triggers, etc., to ensure that a column, once set to a
non-null value, can never be changed.

=cut

sub once_triggers_sql {
    my ($self, $key, $attr, $table, $when) = @_;
    my $col = $attr->column;
    return "CREATE TRIGGER ck_$key\_$col\_once\n"
          . "BEFORE UPDATE ON $table\n"
          . "FOR EACH ROW BEGIN\n"
        . qq{    SELECT RAISE(ABORT, 'value of $key.$col cannot be changed')\n}
          . "    WHERE  $when;\n"
          . "END;\n";
}

##############################################################################

=head3 unique_triggers

  my @unique_triggers = $kbs->unique_triggers($class);

Returns the SQLite triggers to validate the values of any "unique" attributes
in the table representing the contents of the class represented by the
Object::Relation::Meta::Class::Schema object passed as the sole argument. If the class
has no unique attributes C<unique_triggers()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub unique_triggers {
    my ($self, $class) = @_;
    my @uniques = grep { $_->unique && !$_->distinct } $class->table_attributes
        or return;
    my $table       = $class->table;
    my $key         = $class->key;
    my $state_class = first { grep { $_->name eq 'state'} $_->table_attributes }
        reverse( $class->parents );
    my @trigs;
    if (!$state_class || $state_class eq $class) {
        # The unique cols are in the same table as state. Simple triggers.
        for my $attr (@uniques) {
            my $col = $attr->column;
            push @trigs,
                "CREATE TRIGGER cki_$key\_$col\_unique\n"
              . "BEFORE INSERT ON $table\n"
              . "FOR EACH ROW BEGIN\n"
              . "    SELECT RAISE (ABORT, 'column $col is not unique')\n"
              . "    WHERE  (\n"
              . "               SELECT 1\n"
              . "               FROM   $table\n"
              . "               WHERE  state > -1 AND $col = NEW.$col\n"
              . "               LIMIT  1\n"
              . "           );\n"
              . "END;\n",

                "CREATE TRIGGER cku_$key\_$col\_unique\n"
              . "BEFORE UPDATE ON $table\n"
              . "FOR EACH ROW BEGIN\n"
              . "    SELECT RAISE (ABORT, 'column $col is not unique')\n"
              . "    WHERE  (NEW.$col <> OLD.$col OR (\n"
              . "                NEW.state > -1 AND OLD.state < 0\n"
              . "            )) AND (\n"
              . "               SELECT 1 from $table\n"
              . "               WHERE  id <> NEW.id\n"
              . "                      AND $col = NEW.$col\n"
              . "                      AND state > -1\n"
              . "               LIMIT 1\n"
              . "           );\n"
              . "END;\n";
        }
    } else {
        # The state attribute is in a different table. Complex triggers.
        my $parent_table = $state_class->table;
        for my $attr (@uniques) {
            my $col = $attr->column;
            push @trigs,
                "CREATE TRIGGER cki_$key\_$col\_unique\n"
              . "BEFORE INSERT ON $table\n"
              . "FOR EACH ROW BEGIN\n"
              . "    SELECT RAISE (ABORT, 'column $col is not unique')\n"
              . "    WHERE  (\n"
              . "               SELECT 1\n"
              . "               FROM   $parent_table, $table\n"
              . "               WHERE  $parent_table.id = $table.id\n"
              . "                      AND $parent_table.state > -1\n"
              . "                      AND $table.$col = NEW.$col\n"
              . "               LIMIT  1\n"
              . "           );\n"
              . "END;\n",
                "CREATE TRIGGER cku_$key\_$col\_unique\n"
              . "BEFORE UPDATE ON $table\n"
              . "FOR EACH ROW BEGIN\n"
              . "    SELECT RAISE (ABORT, 'column $col is not unique')\n"
              . "    WHERE  NEW.$col <> OLD.$col AND (\n"
              . "               SELECT 1\n"
              . "               FROM   $parent_table, $table\n"
              . "               WHERE  $parent_table.id = $table.id\n"
              . "                      AND $parent_table.id <> NEW.id\n"
              . "                      AND $parent_table.state > -1\n"
              . "                      AND $table.$col = NEW.$col\n"
              . "               LIMIT  1\n"
              . "           );\n"
              . "END;\n",
                "CREATE TRIGGER ckp_$key\_$col\_unique\n"
              . "BEFORE UPDATE ON $parent_table\n"
              . "FOR EACH ROW BEGIN\n"
              . "    SELECT RAISE (ABORT, 'column $col is not unique')\n"
              . "    WHERE  NEW.state > -1 AND OLD.state < 0\n"
              . "           AND (SELECT 1 FROM $table WHERE id = NEW.id)\n"
              . "           AND (\n"
              . "               SELECT COUNT($col)\n"
              . "               FROM   $table\n"
              . "               WHERE  $col = (\n"
              . "                   SELECT $col FROM $table\n"
              . "                   WHERE id = NEW.id\n"
              . "               )\n"
              . "           ) > 1;\n"
              . "END;\n";
        }
    }
    return @trigs;
}

##############################################################################

=head3 operator_triggers

  my @operator_triggers = $kbs->operator_triggers($class);

Returns SQLite triggers to validate that the value of a operator column in the
table representing the contents of the class represented by the
Object::Relation::Meta::Class::Schema object passed as the sole argument. If the class
does not have a operator attribute (because it inherits the operator from a concrete
parent class), C<operator_trigger()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub operator_triggers {
    my ($self, $class) = @_;
    $self->_domain_triggers(
        $class,
        'operator',
        '%s NOT IN (' . join(
            ', ', map { "'$_'"}
                qw(== != eq ne =~ !~ > < >= <= gt lt ge le)
            ) . ')',
    );
}

##############################################################################

=head3 media_type_triggers

  my @media_type_triggers = $kbs->media_type_triggers($class);

Returns SQLite triggers to validate that the value of a media_type column in
the table representing the contents of the class represented by the
Object::Relation::Meta::Class::Schema object passed as the sole argument. If the class
does not have a media_type attribute (because it inherits the media_type from
a concrete parent class), C<media_type_trigger()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub media_type_triggers {
    my ($self, $class) = @_;
    $self->_domain_triggers(
        $class,
        'media_type',
        q{%s NOT REGEXP '^\\w+/\\w+$'}
    );
}

##############################################################################

=head3 attribute_triggers

  my @attribute_triggers = $kbs->attribute_triggers($class);

Returns SQLite triggers to validate that the value of a attribute column in
the table representing the contents of the class represented by the
Object::Relation::Meta::Class::Schema object passed as the sole argument. If the class
does not have a attribute attribute (because it inherits the attribute from
a concrete parent class), C<attribute_trigger()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub attribute_triggers {
    my ($self, $class) = @_;
    $self->_domain_triggers(
        $class,
        attribute => q{%s NOT REGEXP '^\\w+\.\\w+$'}
    );
}

##############################################################################

=head3 version_triggers

  my @version_triggers = $kbs->version_triggers($class);

Returns SQLite triggers to validate that the value of a version column in the
table representing the contents of the class represented by the
Object::Relation::Meta::Class::Schema object passed as the sole argument. If the class
does not have a version attribute (because it inherits the version from a
concrete parent class), C<version_trigger()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub version_triggers {
    my ($self, $class) = @_;
    $self->_domain_triggers(
        $class,
        version => q{%s NOT REGEXP '^v?\\d[\\d._]+$'}
    );
}

##############################################################################

=head3 gtin_triggers

  my @gtin_triggers = $kbs->gtin_triggers($class);

Returns SQLite triggers to validate that the value of a gtin column in the
table representing the contents of the class represented by the
Object::Relation::Meta::Class::Schema object passed as the sole argument. If the class
does not have a gtin attribute (because it inherits the gtin from a
concrete parent class), C<gtin_trigger()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub gtin_triggers {
    my ($self, $class) = @_;
    # Force string context so that Perl doesn't truncate the integer.
    $self->_domain_triggers(
        $class,
        gtin => 'NOT isa_gtin(CAST(%s AS TEXT))'
    );
}

##############################################################################

=head3 insert_for_class

  my $insert_trigger_sql = $kbs->insert_for_class($class);

Returns an SQLite trigger that manages C<INSERT> statements executed against
the view for the class. The trigger ensures that the C<INSERT> statement
updates the table for the class as well as any parent classes. Extended and
mediated objects are also inserted or updated as appropriate, but other
contained objects are ignored, and should be inserted or updated separately.

=cut

sub insert_for_class {
    my ($self, $class) = @_;
    my $key = $class->key;

    # Output the INSERT trigger.
    my $sql = "CREATE TRIGGER insert_$key\n"
      . "INSTEAD OF INSERT ON $key\nFOR EACH ROW BEGIN";
    my $pk = '';

    # Output the insert statements for all parent tables.
    for my $impl (reverse($class->parents)) {
        $sql .= $self->_insert_into_table($impl, $pk);
        $pk ||= 'last_insert_rowid(), ';
    }

    if (my $extends = $class->extends || $class->mediates) {
        # We may need to update the extended table. Trickier trigger.
        my @ext_attrs = grep {
            $_->persistent && $_->delegates_to || '' eq $extends
        } $class->attributes;

        $sql .= $self->_extended_insert   ( $class, $extends, \@ext_attrs )
              . $self->_extended_insert_up( $class, $extends, \@ext_attrs )
              . $self->_extending_insert  ( $class, $extends, \@ext_attrs );
    } else {
        # All is normal.
        $sql .= $self->_insert_into_table($class, $pk);
    }

    return $sql . "END;\n";

}

##############################################################################

=head3 update_for_class

  my $update_trigger_sql = $kbs->update_for_class($class);

Returns an SQLite trigger that manages C<UPDATE> statements executed against
the view for the class. The trigger ensures that the C<UPDATE> statement
updates the table for the class as well as any parent classes. Extended and
mediated objects are also updated, but other contained objects are ignored,
and should be updated separately.

=cut

sub update_for_class {
    my ($self, $class) = @_;
    my $key = $class->key;
    my $sql .= "CREATE TRIGGER update_$key\n"
      . "INSTEAD OF UPDATE ON $key\nFOR EACH ROW BEGIN";

    if (my $extends = $class->extends || $class->mediates) {
        # We may need to update the extended table. Trickier trigger.
        $sql .= $self->_extended_update( $class, $extends )
              . $self->_update_table(    $class           );
    }

    else {
        # All is normal.
        $sql .= $self->_update_table($class);
    }

    return $sql . "END;\n";
}

##############################################################################

=head3 delete_for_class

  my $delete_rule_sql = $kbs->delete_for_class($class);

Returns an SQLite rule that manages C<DELETE> statements executed against the
view for the class. Deletes simply pass through to the underlying table for
the class; parent object records are left in tact.

=cut

sub delete_for_class {
    my ($self, $class) = @_;
    my $key = $class->key;
    my $table = $class->table;
    # Output the DELETE rule.
    return "CREATE TRIGGER delete_$key\n"
      . "INSTEAD OF DELETE ON $key\n"
      . "FOR EACH ROW BEGIN\n"
      . "  DELETE FROM $table\n"
      . "  WHERE  id = OLD.id;\n"
      . "END;\n";
}

##############################################################################

=head3 extras_for_class

  my @sql = $kbs->extras_for_class($class)

Returns a list of any extra SQL statements that need to be executed in order
to adequately represent a class in the database. By default, there are none,
so this method returns none. But subclasses may override it to provide extra
functionality.

=cut

sub extras_for_class {
    my ($self, $class) = @_;
    my @attrs = $class->collection_attributes;
    return unless @attrs;
    my $main_key = $class->key;
    my @triggers;
    for my $attr(@attrs) {
        my $view     = $attr->collection_view;
        my $coll_key = $attr->name;
        for my $spec (
            ['insert', ' into'],
            ['update', ''],
            ['delete', ' from'],
        ) {
            my $funcs = $spec->[0] eq 'delete'
                ? "$view\_del($main_key\_id, $coll_key\_ids) "
                . "or $view\_clear($main_key\_id)"
                : "$view\_add($main_key\_id, $coll_key\_ids) "
                . "or $view\_set($main_key\_id, $coll_key\_ids)";
            push @triggers,
                "CREATE TRIGGER $view\_$spec->[0]\n"
              . "INSTEAD OF \U$spec->[0]\E ON $view\n"
              . "BEGIN\n"
              . "    SELECT RAISE(ABORT, 'Please use $funcs "
              . "to $spec->[0]$spec->[1] the $view collection');\n"
              . "END;\n";
          }
    }
    return @triggers;
}

##############################################################################

=begin private

=head1 Private Interface

=head2 Private Instance Methods

=head3 _generate_fk

  my $fk_trigger_sql = $kbs->_generate_fk($class, $attr, $fk_class);

=cut

sub _generate_fk {
    my ($self, $class, $attr, $fk_class) = @_;
    my $key      = $class->key;
    my $table    = $class->table;
    my $fk_key   = $fk_class->key;
    my $fk_table = $fk_class->table;
    my ($fk, $col, $cascade) = ref $attr
      ? ($attr->foreign_key, $attr->column, uc $attr->on_delete eq 'CASCADE')
      : ($class->foreign_key, 'id', 1);
    my $null = ref $attr && $attr->required ? '' : "NEW.$col IS NOT NULL AND ";
    return $self->_generate_fk_sql(
         $fk,
         $fk_table,
         $col,
         $table,
         $null,
         $cascade
    );
}

##############################################################################

=head3 _generate_fk_sql

 my $sql = $self->_generate_fk_sql(
     $fk,
     $fk_table,
     $col,
     $table,
     $null,
     $cascade
 );

This method returns the actual SQL required to generate foreign key
constraints for SQLite. There is very little logic in this method. Instead, it
takes the data and creates the SQL. The primary logic to assemble the data for
this method is in C<_generate_fk>.

The reason these methods are separate is because some tables (such as those
created by C<has_many> relationships) are not represented by C<Object::Relation::Meta>
classes and thus do not have the direct introspective capability necessary to
assemble the arguments dynamically.

=cut

sub _generate_fk_sql {
    my ( $self, $fk, $fk_table, $col, $table, $null, $cascade ) = @_;
    # We actually have three different triggers for each foreign key, so we
    # have to give each one a slightly different name.
    (my $fki = $fk) =~ s/_/i_/;
    (my $fku = $fk) =~ s/_/u_/;
    (my $fkd = $fk) =~ s/_/d_/;

    return (qq{CREATE TRIGGER $fki
BEFORE INSERT ON $table
FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'insert on table "$table" violates foreign key constraint "$fk"')
    WHERE  $null(SELECT id FROM $fk_table WHERE id = NEW.$col) IS NULL;
END;
},

      qq{CREATE TRIGGER $fku
BEFORE UPDATE ON $table
FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'update on table "$table" violates foreign key constraint "$fk"')
    WHERE  $null(SELECT id FROM $fk_table WHERE id = NEW.$col) IS NULL;
END;
},
      ($cascade
         ? qq{CREATE TRIGGER $fkd
AFTER DELETE ON $fk_table
FOR EACH ROW BEGIN
  DELETE from $table WHERE $col = OLD.id;
END;
}
         : qq{CREATE TRIGGER $fkd
BEFORE DELETE ON $fk_table
FOR EACH ROW BEGIN
    SELECT RAISE(ABORT, 'delete on table "$fk_table" violates foreign key constraint "$fk"')
    WHERE  (SELECT $col FROM $table WHERE $col = OLD.id) IS NOT NULL;
END;
})
  );
}

sub _generate_collection_constraints {
    my ($self, $class) = @_;
    my @attributes = $class->collection_attributes;
    return unless @attributes;
    my @constraints;
    my $main_key   = $class->key;
    my $main_table = $class->table;
    foreach my $attr (@attributes) {
        my $table      = $attr->collection_table;
        my $view       = $attr->collection_view;
        my $coll_table = $attr->collection_of->table;
        my $coll_key   = $attr->name;
        my $cascade  = 1;
        my $null     = '';
        push @constraints,
            $self->_generate_fk_sql(
                "fk_$view\_$main_key\_id",
                $main_table,
                "$main_key\_id",
                $table,
                $null,
                $cascade,
            ),
            $self->_generate_fk_sql(
                "fk_$view\_$coll_key\_id",
                $coll_table,
                "$coll_key\_id",
                $table,
                $null,
                $cascade,
            );

        if ($attr->relationship eq 'has_many') {
            push @constraints, qq{CREATE TRIGGER $view\_cascade
AFTER DELETE ON $table
FOR EACH ROW BEGIN
    DELETE FROM $coll_table WHERE id = OLD.$coll_key\_id;
END;
}
        }
    }
    return @constraints;
}

##############################################################################

=head3 _insert_into_table

  my $sql = $kbs->_insert_into_table($class, $pk);

Used by C<insert_for_class()>, this method is used to generate the C<INSERT>
statement used by a trigger to C<INSERT> into tables when inserting into a
C<VIEW> that represents a class. The only classes for which it is not used are
those that extend another class.

=cut

sub _insert_into_table {
    my ($self, $class, $pk) = @_;
    my $table = $class->table;
    return "\n  INSERT INTO $table ("
          . ($pk ? 'id, ' : '')
          . join(', ', map { $_->column } $class->table_attributes )
          . ")\n  VALUES ($pk"
          . join(', ', map {
              if ($_->type eq 'uuid') {
                  'COALESCE(NEW.' . $_->view_column . ', UUID_V4())';
              } elsif (my $def = $self->column_default($_)) {
                  $def =~ s/DEFAULT\s+//;
                  'COALESCE(NEW.' . $_->view_column . ", $def)";
              } else {
                  'NEW.' . $_->view_column;
              }
          } $class->table_attributes)
          . ");\n";
}

##############################################################################

=head3 _extended_insert

  my $sql = $kbs->_extended_insert($class, $extends, \@ext_attrs);

This method, called by C<insert_for_class()>, returns SQL to be used in the
C<INSERT> trigger on a C<VIEW> for an extended class. The SQL returned is one
or more C<INSERT>s into the table or tables of the extended class.

=cut

sub _extended_insert {
    my ($self, $class, $extends, $ext_attrs) = @_;
    my $pk      = '';
    my $sql     = '';

    # Output the insert statements for all parent tables.
    # We can't just use the view becausee last_insert_rowid() doesn't return IDs
    # inserted by triggers. See http://sqlite.org/cvstrac/tktview?tn=1191.
    for my $impl (reverse($extends->parents), $extends) {
        $sql .= $self->_extended_insert_into_table(
            $extends,
            $impl,
            $ext_attrs,
            $pk
        );
        $pk ||= 'last_insert_rowid(), ';
    }
    return $sql;
}

##############################################################################

=head3 _extended_insert_into_table

  my $sql = $kbs->_extended_insert_into_table(
      $top_class,
      $class,
      $ext_attrs,
      $pk
  );

This method is called repeatedly by C<_extended_insert()> to generate and
return C<INSERT> statements for the extended class table and all of it is
parents (if any). The $pk argument should be an empty string the first time
it's called, and 'last_insert_rowid(), ' thereafter, so that the primary key
of the root class is used as the primary key for all child classes.

=cut

sub _extended_insert_into_table {
    my ($self, $top_class, $impl, $ext_attrs, $pk) = @_;
    my $ext_key = $top_class->key;
    my $table   = $impl->table;
    my %attrs   = map { $_ => 1 } $impl->table_attributes;

    return "\n  INSERT INTO $table ("
        . ($pk ? 'id, ' : '')
        . join(', ', map { $_->column } $impl->table_attributes )
        . ")\n  SELECT $pk"
        . join(', ', map {
            if ($_->type eq 'uuid') {
                'COALESCE(NEW.' . $_->view_column . ', UUID_V4())';
            } elsif (my $def = $self->column_default($_)) {
                $def =~ s/DEFAULT\s+//;
                'COALESCE(NEW.' . $_->view_column . ", $def)";
            } else {
                'NEW.' . $_->view_column;
            }
        } grep { $attrs{$_->acts_as} } @$ext_attrs)
        . "\n  WHERE  NEW.$ext_key\__id IS NULL;\n";
}

##############################################################################

=head3 _extended_insert_up

  my $sql = $kbs->_extended_insert_up($class, $extends, \@ext_attrs);

This method, called by C<insert_for_class()>, returns SQL to be used in the
C<INSERT> trigger on a C<VIEW> for an extended class. The SQL returned is an
C<UPDATE> of the C<VIEW> of the extended class.

=cut

sub _extended_insert_up {
    my ($self, $class, $extends, $ext_attrs) = @_;
    my $ext_key   = $extends->key;

    return "\n  UPDATE $ext_key\n  SET    "
        . join(
            ', ',
            map {
                my $col = $_->acts_as->view_column;
                sprintf "%s = COALESCE(NEW.%s, %s)",
                    $col, $_->view_column, $col;
            }
            grep { !$_->once } @$ext_attrs
        )
        . "\n  WHERE  NEW.$ext_key\__id IS NOT NULL "
        . "AND id = NEW.$ext_key\__id;\n";
}

##############################################################################

=head3 _extending_insert

  my $sql = $kbs->_extending_insert($class, $extends, \@ext_attrs);

This method, called by C<insert_for_class()>, returns SQL to be used in the
C<INSERT> trigger on a C<VIEW> for an extended class. The SQL returned is an
C<INSERT> into the table of the extending class.

=cut

sub _extending_insert {
    my ($self, $class, $extends, $ext_attrs) = @_;
    my $ext_key  = $extends->key;
    my $table = $class->table;
    return "\n  INSERT INTO $table ("
        . join(', ', map { $_->column } $class->table_attributes )
        . ")\n  VALUES ("
        . join(', ', map {
            if ($_->type eq 'uuid') {
                'COALESCE(NEW.' . $_->view_column . ', UUID_V4())';
            } elsif (my $def = $self->column_default($_)) {
                $def =~ s/DEFAULT\s+//;
                'COALESCE(NEW.' . $_->view_column . ", $def)";
            } elsif ($_->type eq $ext_key) {
                'COALESCE(NEW.' . $_->view_column . ", last_insert_rowid())";
            } else {
                'NEW.' . $_->view_column;
            }
        } $class->table_attributes)
        . ");\n";
}

##############################################################################

=head3 _update_table

  my $sql = $kbs->_update_table($class);

Used by C<_update_for_class()>, this method is used to generate the C<UPDATE>
statements used by a trigger to C<UPDATE> tables when updating a C<VIEW> that
represents a class. The only classes for which it is not used are those that
extend another class.

=cut

sub _update_table {
    my ($self, $class) = @_;
    my $sql = '';
    for my $impl (reverse ($class->parents), $class) {
        my $table = $impl->table;
        $sql .= "\n  UPDATE $table\n  SET    "
          . join(
              ', ',
              map { sprintf "%s = NEW.%s", $_->column, $_->view_column }
              grep { !$_->once } $impl->table_attributes
            )
          . "\n  WHERE  id = OLD.id;\n";
    }
    return $sql;

}

##############################################################################

=head3 _extended_update

  my $sql = $kbs->_extended_update($class, $extended);

Used by C<_update_for_class()>, this method is used to generate the C<UPDATE>
statements used by a trigger to C<UPDATE> tables when updating a C<VIEW> that
represents a class that extends another class.

=cut

sub _extended_update {
    my ($self, $class, $extended) = @_;
    my $ext_key  = $extended->key;

    return "\n  UPDATE $ext_key\n  SET    "
        . join(
            ', ',
            map  {
                sprintf "%s = NEW.%s", $_->acts_as->view_column, $_->view_column
            }
            grep {
                     $_->persistent
                 && !$_->once
                 &&  $_->delegates_to || '' eq $extended
            } $class->attributes
        )
      . "\n  WHERE  id = OLD.$ext_key\__id;\n";
}

##############################################################################

=head3 _domain_triggers

  my @trigger_sql = $self->_domain_triggers($class, $type => $check_sql);

This method is used to create triggers for domain constraints. That is, it
create triggers to constrain the values of columns of particular data types.
The data types that need these triggers tend to correspond to those for which
C<DOMAIN>s are created in Object::Relation::Schema::DB::Pg; hence the name of
this meethod.

For example, the constraint triggers for the C<state> data type an be
constructed for a given clas like so:

  my @trigs = $self->_domain_triggers(
      $class,
      state => '%s NOT BETWEEN -1 AND 2'
  );

This makes it much easier to add new data types, whild maintenance of the code
to enforce them in the SQLite database is all in one place.

=cut

sub _domain_triggers {
    my ($self, $class, $domain, $check) = @_;
    my @attributes = grep { $_->type eq $domain} $class->table_attributes
      or return;
    my $table = $class->table;
    my $key = $class->key;
    my @trigs;
    for my $attr (@attributes) {
        my $col   = $attr->column;
        # If it's not required, it's allowed to be NULL, so don't check NULLs.
        my $where = ($attr->required ? '' : "NEW.$col IS NOT NULL AND ")
            . sprintf $check, "NEW.$col";

        push @trigs,
            "CREATE TRIGGER cki_$key\_$col\n"
          . "BEFORE INSERT ON $table\n"
          . "FOR EACH ROW BEGIN\n"
          . "    SELECT RAISE(ABORT, 'value for domain $domain violates "
          .                        qq{check constraint "ck_$domain"')\n}
          . "    WHERE  $where;\n"
          . "END;\n",
            "CREATE TRIGGER cku_$key\_$col\n"
          . "BEFORE UPDATE OF $col ON $table\n"
          . "FOR EACH ROW BEGIN\n"
          . "    SELECT RAISE(ABORT, 'value for domain $domain violates "
          .                        qq{check constraint "ck_$domain"')\n}
          . "    WHERE  $where;\n"
          . "END;\n";
    }
    return @trigs;
}

1;
__END__

##############################################################################

=end private

=head1 Copyright and License

Copyright (c) 2004-2006 Kineticode, Inc. <info@obj_relode.com>

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
