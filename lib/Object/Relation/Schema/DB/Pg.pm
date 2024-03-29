package Object::Relation::Schema::DB::Pg;

# $Id: Pg.pm 3076 2006-07-28 17:20:08Z theory $

use strict;

use version;
our $VERSION = version->new('0.1.0');

use base 'Object::Relation::Schema::DB';
use List::Util qw(first);
use Carp;

=head1 Name

Object::Relation::Schema::DB::Pg - Object::Relation PostgreSQL data store schema generation

=head1 Synopsis

  use Object::Relation::Schema;
  my $kbs = Object::Relation::Schema->new;
  $kbs->generate_to_file($file_name);

=head1 Description

This module generates and outputs to a file the schema information necessary
to create a PostgreSQL data store for a Object::Relation application. See
L<Object::Relation::Schema|Object::Relation::Schema> and
L<Object::Relation::Schema::DB|Object::Relation::Schema::DB> for more information.

=cut

##############################################################################
# Instance Interface
##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 sequences_for_class

  my @sequence_sql = $kbs->sequences_for_class($class);

This method takes a class object and returns a C<CREATE SEQUENCE> statement
for the class if it has no parent classes, as well as sequences for any
collections that the class contains.

=cut

sub sequences_for_class {
    my ($self, $class) = @_;
    return if $class->parents;
    my $key = $class->key;
    return "CREATE SEQUENCE seq_$key;\n";
}

##############################################################################

=head3 format_coll_table

  my $table = $kbs->collection_table($table, $has_key, $had_key);

This method overrides that in the parent class in order not to have the
primary key embedded in the table declaration. This is because we want named
primary keys in PostgreSQL.

=cut

sub format_coll_table {
    my ($self, $table, $has_key, $had_key) = @_;
    return <<"    END_SQL";
CREATE TABLE $table (
    $has_key\_id INTEGER NOT NULL,
    $had_key\_id INTEGER NOT NULL,
    $had_key\_order SMALLINT NOT NULL
);
    END_SQL
}

##############################################################################

=head3 column_type

  my $type = $kbs->column_type($attr);

Pass in a Object::Relation::Meta::Attribute::Schema object to get back the PostgreSQL
column type to be used for the attribute. The column types are optimized for
the best correspondence between the attribute types and the types supported by
PostgreSQL, plus data domains where appropriate (e.g., the "state" column type
is defined by a data domain defined by a statement returned by
C<setup_code()>).

=cut

my %types = (
    attribute  => 'ATTRIBUTE',
    binary     => 'BYTEA',
    boolean    => 'BOOLEAN',
    duration   => 'INTERVAL',
    datetime   => 'TIMESTAMP',
    gtin       => 'GTIN',
    integer    => 'INTEGER',
    media_type => 'MEDIA_TYPE',
    operator   => 'OPERATOR',
    posint     => 'POSINT',
    state      => 'STATE',
    string     => 'TEXT',
    uuid       => 'UUID',
    version    => 'VERSION',
    whole      => 'WHOLE',
);

sub column_type {
    my ($self, $attr) = @_;
    return 'INTEGER' if $attr->references;
    my $type = $attr->type;
    return $types{$type} if $types{$type};
    croak "No such data type: $type" unless Object::Relation::Meta->for_key($type);
}

##############################################################################

=head3 pk_column

  my $pk_sql = $kbs->pk_column($class);

Returns the SQL statement to create the primary key column for the table for
the Object::Relation::Meta::Class::Schema object passed as its sole argument. If the
class has no concrete parent class, the primary key column expression will set
up a C<DEFAULT> statement to get its value from the sequence created for the
class. Otherwise, it will be be a simple column declaration. The primary key
constraint is actually returned by C<constraints_for_class()>, and so is not
included in the expression returned by C<pk_column()>.

=cut

sub pk_column {
    my ($self, $class) = @_;
    return 'id INTEGER NOT NULL' if $class->parent;
    my $key = $class->key;
    return "id INTEGER NOT NULL DEFAULT NEXTVAL('seq_$key')";
}

##############################################################################

=head3 column_default

  my $default_sql = $kbs->column_default($attr);

Pass in a Object::Relation::Meta::Attribute::Schema object to get back the default
value expression for the column for the attribute. Returns C<undef> (or an
empty list) if there is no default value on the column. Otherwise, it returns
the default value expression. Overrides the parent method to return
PostgreSQL-specific default expressions where appropriate (e.g., for boolean)
columns.

