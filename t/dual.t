use strict;
use warnings;

use Test::More;

use lib 't/lib';

use A::Schema;

my $s = A::Schema->connect('dbi:SQLite::memory:');
$s->deploy;

my $adam = $s->resultset('Human')->create({
   name => 'Adam',
});

my $eve = $s->resultset('Human')->create({
   name => 'Eve',
});

my $cain = $adam->sons->create({
   dad_id => $adam->id,
   name => 'Cain',
   mom_id => $eve->id,
});

my $lillith = $cain->daughters->create({
   dad_id => $cain->id,
   name => 'Lillith', # I know this is false, but it's a test.
});

use Devel::Dwarn;
Dwarn [$lillith->dad_id];
Dwarn [$lillith->paternal_lineage->get_column('id')->all];
Dwarn $lillith->dad_path;

Dwarn [$lillith->mom_id];
Dwarn [$lillith->maternal_lineage->get_column('id')->all];
Dwarn $lillith->mom_path;

done_testing;
