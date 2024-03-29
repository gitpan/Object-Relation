package Object::Relation::Meta;

# $Id: Meta.pm 3076 2006-07-28 17:20:08Z theory $

use strict;

use version;
our $VERSION = version->new('0.1.0');

use base 'Class::Meta';
use Object::Relation::Meta::DataTypes;
use Object::Relation::Meta::Attribute;
use Object::Relation::Meta::Class;
use Object::Relation::Meta::Method;
use Object::Relation::Exceptions qw(
    throw_exlib
    throw_invalid_class
    throw_invalid_attr
);
use Class::Meta::Types::String;    # Move to DataTypes.

use constant BASE_CLASS => 'Object::Relation::Base';

=head1 Name

Object::Relation::Meta - Object::Relation class automation, introspection, and data validation

=head1 Synopsis

  package MyThingy;

  use strict;

  BEGIN {
      my $cm = Object::Relation::Meta->new(
        key         => 'thingy',
        plural_key  => 'thingies',
        name        => 'Thingy',
        plural_name => 'Thingies',
      );
      $cm->build;
  }

=head1 Description

This class inherits from L<Class::Meta|Class::Meta> to provide class
automation, introspection, and data validation for Object::Relation classes. It
overrides the behavior of Class::Meta to specify the use of the
L<Object::Relation::Meta::Class|Object::Relation::Meta::Class> subclass in place of
Class::Meta::Class.

Any class created with L<Object::Relation::Meta|Object::Relation::Meta> will
automatically have L<Object::Relation::Base|Object::Relation::Base> pushed onto
its C<@ISA> array unless it already inherits from
L<Object::Relation::Base|Object::Relation::Base>.

=head1 Dynamic APIs

This class supports the dynamic loading of extra methods specifically designed
to be used with particular Object::Relation data store implementations. This is so that
the store APIs can easily dispatch to attribute objects, class objects, and
data types to get data-store specific metadata without having to do extra work
themselves. Data store implementors needing store-specific metadata methods
should add them as necessary to the C<import()> methods of
L<Object::Relation::Meta::Class|Object::Relation::Meta::Class>,
L<Object::Relation::Meta::Attribute|Object::Relation::Meta::Attribute>, and/or/
L<Object::Relation::Meta::Type|Object::Relation::Meta::Type>

In general, however, Object::Relation users will not need to worry about loading
data-store specific APIs, as the data stores will load them themselves. And
since the methods should either be protected or otherwise transparent, no one
else should use them, anyway.

As of this writing, only a single data-store specific API label is supported:

  use Object::Relation::Meta ':with_dbstore_api';

More may be added in the future.

=cut

sub import {
    my ( $pkg, $api_label ) = @_;
    return unless $api_label;
    $_->import($api_label) for qw(
        Object::Relation::Meta::Class
        Object::Relation::Meta::Attribute
        Object::Relation::Meta::Type
    );
}

##############################################################################
# Constructors.
##############################################################################

=head1 Class Interface

=head2 Constructors

=head3 new

  my $cm = Object::Relation::Meta->new(%init);

Overrides the parent Class::Meta constructor in order to specify that the
class class be Object::Relation::Meta::Classl, the attribute class be
Object::Relation::Meta::Attribute, and that the method class be Object::Relation::Meta::Method.
It also forces the C<key> parameter to default to the last part of the package
name, e.g., the C<key> for the class My::Big::Fat::Cat would be "cat". This is
to override Class::Meta's default of using the full class name for the C<key>.

In addition to the parameters supported by C<< Class::Meta->new >>,
C<< Object::Relation::Meta->new >> supports these extra attributes:

=over

=item plural_key

The pluralized form of the C<key> parameter. For example, if the key is
"thingy", the plural key would be "thingies". If not defined,
L<Lingua::EN::Inflect|Lingua::EN::Inflect> will be used to generate a plural
key.

=item plural_name

The pluralized form of the C<name> parameter. For example, if the name is
"Thingy", the plural key would be "Thingies". If not defined,
L<Lingua::EN::Inflect|Lingua::EN::Inflect> will be used to generate a plural
name.

=item sort_by

This attribute is the name of an attribute or array reference of names of the
attributes to use when sorting a list of objects of the class. If C<sort_by>
is not specified, it defaults to the first attribute declared after the
C<uuid> and C<state> attributes.

=item extends

This attribute specifies a single Object::Relation class name that the class extends.
Extension is similar to inheritance, only extended class objects have their
own UUIDs and states, and there can be multiple extending objects for a single
extended object (think one person acting as several users).

=back

=cut

__PACKAGE__->default_error_handler(\&throw_exlib);

