package Object::Relation::Meta::Method;

# $Id: Method.pm 3076 2006-07-28 17:20:08Z theory $

use strict;

use version;
our $VERSION = version->new('0.1.0');

use base 'Class::Meta::Method';

=head1 Name

Object::Relation::Meta::Method - Object::Relation object method introspection

=head1 Synopsis

  # Assuming MyThingy was generated by Object::Relation::Meta.
  my $class  = MyThingy->my_class;
  my $thingy = MyThingy->new;

  print "\nMethods:\n";
  for my $meth ($class->methods) {
      print "  o ", $meth->name, $/;
      $meth->call($thingy);
  }

=head1 Description

This class inherits from L<Class::Meta::Method|Class::Meta::Method> to provide
method metadata for Object::Relation classes. See the L<Class::Meta|Class:Meta>
documentation for details on meta classes. See the L<"Instance Interface">
section for the attributes added to Object::Relation::Meta::Method in addition to those
defined by Class::Meta::Method.

=cut

##############################################################################
# Instance Methods.
##############################################################################

=head1 Instance Interface

=head2 Accessor Methods

=head3 delegates_to

  my $delegates_to = $meth->delegates_to;

If the method transparently delegates to an object of another class, this
method will return the Object::Relation::Meta::Class object describing that class. This
method is implicitly set by Object::Relation::Meta for classes that either extend or
mediate another class, or are a type of another class. In those cases,
Object::Relation::Meta will create extra methods to delegate to the methods of the
referenced or extended classes, and those methods will have their
C<delegates_to> methods set accordingly.

=cut

sub delegates_to { shift->{delegates_to} }

##############################################################################

=head3 acts_as

  my $acts_as = $meth->acts_as;

If C<delegates_to()> returns a Object::Relation::Meta::Class object representing the
class of object to which the method delegates, C<acts_as()> returns the
Object::Relation::Meta::Method object to which this method corresponds. That is, this
method I<acts as> the method returned here.

=cut

sub acts_as { shift->{acts_as} }

1;
__END__

##############################################################################

=head1 Copyright and License

Copyright (c) 2004-2006 Kineticode, Inc. <info@obj_relode.com>

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