=cut

sub column_default {
    my ($self, $attr) = @_;
    my $type = $attr->type;

    if ($type eq 'boolean') {
        my $def = $attr->default;
        return unless defined $def;
        return $def ? 'DEFAULT true' : 'DEFAULT false';
    }

    elsif ($type eq 'uuid') {
        return 'DEFAULT UUID_V4()';
    }

    return $self->SUPER::column_default($attr)
}

##############################################################################

=head2 column_reference

  my $ref_sql = $kbs->column_reference($attr);

Overrides the parent method to return C<undef> (or an empty list). This is
because the column foreign key constraints are named and returned by
C<constraints_for_class()>, instead.

=cut

sub column_reference { return }

##############################################################################

=head3 index_for_attr

  my $index = $kbs->index_for_attr($class, $attr);

Returns the SQL that declares an SQL index. This implementation overrides that
in L<Object::Relation::Schema::DB|Object::Relation::Schema::DB> to change it to a
partial unique index or to remove the C<UNIQUE> keyword if the attribute is
unique but not distinct. The difference is that a unique attribute is unique
only relative to the C<state> attribute. A unique attribute can have more than
one instance of a given value as long as no more than one of them also has a
state greater than -1. In PostgreSQL, this is handled by a partial unique
index if the attribute and the state attribute are in the same table, or by
triggers if they are in different tables (due to inheritance).

=cut

sub index_for_attr {
    my ($self, $class, $attr) = @_;
    my $sql = $self->SUPER::index_for_attr($class => $attr);
    return $sql unless $attr->unique && !$attr->distinct;

    my $state_class = first {
        grep { $_->name eq 'state'} $_->table_attributes
    } $class, reverse( $class->parents );

    if ($state_class eq $class) {
        # Create a partial unique index.
        $sql =~ s/;\n$/ WHERE state > -1;\n/;
    }

    # If state in a parent class, we'll have to use a constraint, instead.
    else {
        $sql =~ s/UNIQUE\s+//;
    }
    return $sql;
}

##############################################################################

=head3 index_on

  my $column = $kbs->index_on($attr);

Returns the name of the column on which an index will be generated for the
given Object::Relation::Meta::Attribute::Schema object. Called by C<index_for_class()>
in the parent class. Overridden here to wrap the name in the PostgreSQL
C<LOWER()> function when the data type is a string.

=cut

sub index_on {
    my ($self, $attr) = @_;
    my $name = $attr->column;
    my $type = $attr->type;
    return "LOWER($name)" if $type eq 'string' || $type eq 'version';
    return $name;
}

##############################################################################

=head3 constraints_for_class

  my @constraints = $kbs->constraints_for_class($class);

Returns a list of the SQL statements to create all of the constraints for the
class described by the Object::Relation::Meta::Class::Schema object passed as the sole
argument.

The constraint statements returned may include one or more of the following:

=over

=item *

A primary key constraint.

=item *

A foreign key constraint from the primary key column to the table for a
concrete parent class.

=item *

Foreign key constraints to the tables for contained (referenced) objects.

=item *

"Once triggers", which prevent a value from being changed in a column after
the first time it has been set to a non-C<NULL> value.

=item *

"Unique triggers", which prevent a column from having two rows with the same
value. Only applies when the C<state> column is in a parent table, because
otherwise this constraint is actually handled by a partial unique index.

=back

=cut

sub constraints_for_class {
    my ($self, $class) = @_;
    my $key   = $class->key;
    my $table = $class->table;
    my $pk    = $class->primary_key;

    # We always need a primary key.
    my @cons = (
        "ALTER TABLE $table\n  ADD CONSTRAINT $pk PRIMARY KEY (id);\n"
    );

    # Add a foreign key from the id column to the parent table if this
    # class has a parent table class.
    if (my $parent = $class->parent) {
        my $fk       = $class->foreign_key;
        my $fk_table = $parent->table;
        push @cons, "ALTER TABLE $table\n"
          . "  ADD CONSTRAINT $fk FOREIGN KEY (id)\n"
          . "  REFERENCES $fk_table(id) ON DELETE CASCADE;\n";
    }

    # Add foreign keys for any attributes that reference other objects.
    for my $attr ($class->table_attributes) {
        my $ref        = $attr->references or next;
        my $fk_table   = $ref->table;
        my $del_action = uc $attr->on_delete;
        my $col        = $attr->column;
        my $fk         = $attr->foreign_key;
        push @cons, "ALTER TABLE $table\n"
          . "  ADD CONSTRAINT $fk FOREIGN KEY ($col)\n"
          . "  REFERENCES $fk_table(id) ON DELETE $del_action;\n";
    }

    # Add any once triggers and unique constraints.
    push @cons, (
        $self->once_triggers(   $class ),
        $self->unique_triggers( $class ),
    );

    push @cons, $self->_generate_collection_constraints( $class );
    return @cons;
}