sub new {
    my $pkg  = shift;
    my $caller = caller;
    (my $key = lc $caller) =~ s/.*:://;
    my $self = $pkg->SUPER::new(
        package         => $caller,  # Ensure.
        key             => $key,     # Default.
        @_,
        class_class     => $pkg->class_class,
        attribute_class => $pkg->attribute_class,
        method_class    => $pkg->method_class,
    );

    my $class    = $self->class;
    my $package  = $class->package;
    my $extended = $class->extends;
    my $mediated = $class->mediates;

    if ( BASE_CLASS ne $package ) {
        unless ( $package->isa(BASE_CLASS) ) {
            # force packages to inherit from Object::Relation
            # XXX unfortunately, there's some deep magic in "use base" which
            # causes the simple "push @ISA" to fail.
            #no strict 'refs';
            #push @{"$package\::ISA"}, BASE_CLASS;
            eval "package $package; use base '" . BASE_CLASS . q{';};
            if ( my $error = $@ ) {
                # This should never happen ...
                # If it does, there's a good chance you're in the wrong
                # directory and the config file can't be found.
                throw_invalid_class [
                    'I could not load the class "[_1]": [_2]',
                    BASE_CLASS,
                    $error,
                ];
            }
        }

        # Set up the store handle.
        my $store_config = delete $class->{store_config}
            || $package->can('StoreHandle') ? undef : {};

        if ($store_config) {
            my $handle = Object::Relation::Handle->new($store_config);
            $handle->_add_store_meta($self);
            no strict 'refs';
            *{"$package\::StoreHandle"} = sub { $handle };
        }
    }

    if ($extended and $mediated) {
        throw_invalid_class [
            '[_1] can either extend or mediate another class, but not both',
            $class->package,
        ];
    }

    # Set up attributes if this class extends another class.
    elsif ($extended) {
        my $ext_pkg = $extended->package;

        # Make sure that we're not using inheritance!
        throw_invalid_class [
            '[_1] cannot extend [_2] because it inherits from it',
            $package,
            $ext_pkg,
        ] if $package->isa($ext_pkg);

        $self->_add_delegates(
            $extended,
            'extends',
            1,
            sub { $extended->package->new },
            $class->type_of,
        );
    }

    # Set up attributes if this class mediates another class.
    elsif ($mediated) {
        $self->_add_delegates(
            $mediated,
            'mediates',
            1,
            sub { $mediated->package->new }
        );
    }

    # Set up attributes if this class is a type of another class.
    if (my $type = $class->type_of) {
        $self->_add_delegates($type, 'type_of', 0);
    }

    return $self;
}

##############################################################################

=head2 Class Attributes

=head3 class_class

  my $class_class = Object::Relation::Meta->class_class;
  Object::Relation::Meta->class_class($class_class);

The subclass or Class::Meta::Class that will be used to represent class
objects. The value of this class attribute is only used at startup time when
classes are loaded, so if you want to change it form the default, which is
"Object::Relation::Meta::Class", do it before you load any Object::Relation classes.

=cut

my $class_class = 'Object::Relation::Meta::Class';

sub class_class {
    shift;
    return $class_class unless @_;
    $class_class = shift;
}

##############################################################################

=head3 attribute_class

  my $attribute_class = Object::Relation::Meta->attribute_class;
  Object::Relation::Meta->attribute_class($attribute_class);

The subclass or Class::Meta::Attribute that will be used to represent attribute
objects. The value of this class attribute is only used at startup time when
classes are loaded, so if you want to change it form the default, which is
"Object::Relation::Meta::Attribute", do it before you load any Object::Relation classes.

=cut

my $attribute_class = 'Object::Relation::Meta::Attribute';

sub attribute_class {
    shift;
    return $attribute_class unless @_;
    $attribute_class = shift;
}

##############################################################################

=head3 method_class

  my $method_class = Object::Relation::Meta->method_class;
  Object::Relation::Meta->method_class($method_class);

The subclass or Class::Meta::Method that will be used to represent method
objects. The value of this class method is only used at startup time when
classes are loaded, so if you want to change it form the default, which is
"Object::Relation::Meta::Method", do it before you load any Object::Relation classes.

=cut

my $method_class = 'Object::Relation::Meta::Method';

sub method_class {
    shift;
    return $method_class unless @_;
    $method_class = shift;
}

##############################################################################

=head2 Class Methods

=head3 for_key

  my $class = Object::Relation::Meta->for_key($key);

This method overrides the implementation inherited from
L<Class::Meta|Class::Meta> to throw an exception no class object exists for
the key passed as its sole argument. To use C<for_key()> without getting an
exception, call C<< Class::Meta->for_key() >>, instead.

=cut

sub for_key {
    my ($pkg, $key) = @_;
    if (my $class = $pkg->SUPER::for_key($key)) {
        return $class;
    }
    throw_invalid_class [
        'I could not find the class for key "[_1]"',
        $key
    ];
}

##############################################################################

=head3 attr_for_key

  my $attribute = Object::Relation::Meta->attr_for_key('foo.bar');

This method returns a L<Object::Relation::Meta::Attribute|Object::Relation::Meta::Attribute>
object for a given class key and attribute. The class key and attribute name
are separated by a dot (".") in the argument. In this above example, the
attribute "bar" would be returned for the class with the key "foo".

=cut

sub attr_for_key {
    my $pkg = shift;
    my ($key, $attr_name) = split /\./ => shift;
    if (my $attr = $pkg->for_key($key)->attributes($attr_name)) {
        return $attr;
    }
    throw_invalid_attr [
        'I could not find the attribute "[_1]" in class "[_2]"',
        $attr_name,
        $key,
    ];
}

##############################################################################

=begin private

=head1 Private Interface

=head2 Private Instance Methods

=head3 _add_delegates

  $km->_add_delegates($ref, $rel, $persist, $default);

This method is called by C<new()> to add delegating attributes to a
Object::Relation::Meta::Class that extends, mediates, or is a type of another class.
The arguments are as follows:

=over

=item 1 $ref

The first argument is a Object::Relation::Meta::Class object representing the class
that the current class references for the relationship.

=item 2 $rel

The second argument is a string denoting the type of relationship, one of
"extends", "mediates", or "type_of".

=item 3 $persist

A boolean value indicating whether the attributes should be persistent or not.
Only "type_of" attributes should not be persistent.

=item 4 $default

The default value for the attribute, if any.

=back

=cut

sub _add_delegates {
    my ($self, $ref, $rel, $persist, $def, @others) = @_;
    my $class = $self->class;
    my $key   = $ref->key;

    # Add attribute for the object.
    $self->add_attribute(
        name         => $key,
        type         => $key,
        required     => 1,
        label        => $ref->{label},
        view         => Class::Meta::TRUSTED,
        create       => Class::Meta::RDWR,
        default      => $def,
        relationship => $rel,
        widget_meta  => Object::Relation::Meta::Widget->new(
            type => 'search',
            tip  => $ref->{label},
        ),
    );

    # XXX Object::Relation::Meta::Class::Schema->parents doesn't work because it
    # only returns non-abstract parents and, besides, doesn't figure out
    # what they are until build() is called.

    my $parent = ($class->Class::Meta::Class::parents)[0];

    # This isn't redundant because attributes can have been added to $class
    # only by _add_delegates(). It won't return any for the current class
    # until after build() is called, and since this is new(), the class itself
    # hasn't declared any yet!

    my %attrs = map { $_->name => undef }
        $class->attributes, $parent->attributes;

    # Disallow attributes with the same names as other important relations.
    $attrs{$_->key} = undef for grep { defined } @others;

    # Add attributes from the extended class.
    for my $attr ($ref->attributes) {
        my $name      = $attr->name;
        my $attr_name = exists $attrs{$name} ? "$key\_$name" : $name;

        # Create a new attribute that references the original attribute.
        $self->add_attribute(
            name         => $attr_name,
            type         => $attr->type,
            required     => $attr->required,
            once         => $attr->once,
            label        => $attr->{label},
            desc         => $attr->desc,
            view         => $attr->view,
            authz        => $attr->authz,
            create       => Class::Meta::NONE,
            context      => $attr->context,
            default      => $attr->default,
            widget_meta  => $attr->widget_meta,
            unique       => $attr->unique,
            distinct     => $attr->distinct,
            indexed      => $attr->indexed,
            persistent   => $attr->persistent && $persist,
            delegates_to => $ref,
            acts_as      => $attr,
        );
        # Delegation methods are created by Object::Relation::Meta::AccessorBuilder.
    }

    if ($persist) {
        # Copy over the methods, too.
        my $pack = $class->package;
        my %meths = map { $_->name => undef }
            $class->methods, $parent->methods;

        for my $meth ($ref->methods) {
            my $name      = $meth->name;
            my $meth_name = exists $meths{$name} ? "$key\_$name" : $name;

            $self->add_method(
                name         => $meth_name,
                label        => $meth->{label},
                desc         => $meth->desc,
                view         => $meth->view,
                context      => $meth->context,
                args         => $meth->args,
                returns      => $meth->returns,
                delegates_to => $ref,
                acts_as      => $meth,
            );

            # Create the delegating method.
            no strict 'refs';
            *{"$pack\::$meth_name"} = eval qq{
                sub {
                    my \$o = shift->$key or return;
                    \$o->$name(\@_);
                }
            };
        }
    }

    return $self;
}

=end private

=cut

1;
__END__

##############################################################################

=head1 Copyright and License

Copyright (c) 2004-2006 Kineticode, Inc. <info@obj_relode.com>

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
