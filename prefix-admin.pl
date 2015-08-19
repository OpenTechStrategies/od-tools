#!/usr/bin/perl
# 
#  Tool for dumping, copying or deleting groups of tables by common prefix
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#  

use DBI;
use Term::ReadPassword;

# Validate command and get option values
$valid = 0;
if( $#ARGV > 2 ) {
	( $user, $db1, $pre1, $cmd, $db2, $pre2 ) = @ARGV;
	if( $cmd eq '--dump' or $cmd eq '--delete' or ( $cmd eq '--copy' && $#ARGV == 5 ) ) { $valid = 1 }
}

# Show syntax if not valid
die "\nAdminister database tables by table prefix.

Usage:
	preifx-admin USER DBNAME PREFIX --dump FILENAME

	   or

	prefix-admin USER DBNAME PREFIX --delete

	   or

	prefix-admin USER DBNAME PREFIX --copy DBNAME PREFIX



" unless $valid;

# Get database password
$pass = read_password( 'Enter password: ' );

# Connect to the db this wiki is in
$dbh = DBI->connect( "dbi:mysql:$db1", $user, $pass )
	or die "\nCan't connect to database '$db1': ", $DBI::errstr, "\n";

# Do the dump command
if( $ARGV[3] eq '--dump' ) {
	$file = $db2;
	@tables = getTables( $pre1 );
	die "\nNo tables found with prefix \"$pre1\"\n" if $#tables < 0;
	$tables = join( ' ', @tables );
	qx( mysqldump -u $user --password='$pass' $db1 $tables > "$file" );
}

# Do the delete command
elsif( $ARGV[3] eq '--delete' ) {
	$bak = '/tmp/' . $db1 . '_' . $pre1 . time() . '.sql';
	@tables = getTables( $pre1 );
	die "\nNo tables found with prefix \"$pre1\"\n" if $#tables < 0;
	$tbl = join( ' ', @tables );
	qx( mysqldump -u $user --password='$pass' $db1 $tbl > "$bak" );
	print "Tables backed up in \"$bak\"\n";
	for( @tables ) {
		#print "\tDropping table \`$_\`\n";
		$sth = $dbh->prepare( "DROP TABLE `$_`" );
		$sth->execute() or die "\nCould not drop table: ", $DBI::errstr, "\n";
	}
	print "" . (1 + $#tables) . " tables dropped.\n";
}

# Do the copy command
elsif( $ARGV[3] eq '--copy' ) {

	# Dump first db.pre
	$tmp1 = '/tmp/' . $db1 . '_' . $pre1 . time() . '.sql';
	@tables = getTables( $pre1 );
	$n = 1 + $#tables;
	$tables = join( ' ', @tables );
	qx( mysqldump -u $user --password='$pass' $db1 $tables > "$tmp1" );

	# Change connection to seconds db (if different)
	if( $db1 ne $db2 ) {
		$dbh = DBI->connect( "dbi:mysql:$db2", $user, $pass )
			or die "\nCan't connect to database '$db2': ", $DBI::errstr, "\n";
	}

	# Backup second db.pre tables
	$tmp2 = '/tmp/' . $db2 . '_' . $pre2 . time() . '.sql';
	@tables = getTables( $pre2 );
	print "Target tables backed up in \"$tmp2\"\n";

	# Delete the tables first (if they exist)
	for( @tables ) {
		$sth = $dbh->prepare( "DROP TABLE `$_`" );
		$sth->execute() or die "\nCould not drop table: ", $DBI::errstr, "\n";
	}
	print "" . (1 + $#tables) . " tables dropped.\n";

	# Rename tables in dump
	if( $pre1 ne $pre2 ) {
		qx( perl -pi -w -e 's/\`$pre1/`$pre2/g;' $tmp1 );
		print "Table prefixes renamed from \"$pre1\" to \"$pre2\"\n";
	}

	# Import tables
	qx( mysql -u $user --password="$pass" $db2 < $tmp1 );
	print "$n tables copied from \"$db1\" to \"$db2\"\n";

}

# Return a list of all the tables having the passed prefix
sub getTables {
	my $pre = shift;
	@tbl = ();
	$sth = $dbh->prepare( 'SHOW TABLES' );
	$sth->execute() or die "\nCould not select tables: ", $DBI::errstr, "\n";
	while ( @data = $sth->fetchrow_array() ) { push @tbl, $data[0] if $data[0] =~ /^$pre/ }
	return @tbl;
}