##############################################################################

=head3 procedures_for_class

  my $constraint_sql = $kbs->procedures_for_class($class);

Returns a list of the SQL statements to create all of the procedures and/or
functions for the class described by the Object::Relation::Meta::Class::Schema object
passed as the sole argument.

This implementation actually returns C<undef> (or an empty list), but may be
overridden in subclasses to return procedure declarations.

=cut

sub procedures_for_class {
    my ( $self, $class ) = @_;
    my @attrs = $class->collection_attributes;
    return unless @attrs;
    my $main_key   = $class->key;
    my @procs;
    for my $attr (@attrs) {
        my $table    = $attr->collection_table;
        my $view     = $attr->collection_view;
        my $coll_key = $attr->name;
        push @procs,
            $self->_coll_clear_sql($view, $table, $main_key),
            $self->_coll_del_sql($view, $table, $main_key, $coll_key),
            $self->_coll_add_sql($view, $table, $main_key, $coll_key),
            $self->_coll_set_sql($view, $table, $main_key, $coll_key),
        ;
    }
    return @procs;
}

sub _coll_clear_sql {
    my ($self, $view, $table, $main_key) = @_;
    return qq{CREATE OR REPLACE FUNCTION $view\_clear (
    obj_ident integer
) RETURNS VOID AS \$\$
BEGIN
    DELETE FROM $table WHERE $main_key\_id = obj_ident;
END;
\$\$ LANGUAGE plpgsql SECURITY DEFINER;
};
}

sub _coll_del_sql {
    my ($self, $view, $table, $main_key, $coll_key) = @_;
    return qq{CREATE OR REPLACE FUNCTION $view\_del (
    obj_ident integer,
    coll_ids  integer[]
) RETURNS VOID AS \$\$
BEGIN
    DELETE FROM $table
    WHERE  $main_key\_id = obj_ident
           AND $coll_key\_id = ANY(coll_ids);
END;
\$\$ LANGUAGE plpgsql SECURITY DEFINER;
};
}


sub _coll_add_sql {
    my ($self, $view, $table, $main_key, $coll_key) = @_;
    return qq{CREATE OR REPLACE FUNCTION $view\_add (
    obj_ident integer,
    coll_ids  integer[]
) RETURNS VOID AS \$\$
DECLARE
  -- To keep track of the current max($coll_key\_order).
  last_ord smallint;
BEGIN
    -- Lock the containing object tuple to prevernt inserts into the
    -- collection table.
    PERFORM true FROM $main_key WHERE id = obj_ident FOR UPDATE;

    -- Determine the previous highest value of the $coll_key\_order column
    -- for the given object ID.
    SELECT INTO last_ord COALESCE(MAX($coll_key\_order), 0)
    FROM   $table
    WHERE  $main_key\_id = obj_ident;

    -- Insert the new IDs. The ordering may not be sequential.
    INSERT INTO $table ($main_key\_id, $coll_key\_id, $coll_key\_order )
    SELECT obj_ident, coll_ids[gs.ser], gs.ser + last_ord
    FROM   generate_series(1, array_upper(coll_ids, 1)) AS gs(ser)
    WHERE  coll_ids[gs.ser] NOT IN (
        SELECT $coll_key\_id FROM $table ect2
        WHERE  $main_key\_id = obj_ident
    );
END;
\$\$ LANGUAGE plpgsql SECURITY DEFINER;
};
}

