#!/usr/bin/perl
#
# Filter a MySQL dump file to only contain a specific table/prefix
#
# Author: http://www.organicdesign.co.nz/nad
#

$args     = join ' ', @ARGV;
( $db, $tbl ) = ( $1, $2 ) if $args =~ /--filter=(\S+)\.(\S+)/;
$rename = $1 if $args =~ /--rename=(\w+)/;
$input  = $1 if $args =~ /--input=(\S+)/;
$output = $1 if $args =~ /--output=(\S+)/;

die "\nUsage:
	--input=input-dump-file.sql

	--output=output-dump-file.sql

	--filter=dbname.table-prefix | dbname.* | *.table-prefix

	--rename=new-table-prefix (optional)

" unless defined $input and defined $output and defined $db;

if( open INPUT, '<', $input ) {

	open OUTPUT, '>', $output;
	
	$found = 0;
	$head = 1;
	$ourtbl = 0;
	$ourdb = 0;
	@databases = ();

	# Loop through the input dump pne line at a time
	while( <INPUT> ) {
		$line = $_;

		# Skip use statements
		next if $line =~ /^USE /;

		# Create database commands determine whether we're in our part of the dump
		if( $line =~ /^CREATE DATABASE.+?`(\w+)`/ ) {
			push @databases, $1;
			$head = 0;
			$ourdb = ( $1 eq $db )
		} else {

			# Create or drop table commands determine whether we're in our part of the database
			if( $line =~ /^(-- Table structure for table|DROP TABLE IF EXISTS|CREATE TABLE).+?`(\w+)`/ ) {
				$head = 0;
				$ourtbl = ( $1 =~ /^$tbl/ or $tbl eq '*' );
			}

			# If it's the dump header, or we're within our table and database add this line to the output dump
			if( $head or ( $ourtbl and ( $#databases < 0 or $ourdb ) ) ) {
				$line =~ s/`$tbl/`$rename/g if defined $rename;
				$found = 1 unless $head;
				print OUTPUT $line;
			}
		}
	}
	close INPUT;
	close OUTPUT;
}

if( $found ) { print "\nSuccess.\n" }
else {
	print "\nNo tables with prefix \"$tbl\" found.\n" unless $found;
	if( $#databases >= 0 ) {
		print "\nThis is a multi-database dump containing the following databases:\n\t" . join( "\n\t", @databases ) . "\n";
		print "\nYou can't use '*' for the database name with a multi-database dump.\n" if $db eq '*';
	}
	elsif( $db ne '*' ) { print "\nThis dump contains only a single database, so you must use '*' for the database name.\n" }
}
