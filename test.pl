
use strict;

use Test;

my ($TABLE, @FIELDS, %ALIASES);

BEGIN {

  $TABLE  =     "TableName";
  @FIELDS = qw( One Two Three Four );

  %ALIASES = (
    $FIELDS[0] => "Uno",
    $FIELDS[2] => "Tres"
  );

  plan tests => 38 + (8 * @FIELDS);
};

use SQL::QueryBuilder::Simple qw( quote_name );
ok(1); # If we made it this far, we're ok.

ok( quote_name($TABLE), "\"$TABLE\"" );

my $obj = SQL::QueryBuilder::Simple->new();
ok( ref($obj), 'SQL::QueryBuilder::Simple' );

$obj->use_bindings(1);
ok($obj->use_bindings, 1);

ok(! $obj->sql);

$obj->table( $TABLE );
ok($obj->table(), $TABLE );

ok($obj->fields, 0);

my $Sql = "SELECT * FROM \"$TABLE\"";
ok($obj->sql, $Sql);

$obj->fields( undef );
ok($obj->fields, 0);

$obj->clear_fields;
ok($obj->fields, 0);

$obj->fields( @FIELDS );
ok(1);

my @Rfields = $obj->fields;
ok(@Rfields, @FIELDS);

for (my $i = 0; $i < @FIELDS; $i++) {
  ok($Rfields[ $i ], @FIELDS[ $i ]);
}

{
  my $Fields = join(", ", map { quote_name($_) } @FIELDS);
  $Sql =~ s/\*/$Fields/;
  ok($obj->sql, $Sql);
}


{
  $obj->aliases( %ALIASES );

  my %aliases = $obj->aliases;
  ok(1);

  ok(keys %aliases, @FIELDS);        # same number of keys as fields
  foreach my $field (@FIELDS) {
    ok($aliases{ $field }, $ALIASES{ $field });
  }

  my %names = $obj->report_field_names;
  ok(1);

  ok(keys %names, @FIELDS);          # same number of keys as fields

  foreach my $name (keys %names) {
    ok($names{$name});
  }

  foreach my $field (keys %aliases) {
    ok($names{ $aliases{ $field } || $field });
  }

  # Test Cumulative Aliases

  $obj->clear_aliases;
  ok($obj->sql, $Sql);

  my %aliases1 = %ALIASES;
  ok( defined $aliases1{ $FIELDS[0] } );

  my $alias0 = $aliases1{ $FIELDS[0] };
  $aliases1{ $FIELDS[0] } = undef;

  $obj->aliases( %aliases1 );
  $obj->aliases( $FIELDS[0] => $alias0 );

  my %aliases = $obj->aliases;
  ok(1);

  ok(keys %aliases, @FIELDS);        # same number of keys as fields
  foreach my $field (@FIELDS) {
    ok($aliases{ $field }, $ALIASES{ $field });
  }

  $obj->clear_aliases;
  ok($obj->sql, $Sql);

}


# Test that redefining fields clears the aliases
{
  # 1. re-create aliases
  $obj->aliases( $FIELDS[0] => "Uno", $FIELDS[2] => "Tres" );
  # 2. re-define fields
  $obj->fields( @FIELDS );

  # 3. test that no fields have aliases
  my %aliases = $obj->aliases;
  foreach my $field (@FIELDS) {
    ok($aliases{ $field }, undef);
  }

  # double-check SQL
  ok($obj->sql, $Sql);
}

{
  my %names = $obj->report_field_names;

  my @ORDER1 = map { "+$_" } (keys %names);

  $obj->order( @ORDER1 );
  ok(1);

  my @order = $obj->order;
  ok(@order, @ORDER1);

  for (my $i=0; $i<@ORDER1; $i++) {
    ok($order[$i], $ORDER1[$i]);
  }

  my @ORDER2 = map { "-$_" } (keys %names);

  $obj->order( @ORDER2 );
  ok(1);

  @order = $obj->order;
  ok(@order, @ORDER2);

  for (my $i=0; $i<@ORDER2; $i++) {
    ok($order[$i], $ORDER2[$i]);
  }

  $obj->order( undef );
  ok($obj->order, 0);

  $obj->order( @ORDER1 );
  ok(1);

  $obj->clear_order();
  ok($obj->order, 0);

}

{
  # we didn't defined any bindings yet
  ok( $obj->bindings, 0 );

  my %CLAUSE1 = (
    $FIELDS[0] => 0,
    $FIELDS[1] => undef,
    $FIELDS[2] => 1,
  );

  $obj->eq( %CLAUSE1 );
  ok( $obj->bindings, 2 );

  $obj->clear_clauses;
  ok( $obj->bindings, 0 );

  my %CLAUSE2 = (
    $FIELDS[0] => 1,
    $FIELDS[2] => [2, 3],
  );

  $obj->eq( %CLAUSE2 );
  ok( $obj->bindings, 3 );

  $obj->clear_clauses;
  ok( $obj->bindings, 0 );


  my %CLAUSE3 = (
    $FIELDS[0] => [1, 2, 3],
    $FIELDS[1] => undef,
    $FIELDS[2] => 4,
  );

  $obj->eq( %CLAUSE3 );
  ok( $obj->bindings, 4 );

  $obj->clear_clauses;
  ok( $obj->bindings, 0 );

  my $obj2 = SQL::QueryBuilder::Simple->new(
    table   => $TABLE,
    fields  => \@FIELDS,
    aliases => \%ALIASES,
    eq      => \%CLAUSE3,
  );
  ok( ref($obj2), 'SQL::QueryBuilder::Simple' );

}