sub _coll_set_sql {
    my ($self, $view, $table, $main_key, $coll_key) = @_;
    return qq{CREATE OR REPLACE FUNCTION $view\_set (
    obj_ident integer,
    coll_ids  integer[]
) RETURNS VOID AS \$\$
BEGIN
    -- Lock the containing object tuple to prevernt inserts into the
    -- collection table.
    PERFORM true FROM $main_key WHERE id = obj_ident FOR UPDATE;

    -- First negate $coll_key\_order to prevent unique index violations.
    UPDATE $table
    SET    $coll_key\_order = -$coll_key\_order
    WHERE  $main_key\_id = obj_ident;

    IF FOUND IS false THEN
        -- There are no existing tuples, so just insert the new ones.
        INSERT INTO $table ($main_key\_id, $coll_key\_id, $coll_key\_order)
        SELECT obj_ident, coll_ids[gs.ser], gs.ser
        FROM   generate_series(1, array_upper(coll_ids, 1)) AS gs(ser)
        WHERE  coll_ids[gs.ser] IS NOT NULL;
    ELSE
        -- First, update the existing tuples with new $coll_key\_order values.
        UPDATE $table SET $coll_key\_order = ser
        FROM (
            SELECT gs.ser, coll_ids[gs.ser] as move_$coll_key
            FROM   generate_series(1, array_upper(coll_ids, 1)) AS gs(ser)
            WHERE  coll_ids[gs.ser] IS NOT NULL
        ) AS expansion
        WHERE move_$coll_key = $coll_key\_id
              AND $main_key\_id = obj_ident;

        -- Now insert the new tuples.
        INSERT INTO $table ($main_key\_id, $coll_key\_id, $coll_key\_order )
        SELECT obj_ident, coll_ids[gs.ser], gs.ser
        FROM   generate_series(1, array_upper(coll_ids, 1)) AS gs(ser)
        WHERE  coll_ids[gs.ser] NOT IN (
            SELECT $coll_key\_id FROM $table ect2
            WHERE  $main_key\_id = obj_ident
        );

        -- Delete any remaining tuples.
        DELETE FROM $table
        WHERE  $main_key\_id = obj_ident AND $coll_key\_order < 0;
    END IF;
END;
\$\$ LANGUAGE plpgsql SECURITY DEFINER;
};
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
    my ($self, $key, $attr, $table, $if) = @_;
    my $col = $attr->column;

    return $self->create_trigger_for_table(
        "$key\_$col\_once",
        'UPDATE',
        $table,
        'BEFORE',
        "trig_$col\_once",
    ) if $attr->type eq 'uuid' && $attr->name eq 'uuid';

    return qq{CREATE FUNCTION $key\_$col\_once() RETURNS trigger AS \$\$
  BEGIN
    IF $if
        THEN RAISE EXCEPTION 'value of $key.$col cannot be changed';
    END IF;
    RETURN NEW;
  END;
\$\$ LANGUAGE plpgsql;
},
    $self->create_trigger_for_table("${key}_${col}_once", 'UPDATE', $table);
}

##############################################################################

=head3 unique_triggers

  my @unique_triggers = $kbs->unique_triggers($class);

Returns the PostgreSQL triggers to validate the values of any "unique"
attributes, wherein the attribute is in a different class than the C<state>
attribute. Unique attributes in the same class as the C<state> attribute are
handled by a partial unique index. If the class has no unique attributes
C<unique_triggers()> will return an empty list.

Called by C<constraints_for_class()>.

=cut

