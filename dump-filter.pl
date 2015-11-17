#!/usr/bin/perl
#
# Filter a MySQL dump file to only contain a specific table/prefix
#
# Author: http://www.organicdesign.co.nz/nad
#

$db = $ARGV[...];
$tb = $ARGV[...];
$input = $ARGV[...];
$output = $ARGV[...];

if( open INPUT, '<', $input ) {

	open OUTPUT, '>', $output
	
	$found = 0;
	$head = 1;
	$ourtbl = 0;
	$ourdb = 0;
	@databases = ();

	for( <INPUT> ) {
		$line = $_;

		if( $line =~ /CREATE DATABASE `(.+?)`/ ) {
			$head = 0;
			$ourdb = ( $1 eq $db )
		}

		else {

			if( $line =~ /CREATE TABLE `(.+?)`/ ) {
				$head = 0;
				$ourtbl = ( $1 eq $tbl );
			}

			if( $head or ( $ourtbl and ( $#databases >=0 or $ourdb ) ) ) {

				$line =~ s/`old/`new/g;
				$found = 1;

				print OUTPUT $line;

			}


		}

	close INPUT;
	close OUTPUT;
}

print "\"$tbl\" not found\n" unless $found;
print "This is a multi-database dump containing the following databases: " . join( ', ', @databases ) . "\n" if $#databases >= 0;
