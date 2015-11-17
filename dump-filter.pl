#!/usr/bin/perl
#
# Filter a MySQL dump file to only contain a specific table/prefix
#
# Author: http://www.organicdesign.co.nz/nad
#

$args     = join ' ', @ARGV;
( $db, $tbl ) = ( $1, $2 ) if $args =~ /--filter=(\w+)\.(\S+)/;
$rename = $1 if $args =~ /--rename=(\w+)/;
$input  = $1 if $args =~ /--input=(\S+)/;
$output = $1 if $args =~ /--output=(\S+)/;

die "\nUsage:\n\n
	--input=input-dump-file.sql

	--output=output-dump-file.sql

	--filter=dbname.table-prefix | dbname.*

	--rename=new-table-prefix (optional)

" unless defined $input and defined $output and defined $db;

if( open INPUT, '<', $input ) {

	open OUTPUT, '>', $output
	
	$found = 0;
	$head = 1;
	$ourtbl = 0;
	$ourdb = 0;
	@databases = ();

	# Loop through the input dump pne line at a time
	for( <INPUT> ) {
		$line = $_;

		# Skip use statements
		next if $line =~ /^USE /;

		# Create database commands determine whether we're in our part of the dump
		if( $line =~ /^CREATE DATABASE.+?`(\w+)`/ ) {
			$head = 0;
			$ourdb = ( $1 eq $db )
		}

		else {

			# Create or drop table commands determine whether we're in our part of the database
			if( $line =~ /^(DROP TABLE IF EXISTS|CREATE TABLE).+?`(\w+)`/ ) {
				$head = 0;
				$ourtbl = ( $1 eq $tbl or $tbl eq '*' );
			}

			# If it's the dump header, or we're within our table and database add this line to the output dump
			if( $head or ( $ourtbl and ( $#databases >=0 or $ourdb ) ) ) {

				$line =~ s/`$tbl/`$rename/g if defined $rename;
				$found = 1;

				print OUTPUT $line;

			}


		}

	close INPUT;
	close OUTPUT;
}

print "\"$tbl\" not found\n" unless $found;
print "This is a multi-database dump containing the following databases: " . join( ', ', @databases ) . "\n" if $#databases >= 0;
