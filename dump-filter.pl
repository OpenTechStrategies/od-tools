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
	$init = 1;
	$ourtbl = 0;
	$ourdb = 0;
	$curdb = 0;
	$curpre = 0;
	$lastpre = 0;
	@databases = ();
	%prefixes = ();

	# Loop through the input dump pne line at a time
	while( <INPUT> ) {
		$line = $_;

		# Skip USE statements and comments
		next if $line =~ /^(USE )/;

		# Keep initial comments
		if( $line =~ /^--/ ) {
			next unless $init;
		} else {
			$init = 0;
		}

		# Create database commands determine whether we're in our part of the dump
		if( $line =~ /^CREATE DATABASE.+?`(\w+)`/ ) {
			$curdb = $1;
			$pre = 0;
			$lastpre = 0;
			$curpre = 0;
			push @databases, $curdb;
			$head = 0;
			$ourdb = ( $1 eq $db );
		} else {

			# Create or drop table commands determine whether we're in our part of the database
			if( $line =~ /^(DROP TABLE IF EXISTS|CREATE TABLE).+?`(\w+)`/ ) {
				$curtbl = $2;
				$head = 0;
				$ourtbl = ( $curtbl =~ /^$tbl/ or $tbl eq '*' );

				# If the current table uses same prefix-like start and is same as previous add it to prefix list 
				$pre = $curtbl =~ /^(\w+?_)/ ? $1 : 0;
				if( $pre and $pre eq $lastpre ) { $curpre = $pre };
				$lastpre = $pre;
				$prefixes{$curdb}{$curpre} = 1 if $curpre;
			}

			# If it's the dump header, or we're within our table and database add this line to the output dump
			if( $head or ( $ourtbl and ( ( $#databases < 0 and $db eq '*' ) or $ourdb ) ) ) {
				$line =~ s/`$tbl/`$rename/g if defined $rename;
				$found = 1 unless $head;
				print OUTPUT $line;
			}
		}
	}
	close INPUT;
	close OUTPUT;
}

# Database/prefix found and exported
if( $found ) { print "\nSuccess.\n" }

# Not found, output details about the dump
else {
	unlink $output;
	print "\nNo tables founding matching the criteria (prefix \"$tbl\", database \"$db\").\n" unless $found;
	if( $#databases >= 0 ) {
		print "\nThis is a multi-database dump containing the following databases and table prefixes:\n";
		for $db ( @databases ) {
			print "\t$db\n";
			print "\t\t$_\n" for keys %{ $prefixes{$db} };
		}
		print "\nYou can't use '*' for the database name with a multi-database dump.\n" if $db eq '*';
	}
	else {
		print "\nThis is a single-database dump containing the following table prefixes:\n";
		print "\t$_\n" for keys %{ $prefixes{0} };
		print "\nYou must use '*' for the database name.\n" if $db ne '*';
	}
}
