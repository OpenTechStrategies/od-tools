#!/usr/bin/perl
#
# Copyright (C) 2008-2010 Aran Dunkley, Marcus Davy and others.
#
# Copyright (C) 2017 Open Tech Strategies, LLC  (modifications:
#   https://github.com/OpenTechStrategies/od-tools/blob/master/csv2wiki.pl)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
# http://www.gnu.org/copyleft/gpl.html
#
# - Original Source:  http://www.organicdesign.co.nz/csv2wiki.pl
# - Started: 2008-03-21
 
require( './wiki.pl' );

use Text::CSV;

$csv2wiki_version = '2.0.1'; # 2009-12-15
 
# Job, log and error files
$ARGV[0] or die "No job file specified!";
$ARGV[0] =~ /^(.+?)(\..+?)?$/;

$log = "$1.log";
$err = "$1.err";
$sep = ",";
$title_prefix = "Record-";

# Parse the job file
if ( open JOB, '<', $ARGV[0] ) {
	for ( <JOB> ) {
		if ( /^\*?\s*\$?csv\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )          { $csv = $1 }
		if ( /^\*?\s*\$?wiki\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )         { $wiki = $1 }
		if ( /^\*?\s*\$?user\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )         { $user = $1 }
		if ( /^\*?\s*\$?pass\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )         { $pass = $1 }
		if ( /^\*?\s*\$?title_prefix\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i ) { $title_prefix = $1 }
		if ( /^\*?\s*\$?sep(arator)?\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i ) { $sep = $2 }
	}
	close JOB;
} else { die "Couldn't parse job file!" }
  
# Log in to the wiki and open input file
wikiLogin( $wiki, $user, $pass ) or die "Couldn't log $user in to $wiki";

# Create a CSV parser.  The binary=>1 flag is needed for multiline fields, as per
# http://search.cpan.org/~ishigaki/Text-CSV-1.91/lib/Text/CSV.pm#Embedded_newlines
my $csv_parser = Text::CSV->new({ binary => 1 });

# Process the records
my %lut = ();
my $wptr = 0;
my @headings;

open(my $csv_stream, '<', $csv) or die "Couldn't open input file '$csv'!";
while ( my $row = $csv_parser->getline ($csv_stream) ) {
	my @fields = @$row;
        my $text = "";

	# If this is the first row, define the page headings.
	if ( $wptr == 0 ) {
		$lut{lc $fields[$_]} = $_ for 0 .. $#fields;
                @headings = @fields;
	}
	else {  # Build the record
		my $i = -1;
		for ( @fields ) {
			# s/^\s*(.+?)\s*$/$1/g;
			$text .= "== " . $headings[++$i] . " ==\n\n";
			$text .= "$_";
			$text .= "\n";
		}

                my $printable_number = sprintf("%03d", $wptr);
		$title = "${title_prefix}${printable_number}";

		# Update the article
		my $comment = "Generate this page using csv2wiki.pl.";
		wikiEdit( $wiki, $title, $text, $comment );

		# TODO: This part is specific to OTS's particular use
		# case.  It causes a MediaWiki-formatted list of all
		# the pages created to be printed on stdout.  The idea
		# is that you would take that output and paste it
		# directly into a top-level wiki page (e.g., "Proposals")
		# to serve as the TOC for all the created pages.  It
		# would be nice to generalize this so that it were
		# somehow controlled by the job file in a customizable way.
		print("* [[$title]]: '''$fields[0]''', $fields[5] ([$fields[4] YouTube])\n");
	}

	$wptr++;
}