sub unique_triggers {
    my ($self, $class) = @_;
    my @uniques = grep { $_->unique && !$_->distinct } $class->table_attributes
        or return;
    my $table        = $class->table;
    my $key          = $class->key;
    my $state_class = first { grep { $_->name eq 'state'} $_->table_attributes }
        reverse( $class->parents )
        or return;
    my $parent_table = $state_class->table;
    my @trigs;
    for my $attr (@uniques) {
        my $col  = $attr->column;
        my $type = $attr->type;
        my ($comp_col, $new_col, $old_col)
            = $type eq 'string' || $type eq 'version'
            ? ("LOWER($col)", "LOWER(NEW.$col)", "LOWER(OLD.$col")
            : ($col,          "NEW.$col",        "OLD.$col"      );

        my $lock_records = <<"        END_SQL";
                /* Lock the relevant records in the parent and child tables. */
                PERFORM true
                FROM    $table, $parent_table
                WHERE   $table.id = $parent_table.id AND $comp_col = $new_col FOR UPDATE;
                IF (SELECT true
                    FROM   $key
                    WHERE  id <> NEW.id AND $comp_col = $new_col AND state > -1
                    LIMIT 1
                ) THEN
                    RAISE EXCEPTION 'duplicate key violates unique constraint "ck_$key\_$col\_unique"';
                END IF;
        END_SQL

        push @trigs, qq{CREATE FUNCTION cki_$key\_$col\_unique() RETURNS trigger AS \$\$
  BEGIN
    $lock_records
    RETURN NEW;
  END;
\$\$ LANGUAGE plpgsql SECURITY DEFINER;

@{[ $self->create_trigger_for_table("cki_${key}_${col}_unique", 'INSERT', $table) ]}

CREATE FUNCTION cku_$key\_$col\_unique() RETURNS trigger AS \$\$
  BEGIN
    IF ($new_col <> $old_col) THEN
        $lock_records
    END IF;
    RETURN NEW;
  END;
\$\$ LANGUAGE plpgsql SECURITY DEFINER;

@{[ $self->create_trigger_for_table("cku_${key}_${col}_unique", 'UPDATE', $table) ]}

CREATE FUNCTION ckp_$key\_$col\_unique() RETURNS trigger AS \$\$
  BEGIN
    IF (NEW.state > -1 AND OLD.state < 0
        AND (SELECT true FROM $table WHERE id = NEW.id)
       ) THEN
        /* Lock the relevant records in the parent and child tables. */
        PERFORM true
        FROM    $table, $parent_table
        WHERE   $table.id = $parent_table.id
                AND $comp_col = (SELECT $comp_col FROM $table WHERE id = NEW.id)
        FOR UPDATE;

        IF (SELECT COUNT($comp_col)
            FROM   $table
            WHERE $comp_col = (SELECT $comp_col FROM $table WHERE id = NEW.id)
        ) > 1 THEN
            RAISE EXCEPTION 'duplicate key violates unique constraint "ck_$key\_$col\_unique"';
        END IF;
    END IF;
    RETURN NEW;
  END;
\$\$ LANGUAGE plpgsql SECURITY DEFINER;

@{[ $self->create_trigger_for_table("ckp_${key}_${col}_unique", 'UPDATE', $parent_table) ]}
};
    }

    return @trigs;
}

##############################################################################

=head3 create_trigger_for_table

  my $trigger = $kbs->create_trigger_for_table(
      $trigger_name, $type, $table, $when, $func,
  );

Given a trigger name and a table name, returns a C<CREATE TRIGGER> statement
which will execute the named trigger before any row is updated/inserted in the
table. The C<$type> should be "UPDATE" or "INSERT". C<$when> defaults to
"BEFORE". If C<$func> is not passed, the name of the trigger will be used for
the name of the function. All other arguments are required.

=cut

sub create_trigger_for_table {
    my ($self, $trigger, $type, $table, $when, $func) = @_;
    $when ||= 'BEFORE';
    $func ||= $trigger;
    return <<"    END_TRIGGER";
CREATE TRIGGER $trigger $when $type ON $table
FOR EACH ROW EXECUTE PROCEDURE $func();
    END_TRIGGER
}

##############################################################################

=head3 insert_for_class

  my $insert_rule_sql = $kbs->insert_for_class($class);

Returns a PostgreSQL C<RULE> that manages C<INSERT> statements executed
against the view for the class. The rule ensures that the C<INSERT> statement
updates the table for the class as well as any parent classes. Extended and
mediated objects are also inserted or updated as appropriate, but other
contained objects are ignored, and should be inserted or updated separately.

=cut

sub insert_for_class {
    my ($self, $class) = @_;
    if (my $extends = $class->extends || $class->mediates) {
        return $self->_extend_for_class($class, $extends);
    } else {
        return $self->_insert_for_class($class);
    }
}

##############################################################################

=head3 update_for_class

  my $update_rule_sql = $kbs->update_for_class($class);

Returns a PostgreSQL rule that manages C<UPDATE> statements executed against
the view for the class. The rule ensures that the C<UPDATE> statement updates
the table for the class as well as any parent classes. Extended and mediated
objects are also updated, but other contained objects are ignored, and should
be updated separately.

=cut

sub update_for_class {
    my ($self, $class) = @_;
    my $key = $class->key;
    # Output the UPDATE rule.
    my $sql .= "CREATE RULE update_$key AS\n"
      . "ON UPDATE TO $key DO INSTEAD (";
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

    if (my $extended = $class->extends || $class->mediates) {
        my $view = $extended->key;
        # Update the extended class's VIEW, too.
        $sql .= "\n  UPDATE $view\n  SET    "
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
          . "\n  WHERE  id = OLD.$view\__id;\n";
    }
    return $sql . ");\n";
}

##############################################################################

=head3 delete_for_class

  my $delete_rule_sql = $kbs->delete_for_class($class);

