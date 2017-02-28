#!/usr/bin/perl
#
# Copyright (C) 2008-2010 Aran Dunkley, Marcus Davy and others.
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
# - Source:  http://www.organicdesign.co.nz/csv2wiki.pl
# - Started: 2008-03-21
 
# Todo
# Make it so that if there is no title then it increments
# $hashref = { $wikitext =~ /\{{3}(.+?)(\|.*?)?\}{3}/g }
require( './wiki.pl' );

use Text::CSV;

$csv2wiki_version = '2.0.1'; # 2009-12-15
 
# Job, log and error files
$ARGV[0] or die "No job file specified!";
$ARGV[0] =~ /^(.+?)(\..+?)?$/;

$log = "$1.log";
$err = "$1.err";
$sep = ",";
$multisep = "\n";
$title = 0;
$template = "Record";
$replace = 0;
$append = 0;
$titleformat = "";
%dups = ();

# Parse the job file
if ( open JOB, '<', $ARGV[0] ) {
	for ( <JOB> ) {
		if ( /^\*?\s*\$?csv\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )          { $csv = $1 }
		if ( /^\*?\s*\$?wiki\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )         { $wiki = $1 }
		if ( /^\*?\s*\$?user\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )         { $user = $1 }
		if ( /^\*?\s*\$?pass\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )         { $pass = $1 }
		if ( /^\*?\s*\$?sep(arator)?\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i ) { $sep = $2 }
		if ( /^\*?\s*\$?multisep\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )     { $multisep = $1 }
		if ( /^\*?\s*\$?title\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )        { $titleformat = $1 }
		if ( /^\*?\s*\$?template\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )     { $template = $1 } 
		if ( /^\*?\s*\$?replace\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )      { $replace = $1 }
		if ( /^\*?\s*\$?append\s*[:=]\s*['"]?(.+?)['"]?;?\s*$/i )       { $append = $1 }
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

open(my $csv_stream, '<', $csv) or die "Couldn't open input file '$csv'!";
while ( my $row = $csv_parser->getline ($csv_stream) ) {
	my @fields = @$row;

        print "KFF:\n";
        print "$fields[0]: $fields[5] ($fields[4])\n";
        print "$#fields\n";
        print "\n";

	# If this is the first row, define the columns and a reverse lookup
	if ( $wptr == 0 ) {
		# TODO: Some code removed here might actually have been
		# important for creating the page later.  Check back.
		$lut{lc $fields[$_]} = $_ for 0 .. $#fields;
	}
	else {  # Build the record as wikitext template syntax
		my $tmpl = "{{$template";
		my $i = -1;
		for ( @fields ) {
			s/^\s*(.+?)\s*$/$1/g;
			$tmpl .= $fields[++$i] ? "\n | $fields[$i] = $_" : ( $_ ? $multisep . $_ : '' );
		}
		$tmpl .= "\n}}";

		# Determine title for the record
		my $title = $titleformat;
		if ( $title ) {
			$title =~ s/\$(\w+)/ buildTitle( $1, \@fields ) /eg;
		} else {
			$title = wikiGuid();
		}

		if ( $replace ) {
			$text = $tmpl;
		} else {

			# Find the template in the wikitext if exists
			$text = wikiRawPage( $wiki, $title );
			for ( wikiExamineBraces( $text ) ) {
				( $pos, $len ) = ( $_->{OFFSET}, $_->{LENGTH} ) if $_->{NAME} eq $template;
			}

			# Replace, prepend or append the template into the current text 
			if ( defined $pos ) {
				substr $text, $pos, $len, $tmpl;
			} else {
				$text = $append ? "$text\n$tmpl" : "$tmpl\n$text";
			}
		}

		# Append (n) if duplicate title
		$n = ++$dups{$title};
		$title = "$title ($n)" if $n > 1;

		# Update the article
		print "Processing row $wptr ($title)\n";
		my $comment = "[[Template:$::template|$::template]] replacement using csv2wiki.pl";
		wikiEdit( $wiki, $title, $text, $comment );
	}

	$wptr++;
}
 
close CSV;

# Replace a token from the title format string with data
# - named indexes are case-insensitive
# - removes double spaces from result
sub buildTitle {
	my $i = shift;
	my $data = shift;
	my $title = $$data[ $i =~ /\D/ ? $::lut{lc $i} : $i - 1 ];
	$title =~ s/ +/ /g;
	return $title;
}

