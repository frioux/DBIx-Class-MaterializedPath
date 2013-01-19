package DBIx::Class::MaterializedPath;

use warnings;
use strict;

use Sub::Current;

sub _get_column_change_method {
   my ($self, $path_info) = @_;

   return sub {
      my $self = shift;
      my $rel = $path_info->{children_relationship};
      $self->_set_materialized_path($path_info);
      ROUTINE->($_) for $self->$rel->search({
         # to avoid recursion
         map +(
            "me.$_" => { '!=' => $self->get_column($_) },
         ), $self->result_source->primary_columns
      })->all
   }
}

1;