Returns a PostgreSQL rule that manages C<DELETE> statements executed against
the view for the class. Deletes simply pass through to the underlying table
for the class; parent object records are left in tact.

=cut

sub delete_for_class {
    my ($self, $class) = @_;
    my $key = $class->key;
    my $table = $class->table;
    # Output the DELETE rule.
    return "CREATE RULE delete_$key AS\n"
      . "ON DELETE TO $key DO INSTEAD (\n"
      . "  DELETE FROM $table\n"
      . "  WHERE  id = OLD.id;\n);\n";
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
        for my $type qw(insert update delete) {
            my $adverb = $type eq 'insert' ? ' into' : '';
            my $var    = $type eq 'delete' ? 'OLD' : 'NEW';
            push @triggers,
                "CREATE OR REPLACE RULE $view\_$type AS\n"
              . "ON \U$type\E TO $view DO INSTEAD (\n"
              . "    SELECT coll_error('$view', '$type$adverb', "
              .            "$var.$main_key\_id, $var.$coll_key\_id);\n"
              . ");\n";
          }
    }
    return @triggers;
}

##############################################################################

=head3 setup_code

  my $setup_sql = $kbs->setup_code;

Returns any SQL statements that must be executed after the creation of a
database, but before any database objects are created. This implementation
returns statement to perform the following tasks:

=over

=item *

Creates a domain, "state", that can be used as a column type in Object::Relation
tables.

=back

=cut

sub setup_code {

q{CREATE DOMAIN state AS SMALLINT NOT NULL DEFAULT 1
CONSTRAINT ck_state CHECK (
   VALUE BETWEEN -1 AND 2
);
},

q{CREATE DOMAIN whole AS INTEGER
CONSTRAINT ck_whole CHECK (
   VALUE >= 0
);
},

q{CREATE DOMAIN posint AS INTEGER
CONSTRAINT ck_posint CHECK (
   VALUE > 0
);
},

q{CREATE DOMAIN operator AS TEXT
CONSTRAINT ck_operator CHECK (
   VALUE IN('==', '!=', 'eq', 'ne', '=~', '!~', '>', '<', '>=', '<=', 'gt',
            'lt', 'ge', 'le')
);
},

q{CREATE DOMAIN media_type AS TEXT
CONSTRAINT ck_media_type CHECK (
   VALUE ~ '^\\\\w+/\\\\w+$'
);
},

# Create a table for classes, attributes and use a FK? Shouldn't be necessary.
q{CREATE DOMAIN attribute AS TEXT
CONSTRAINT ck_attribute CHECK (
   VALUE ~ '^\\\\w+\\\\.\\\\w+$'
);
},

q{CREATE DOMAIN version AS TEXT
CONSTRAINT ck_version CHECK (
    VALUE ~ '^v?\\\\d[\\\\d._]+$'
);
},

# Create the function for validating GTINs.
q{CREATE OR REPLACE FUNCTION isa_gtin(bigint) RETURNS BOOLEAN AS $$
    SELECT ( sum(dgt) % 10 ) = 0
    FROM (
        SELECT substring($1 from idx for 1)::smallint AS dgt
        FROM   (SELECT generate_series(length($1), 1, -2) as idx) AS foo
        UNION ALL
        SELECT substring($1 from idx for 1)::smallint * 3 AS dgt
        FROM   (SELECT generate_series(length($1) -1, 1, -2) as idx) AS foo
    ) AS bar;
$$ LANGUAGE sql STRICT IMMUTABLE;
},

q{CREATE DOMAIN gtin AS BIGINT
CONSTRAINT ck_gtin CHECK (
   isa_gtin(VALUE)
);
},

q{CREATE OR REPLACE FUNCTION trig_uuid_once() RETURNS trigger AS $$
  BEGIN
    IF OLD.uuid <> NEW.uuid OR NEW.uuid IS NULL
        THEN RAISE EXCEPTION 'value of %.uuid cannot be changed', TG_RELNAME;
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;
},

q{CREATE OR REPLACE FUNCTION coll_error(
    view_name  TEXT,
    query_type TEXT,
    obj_id     INTEGER,
    coll_id    INTEGER
) RETURNS VOID AS $$
BEGIN
    IF query_type = 'delete' THEN
        RAISE EXCEPTION
          'Please use %_del(%, {%}) or %_clear(%) to % from the % collection',
          view_name, obj_id, coll_id, obj_id, query_type, view_name;
    ELSE
        RAISE EXCEPTION
          'Please use %_add(%, {%}) or %_set(%, {%}) to % the % collection',
          view_name, obj_id, coll_id, obj_id, coll_id, query_type, view_name;
    END IF;
END;
$$ LANGUAGE plpgsql;
},
}

