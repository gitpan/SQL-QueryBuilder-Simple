package SQL::QueryBuilder::Simple;

use 5.006;
use strict;
use warnings;

use warnings::register __PACKAGE__;

use Carp qw( croak confess );

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw( quote_name ) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw( );

our $VERSION = '0.04';

my %METHOD_SYMBOLS;

sub new
  {
    my $class = shift;
    my $self  = { };
    bless $self, $class;
    $self->_init();

    if (@_) {
      my %methods = @_;
      foreach my $method (qw( table fields aliases order bindings any_clause ),
			  keys %METHOD_SYMBOLS ) {
	if (exists $methods{ $method }) {
	  my $value = $methods{ $method };
	  if (ref($value) eq "ARRAY")
	    {
	      $self->$method( @$value );	
	    }
	  elsif (ref($value) eq "HASH")
	    {
	      $self->$method( %$value );
	    }
	  else
	    {
	      $self->$method( $value );
	    }
	}
      }
    }

    return $self;
  }

sub _access
  {
    my $self  = shift;
    my $field = shift || confess "Expected field name";
    if (@_)
      {
	$self->{ __PACKAGE__ . "::" . $field } = shift;
      }
    else
      {
	return $self->{ __PACKAGE__ . "::" . $field };
      }
  }

sub _init
  {
    my $self = shift;

    if ( (keys %$self) and (warnings::enabled) ) {
      warnings::warn "Warning: object is already initialized";
    }

    my %INITIAL_VALUES = (
      TABLE        => "",    # name of the table
      FIELDS       => [ ],   # array of field names
      ALIASES      => { },   # keys are field names, values are aliases
      NAMES        => { },   # field or alias names
      ORDERING     => [ ],   # sorting order
      USE_BINDINGS => 1,     # not used at this time
      ANY_CLAUSE   => 1,     # true = OR, false = AND
    );

    foreach my $key (keys %INITIAL_VALUES) {
      $self->_access( $key, $INITIAL_VALUES{ $key } );
    }

    $self->clear_clauses;
  }

sub table
  {
    my $self = shift;
    if (@_)
      {
	$self->_access("TABLE", @_);
      }
    else
      {
	return $self->_access("TABLE");
      }
  }

sub fields
  {
    my $self = shift;
    if (@_)
      {
	my @field_list = @_;

	if (!defined $field_list[0])
	  {
	    @field_list = ( );
	  }

	$self->_access("FIELDS", \@field_list);

	$self->clear_aliases;
	$self->clear_order;
      }
    else
      {
	my $field_list_ref = $self->_access("FIELDS");
	return @$field_list_ref;
      }
  }

sub clear_fields
  {
    my $self = shift;
    $self->fields( undef );
  }

sub aliases
  {
    my $self = shift;

    if (@_)
      {
	my %aliases = @_;

	my $curr_aliases = $self->_access("ALIASES");

	foreach my $field (keys %aliases) {
	  if (exists $curr_aliases->{ $field })
	    {
	      $curr_aliases->{ $field } = $aliases{ $field };
	    }
	  else
	    {
	      croak "Invalid field: ", quote_name( $field );
	    }
	}

	$self->_access("ALIASES", $curr_aliases);

	my %names   = map { ($curr_aliases->{ $_ } || $_) => 1 }
	  (keys %$curr_aliases);

	$self->_access("NAMES", \%names);

      }
    else
      {
	my $alias_ref = $self->_access("ALIASES");
	return %$alias_ref;
      }
  }


sub clear_aliases
  {
    my $self = shift;

    my @fields  = $self->fields; # Danger: recursion
    my %aliases = map { $_ => undef } @fields;
    my %names = map { $_ => 1 } @fields;

    $self->_access("ALIASES", \%aliases );
    $self->_access("NAMES", \%names );
  }


sub report_field_names
  {
    my $self = shift;
    my $names = $self->_access("NAMES");
    return %$names;
  }

sub order
  {
    my $self = shift;

    if (@_)
      {
	my @field_list = @_;

	if (!defined $field_list[0])
	  {
	    @field_list = ( );
	  }

	my %names = $self->report_field_names;

	foreach my $sfield (@field_list)
	  {
	    unless ( ($sfield =~ m/^[+-](\w+)/) ) { # and ($names{$1}) ) {
	      croak "Invalid report field name \`$sfield\'";
	    }
	  }

	$self->_access("ORDERING", \@field_list);

      }
    else
      {
	my $field_list_ref = $self->_access("ORDERING");
	return @$field_list_ref;
      }

  }

