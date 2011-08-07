#!/usr/bin/perl -w
use Tk;
use Tk::DialogBox;
use Encode qw(encode decode);

# Run from crontab every minute
# e.g. */1 * * * * root /var/www/tools/portuguese.pl

# Read the list from the file
open FH, '<', "$0.txt";
push @lessons, $_ for grep /^.+/, <FH>;
close FH;

# Exit if already running
exit if qx( ps aux | grep portuguese-running | grep -v grep );
$0 = "portuguese-running";

# Wait for a random time
sleep( 60 + rand( 600 ) );

# Pick a lesson from the list
$n = int( rand( 0.5 + $#lessons / 2 ) ) * 2;
( $q, $a ) = rand() < 0.5 ? ( 0, 1 ) : ( 1, 0 );

$d = MainWindow->new;
$d->withdraw();

$d->messageBox(
	-title   => "Question",
	-message => decode( "UTF-8", $lessons[$n + $q] ),
	-buttons => [ "Ok" ],
	-display => ":1"
);

$d->messageBox(
	-title   => "Answer",
	-message => decode( "UTF-8", $lessons[$n + $a] ),
	-buttons => [ "Ok" ],
	-display => ":1"
);