##############################################################################

=begin private

=head1 Private Interface

=head2 Private Instance Methods

=head3 _insert_for_class

  my $sql = $kbs->_insert_for_class($class);

This method is called by C<insert_for_class()> to create the C<INSERT> C<RULE>
on the view for a class that does not extend another class, which is to say
for most classes.

=cut

sub _insert_for_class {
    my ($self, $class) = @_;
    my $key  = $class->key;
    my $func = 'NEXTVAL';
    my $seq  = '';

    # Output the INSERT rule.
    my $sql = "CREATE RULE insert_$key AS\n"
      . "ON INSERT TO $key DO INSTEAD (";
    for my $impl (reverse($class->parents), $class) {
        $seq ||= $impl->key;
        $sql  .= $self->_insert_into_table($impl, "$func('seq_$seq')");
        $func  = 'CURRVAL';
    }
    return $sql . ");\n";
}

##############################################################################

=head3 _extend_for_class

  my $sql = $kbs->_insert_into_table($extending_class, $extended_class);

This method is called by C<insert_for_class()> to create the C<RULE>s
necessary to insert a new record into the view for a class that extends
another class.

=cut

sub _extend_for_class {
    my ($self, $class, $extends) = @_;
    my $key  = $class->key;
    my $ext_key = $extends->key;
    my $func = 'NEXTVAL';
    my $seq  = '';

    # Get a list of the attributes that delegate to the extended class.
    my @ext_attrs = grep {
        $_->persistent && $_->delegates_to || '' eq $extends
    } $class->attributes;

    # Output the main insert RULE.
    my $sql = "CREATE RULE insert_$key AS\n"
      . "ON INSERT TO $key WHERE NEW.$ext_key\__id IS NULL DO INSTEAD (";
    for my $impl (reverse($class->parents)) {
        $seq ||= $impl->key;
        $sql .= $self->_insert_into_table($impl, "$func('seq_$seq')");
        $func = 'CURRVAL';
    }

    # Append the INSERTs into the extended VIEW and the extending TABLE.
    $seq ||= $class->key;
    $sql .= $self->_extended_insert   ( $class, $extends, \@ext_attrs )
          . $self->_extending_insert   ( $class, $extends, "$func('seq_$seq')")
          . ");\n";

    # Start the extend RULE
    $sql .= "\nCREATE RULE extend_$key AS\n"
          . "ON INSERT TO $key WHERE NEW.$ext_key\__id IS NOT NULL DO INSTEAD (";
    for my $impl (reverse($class->parents)) {
        $sql .= $self->_insert_into_table($impl, "$func('seq_$seq')");
        $func = 'CURRVAL';
    }

    # Append UPDATE to exteded VIEW and INSERT into extending TABLE.
    $sql .= $self->_extended_insert_up( $class, $extends, \@ext_attrs )
          . $self->_insert_into_table($class, "$func('seq_$seq')")
          . ");\n";

    # Append dummy RULE: Pg requires an unconditional DO INSTEAD on VIEWs.
    $sql .= "\nCREATE RULE insert_$key\_dummy AS\n"
          . "ON INSERT TO $key DO INSTEAD NOTHING;\n";
    return $sql;
}

##############################################################################

=head3 _insert_into_table

  my $sql = $kbs->_insert_into_table($class, $seq_code);

Used by C<_insert_for_class()> and C<_extend_for_class()>, this method is used
to generate the C<INSERT> statement used by a C<RULE> to C<INSERT> into a
table when inserting into a C<VIEW> that represents a class. The $seq_code
argument should be a string representing the SQL code to generate the ID for
the table, e.g., "NEXTVAL('seq_person')".

=cut

sub _insert_into_table {
    my ($self, $impl, $seq) = @_;
    my $table = $impl->table;
    return "\n  INSERT INTO $table (id, "
        . join(', ', map { $_->column } $impl->table_attributes )
        . ")\n  VALUES ($seq, "
        . join(', ', map {
            if (my $def = $self->column_default($_)) {
                $def =~ s/DEFAULT\s+//;
                'COALESCE(NEW.' . $_->view_column . ", $def)";
            } else {
                'NEW.' . $_->view_column;
            }
        } $impl->table_attributes)
        . ");\n";
}

#############################################################################

=head3 _extended_insert

  my $sql = $kbs->_extended_insert($class, $extends, \@ext_attrs);

This method, called by C<_extend_for_class()>, returns SQL to be used in the
C<INSERT> C<RULE> on a C<VIEW> for an extended class. The SQL returned is a
single C<INSERT> into the C<VIEW> for the extended class.

=cut

sub _extended_insert {
    my ($self, $class, $extends, $ext_attrs) = @_;
    my $ext_key = $extends->key;

    return "\n  INSERT INTO $ext_key ("
        . join(', ', map { $_->view_column } $extends->persistent_attributes )
        . ")\n  VALUES ("
        . join(', ', map {
            if (my $def = $self->column_default($_)) {
                $def =~ s/DEFAULT\s+//;
                'COALESCE(NEW.' . $_->view_column . ", $def)";
            } else {
                'NEW.' . $_->view_column;
            }
        } @$ext_attrs)
        . ");\n"
}

##############################################################################

=head3 _extended_insert_up

  my $sql = $kbs->_extended_insert_up($class, $extends, \@ext_attrs);

This method, called by C<_extend_for_class()>, returns SQL to be used in the
C<INSERT> C<RULE> on a C<VIEW> for an extended class. The SQL returned is an
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
        . "\n  WHERE  id = NEW.$ext_key\__id;\n";
}

##############################################################################

=head3 _extending_insert

  my $sql = $kbs->_extending_insert($class, $extends, \@ext_attrs);

This method, called by C<_extend_for_class()>, returns SQL to be used in the
C<INSERT> C<RULE> on a C<VIEW> for an extended class. The SQL returned is an
C<INSERT> into the table of the extending class.

=cut

sub _extending_insert {
    my ($self, $class, $extends, $seq) = @_;
    my $table   = $class->table;
    my $ext_key = $extends->key;
    my $ext_seq = $ext_key;
    if (my @parents = reverse($extends->parents)) {
        $ext_seq = $parents[0]->key;
    }

    return "\n  INSERT INTO $table (id, "
        . join(', ', map { $_->column } $class->table_attributes )
        . ")\n  VALUES ($seq, "
        . join(', ', map {
            if (my $def = $self->column_default($_)) {
                $def =~ s/DEFAULT\s+//;
                'COALESCE(NEW.' . $_->view_column . ", $def)";
            } elsif ($_->type eq $ext_key) {
                "CURRVAL('seq_$ext_seq')";
            } else {
                'NEW.' . $_->view_column;
            }
        } $class->table_attributes)
        . ");\n";
}

##############################################################################

=head3 _generate_collection_constraints

  my @coll_constraints = $schema->_generate_collection_constraints($class);

Returns a list of the constraints necessary to manage a collection table
associated with the Object::Relation::Meta::Class object passed as the sole argument.

=cut

sub _generate_collection_constraints {
    my ( $self, $class ) = @_;
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
        push @constraints,
            qq{ALTER TABLE $table
  ADD CONSTRAINT pk_$view PRIMARY KEY ($main_key\_id, $coll_key\_id);
},

            qq{ALTER TABLE $table
  ADD CONSTRAINT fk_$view$main_table\_id FOREIGN KEY ($main_key\_id)
  REFERENCES $main_table(id) ON DELETE CASCADE;
},
            qq{ALTER TABLE $table
  ADD CONSTRAINT fk_$view\_$coll_key\_id FOREIGN KEY ($coll_key\_id)
  REFERENCES $coll_table(id) ON DELETE CASCADE;
};

        if ($attr->relationship eq 'has_many') {
            # Each collection object belongs only to the parent object,
            # so make sure that deletes fully cascade.
        push @constraints,
            qq{CREATE OR REPLACE FUNCTION $view\_cascade() RETURNS trigger AS \$\$
  BEGIN
    DELETE FROM $coll_table WHERE id = OLD.$coll_key\_id;
    RETURN OLD;
  END;
\$\$ LANGUAGE plpgsql;
},
            $self->create_trigger_for_table(
                "$view\_cascade",
                'DELETE',
                $table,
                'AFTER',
            );
        }
    }
    return @constraints;
}

1;
__END__

##############################################################################

=head1 Copyright and License

Copyright (c) 2004-2006 Kineticode, Inc. <info@obj_relode.com>

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