sub clear_order
  {
    my $self = shift;
    $self->order( undef );
  }




sub quote_name
  {
    my $name = shift;
    if ($name =~ m/^\"*\"$/)
      {
	return $name;
      }
    else
      {
	return "\"$name\"";
      }
  }


sub sql
  {
    my $self = shift;

    unless ($self->use_bindings) {
      croak "Unimplemented feature: use_bindings() must be true";
    }

    unless ($self->table) {
      if (warnings::enabled) {
	warnings::warn "No table is defined: cannot generate SQL";
      }
      return;
    }

    my $sql_statement = "SELECT ";

    my @fields = $self->fields;

    if (@fields)
      {
	my %aliases = $self->aliases;

	$sql_statement .= join( ", ",
          map {
            my $fld = quote_name($_);
	    if (defined $aliases{ $_ }) {
	      $fld .= " AS " . quote_name( $aliases{ $_ } );
	    }
	    $fld;
          } @fields);

      }
    else
      {
	$sql_statement .= "*";
      }

    $sql_statement .=
      " FROM " . quote_name( $self->table );

    {

      my $where_clause = "";
      my $conn = ($self->any_clause) ? "OR" : "AND";

      sub eq_null {
	my ($field, $value, $sym) = @_;
	$sym ||= "=";
	if (defined $value) {
	  return quote_name($field) . $sym . "?";
	} else {
	  if ($sym eq "<>") {
	    return quote_name($field) . " IS NOT NULL";
	  } else {
	    return quote_name($field) . " IS NULL";
	  }
	}
      }

      foreach my $method (sort keys %METHOD_SYMBOLS) {

      my %clauses = $self->$method;
      if (keys %clauses)
	{
	  if ($where_clause) { $where_clause .= " $conn "; }

	  $where_clause .= join( " $conn ",
	    map {
	      my $fld;
	      if (ref( $clauses{$_} ) eq "ARRAY")
		{
		  my $aux = $_;
		  "(" .
                    join( ($method eq "eq")?" OR ":" AND ",
		      map { eq_null( $aux, $_, $METHOD_SYMBOLS{$method} ) }
			 @{$clauses{$aux}}
                    ) . ")";
		}
	      else
		{
		  eq_null( $_, $clauses{$_}, $METHOD_SYMBOLS{ $method } );
		}
	    } sort keys %clauses);

	}

      }

      if ($where_clause) {
	$sql_statement .= " WHERE " . $where_clause;
      }
    }


    {
      my @order = $self->order;
      if (@order) {
	$sql_statement .= " ORDER BY ";

	$sql_statement .= join( ", ",
	    map {
	      m/([+-])(\w+)/;
	      my $fld = quote_name($2) .
		( ($1 eq "-") ? " DESC" : " ASC" );
	      $fld;
	    } @order);
      }
    }

    return $sql_statement;
  }

sub bindings
  {
    my $self = shift;

    my @binds = ( );

    foreach my $method (sort keys %METHOD_SYMBOLS) {

      my %clauses = $self->$method;

      if (keys %clauses)
	{

	  push @binds, map {
	    my $field = $_;
	    my $value = $clauses{ $field };
	    if (defined $value) {
	      if (ref($value) eq "ARRAY") {
		@$value;
	      } else {
		$value;
	      }
	    } else {
	      # do nothing: don't even return an undef
	    }
	  } (sort keys %clauses);
	}

    }

    return @binds;

  }

sub clear_clauses
  {
    my $self = shift;

    foreach my $method (keys %METHOD_SYMBOLS) {
      $self->_access( uc($method), { } );
    }
  }


BEGIN
  {

    %METHOD_SYMBOLS = (
      'eq' => '=',
      'ne' => '<>',
      'lt' => '<',
      'gt' => '>',
      'le' => '<=',
      'ge' => '>=',
    );

    foreach my $method (keys %METHOD_SYMBOLS) {
    no strict 'refs';
    *$method = sub
      {
	my $self = shift;

	if (@_) {
	  my %clauses = @_;

# 	  my %names = $self->report_field_names;
# 
# 	  foreach my $sfield (keys %clauses) {
# 	    unless ($names{$sfield}) {
# 	      croak "Invalid report field name";
# 	    }
# 	  }

	  $self->_access(uc($method), \%clauses);
	} else {
	  my $clauses_ref = $self->_access(uc($method));
	  return %$clauses_ref;
	}
      };
    }

    foreach my $method (qw( use_bindings any_clause ) )
      {
	no strict 'refs';
	my $field   = uc($method);
	*$method = sub {
	  my $self = shift;
	  if (@_)
	    {
	      $self->_access($field, @_);
	    }
	  else
	    {
	      return $self->_access($field);
	    }
	};
      }
  }

1;
__END__

=head1 NAME

SQL::QueryBuilder::Simple - Generates simple SQL SELECT queries

=head1 REQUIREMENTS

This module is written for and tested on Perl 5.6.0.

It uses only standard modules.

=head2 Installation

Installation is pretty standard:

  perl Makefile.PL
  make
  make test
  make install

=head1 SYNOPSIS

  use SQL::QueryBuilder::Simple;

  my $query = SQL::QueryBuilder::Simple->new(
    table  => "MYTABLE",            # from table MYTABLE
    fields => [ qw( FLD1 FLD2 ) ],  # select fields FLD1, FLD2
    ne     => { FLD1 => -1 },       # where FLD1 not equal to -1
  );

  print $query->sql; # SELECT FLD1, FLD2 FROM MYTABLE WHERE FLD1<>?

  use DBI;

  my $dbh = DBI->connect( ... ) or die;
  my $sth = $dbh->prepare( $query->sql ) or die;

  $sth->execute( $query->bindings ) or die;

=head1 DESCRIPTION

This module generates simple SQL select statements and manages binding
parameters, to simplify generating dynamic queries.

This module will only generate SQL code. It does not validate the code,
nor does it check against any database to see if table or field names
are valid.

=head2 METHODS

=over

=item new

  $obj = SQL::QueryBuilder::Simple->new( %PARAMTETERS );

Creates a new object. Optional parameters (corresponding to most method
names below) can be specified to configure the query.

=item table

  $obj->table( $TABLENAME );

  $TABLENAME = $obj->table;

Sets the table or view used in the query. Only one table may be specified.
If it is called without arguments, it returns the name of the table.

=item fields

  $obj->fields( @FIELDS );

  @FIELDS = $obj->fields;

Sets the fields to be returned from the table.  If none set set, the
query will default to selecting all fields.  Redefining C<fields>
will clear any defined C<aliases> and C<order>.

If it is called without any arguments, it returns an array of field names.

If called as a parameter within the C<new> method, the argument must be
an array reference.

=item clear_fields

  $obj->clear_fields;

Clear all defined fields. The query will default to selecting all fields.

=item aliases

  $obj->aliases( %ALIASES );

  %ALIASES = $obj->aliases;

Defines aliases for field names. For example,

  $query->aliases( FLD1 => "First", FLD2 => "Second" );

Note that aliases are cumulative (unlike other methods, where calls will
redefine related values). The following is equivalent to the
above example:

  $query->aliases( FLD1 => "First" );
  $query->aliases( FLD2 => "Second" );

If called as a parameter within the C<new> method, the argument must be
a hash reference.

=item clear_aliases

  $obj->clear_aliases;

Clear all defined aliases.

=item report_field_names

  %NAMES = $obj->report_field_names;

Returns a hash where the keys are the field names (or alias names instead).

=item eq

  $obj->eq( %EQUALS );

  %EQUALS = $obj->eq;

Sets FIELD=VALUE WHERE clauses. The hash keys are field names or aliases,
and the hash values are the values are the values that the fields should be
equal to.  For example,

  $query->eq( FLD1 => 0 );

will require that FLD1 be equal to 0. (In SQL examples, we will use something
like "WHERE FLD1=0", but in reality the object generates SQL with binding
parameters: "WHERE FLD1=?"; see C<bindings> for more information).

If the value is an array reference, it will require that the field be
one of those values:

  $query->eq( FLD1 => [1, 4] );

will translate to "WHERE (FLD1=1 OR FLD1=4)" in SQL.

When the value is undefined:

  $query->eq( FLD1 => undef );

will translate to "WHERE FLD IS NULL" in SQL (requiring a NULL value).

Multiple fields may be specified:

  $query->eq( FLD1 => [1, 4], FLD2 => 0, FLD3 => undef, );

In the above example, the query will require that any of the above 
restrictions be true (connected by "OR").  If you want to require that
all of them be true (connected by "AND"), set C<any_clause> to false.

Note that there is no way to specify the order of the conditions in the
clause, which is why only simple connectors are used.

Redefining this method will overwrite existing clauses.

If called as a parameter within the C<new> method, the argument must be
a hash reference.

=item ne

  $obj->ne( %NOT_EQUALS );

  %NOT_EQUALS = $obj->ne;

Specify inequalities for the query (fields not be equal to values).

Similar to C<eq>, with some exceptions: when passed an array reference,
the connector will be "AND" instead of "OR":

  $query->ne( FLD1 => [1, 4] );

will translate to "WHERE (FLD1<>1 AND FLD1<>4)" in SQL.

If called as a parameter within the C<new> method, the argument must be
a hash reference.

It is possible to use multple clauses for a query:

  $query->ne( FLD1 => 1 );
  $query->eq( FLD2 => "Bob" );
  $query->any_clause(0);       # require all clauses

returns "WHERE FLD1<>1 AND FLD2='Bob'" in SQL.

=item lt

  $obj->lt( %LESS_THAN );

  %LESS_THAN = $obj->lt;

Specify that fields be less than values for the query.

Similar to C<eq>, except that array references or undefined values will
produce nonsense results (read: undocumented and unsupported).

If called as a parameter within the C<new> method, the argument must be
a hash reference.

=item gt

Specify that fields be greater than values for the query. See C<lt>.

=item le

Specify that fields be less than or equal to values for the query. See C<lt>.

=item ge

Specify that fields be greater than or equal to values for the query.
See C<lt>.

=item any_clause

  $query->any_clause(0);

  if ($query->any_clause) { ... }

If true (default), the query will require that I<any> clause be true.  If
false, the query will require I<all> clauses to be true.  For example,

  $query->any_clause(1);
  print $query->sql;     # SELECT * FROM FOO WHERE A=? OR B=?

  $query->any_clause(0);
  print $query->sql;     # SELECT * FROM FOO WHERE A=? AND B=?

This method may also be specified as a parameter in the C<new> method.

=item clear_clauses

  $query->clear_clauses;

Remove all defined clauses.

=item order

If called as a parameter within the C<new> method, the argument must be
an array reference.

=item clear_order

  $query->clear_order;

Remove defined sorting orders.

=item sql

  $SQL_STATEMENT = $obj->sql;

Returns the SQL statement.

=item bindings

  @BINDING_PARAMS = $obj->bindings();

Returns the actual binding parameters used for DBI, in the same order as
the corresponding SQL statement generated by C<sql>.  For example:

  use DBI;

  my $dbh = DBI->connect( ... ) or die;
  my $sth = $dbh->prepare( $query->sql ) or die;

  $sth->execute( $query->bindings ) or die;

=item use_bindings

  $obj->use_bindings(1);

  if ($obj->use_bindings) { ... }

When true (default>, generate SQL with binding parameters rather than with
values plugged in.  When false, C<sql> will produce an error because the
feature is not yet implemented.

=back

=head2 EXPORT

None by default. The following subroutines may be specified manually:

=over

=item quote_name

A utility routine which surrounds a name with quotes.

=back

=head1 KNOWN ISSUES

This module implements simple SQL queries against tables and views.
Joined tables, functions, and many clauses such as BETWEEN or IN are
not supported.

Complex where clauses beyond any/all are not supported.

C<sql> cannot run when C<use_bindings> is false.  This feature is not yet
implemented.

See the TODO file in this distribution for future features.

=head1 SEE ALSO

There are similar modules available on CPAN.  Many of these modules
incorporate database connections and execute the queries, which in
some cases is too much functionality.  However, these may be more
suited to your needs.  Some of them are listed below:

  DBIx::SearchBuilder
  Relations::Query
  Text::Query::SQL

=head1 AUTHOR

Robert Rothenberg <rrwo@cpan.org>

=head1 LICENSE

Copyright (c) 2001 Robert Rothenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut


