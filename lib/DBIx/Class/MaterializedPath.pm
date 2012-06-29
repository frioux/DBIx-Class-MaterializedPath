package DBIx::Class::MaterializedPath;

use 5.16.0;
use warnings;

use base 'DBIx::Class::Helper::Row::OnColumnChange';

use Class::C3::Componentised::ApplyHooks
   -before_apply => sub {
      die 'class (' . $_[0] . ') must implement materialized_path_columns method!'
         unless $_[0]->can('materialized_path_columns')
   },
   -after_apply => sub {
      my %mat_paths = %{$_[0]->materialized_path_columns};

      for my $path (keys %mat_paths) {
         $_[0]->_install_after_column_change($mat_paths{$path});
         $_[0]->_install_full_path_rel($mat_paths{$path});
         $_[0]->_install_reverse_full_path_rel($mat_paths{$path});
      }
   };

sub insert {
   my $self = shift;

   my $ret = $self->next::method;

   my %mat_paths = %{$ret->materialized_path_columns};
   for my $path (keys %mat_paths) {
      $ret->_set_materialized_path($mat_paths{$path});
   }

   return $ret;
}

sub _set_materialized_path {
   my ($self, $path_info) = @_;

   my $direct     = $path_info->{direct_column};
   my $direct_fk  = $path_info->{direct_fk_column};
   my $path       = $path_info->{materialized_path_column};
   my $direct_rel = $path_info->{direct_relationship};

   # XXX: Is this completely necesary?
   $self->discard_changes;

   my $path_separator = $path_info->{separator} || '/';
   if ($self->get_column($direct)) { # if we aren't the root
      $self->set_column($path,
         $self->$direct_rel->get_column($path) .
            $path_separator .
            $self->get_column($direct_fk)
      );
   } else {
      $self->set_column($path, $self->$direct_fk );
   }

   $self->update
}

sub _install_after_column_change {
   my ($self, $path_info) = @_;

   for my $column (map $path_info->{$_}, qw(direct_column materialized_path_column)) {
      $self->after_column_change($column => {
         txn_wrap => 1,

         # XXX: is it worth installing this?
         method => sub {
            my $self = shift;

            my $rel = $path_info->{direct_reverse_relationship};
            $self->_set_materialized_path($path_info);
            __SUB__->($_) for $self->$rel->search({
               # to avoid recursion
               map +(
                  "me.$_" => { '!=' => $self->get_column($_) },
               ), $self->result_source->primary_columns
            })->all
         },
      });
   }
}

my %concat_operators = (
   'DBIx::Class::Storage::DBI::MSSQL' => '+',
);

sub _get_concat {
   my ($self, $rsrc) = @_;

   my $concat;
   for (keys %concat_operators) {
      return $concat_operators{$_} if $rsrc->storage->isa($_)
   }

   return '||'
}

sub _install_full_path_rel {
   my ($self, $path_info) = @_;

   $self->has_many(
      $path_info->{full_path} => $self,
      sub {
         my $args = shift;

         my $path_separator = $path_info->{separator} || '/';
         my $rest = "$path_separator%";

         my $fk = $path_info->{direct_fk_column};
         my $mp = $path_info->{materialized_path_column};
         my @me = (
            $path_info->{include_self_in_path}
            ?  {
               "$args->{self_alias}.$fk" => { -ident => "$args->{foreign_alias}.$fk" }
            }
            : ()
         );
         my $concat = $self->_get_concat($args->{self_resultsource});

         return ([{
               "$args->{self_alias}.$mp" => {
                  # TODO: add stupid storage mapping
                  -like => \["$args->{foreign_alias}.$mp" . " $concat ?",
                     [ {} => $rest ]
                  ],
               }
            },
            @me
         ],
         $args->{self_rowobj} && {
            "$args->{foreign_alias}.$fk" => {
               -in => [
                  grep {
                     $path_info->{include_self_in_path}
                        ||
                      $_ ne $args->{self_rowobj}->$fk
                  # TODO: should we use accessor instead of direct $mp?
                  } split qr(\Q$path_separator\E), $args->{self_rowobj}
                     ->get_column($mp)
               ]
            },
         });
      }
   );
}

sub _install_reverse_full_path_rel {
   my ($self, $path_info) = @_;

   $self->has_many(
      $path_info->{reverse_full_path} => $self,
      sub {
         my $args = shift;

         my $path_separator = $path_info->{separator} || '/';
         my $rest = "$path_separator%";

         my $fk = $path_info->{direct_fk_column};
         my $mp = $path_info->{materialized_path_column};

         my @me = (
            $path_info->{include_self_in_reverse_path}
            ?  {
               "$args->{foreign_alias}.$fk" => { -ident => "$args->{self_alias}.$fk" }
            }
            : ()
         );
         my $concat = $self->_get_concat($args->{self_resultsource});

         return [{
            "$args->{foreign_alias}.$mp" => {
               -like => \["$args->{self_alias}.$mp" . " $concat ?",
                  [ {} => $rest ]
               ],
            }
         }, @me ]
      }
   );
}

1;
