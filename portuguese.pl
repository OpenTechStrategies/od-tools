#!/usr/bin/perl -w
#
# Brings up random portuguese lessons in dialog boxes randomly
#
# Should be run from crontab every minute, e.g. with the following crontab entry
# */1 * * * * root /var/www/tools/portuguese.pl
#
# Requires Debian packages perl-tk, libimage-size-perl
use Encode qw(encode decode);
use Tk;
use Tk::DialogBox;
use Tk::widgets qw/JPEG PNG/;
use Image::Size;

# Location of sentences.txt and the Pictures directory
$lessons = "/home/nad/Contacts/Beth/Lessons";

# Exit if an instance is already already running
exit 0 if qx( ps aux | grep portuguese-running | grep -v grep );

# Mark process as running and wait for 1 to 10 minutes
$t = int( 60 + rand( 540 ) );
$0 = "portuguese-running ($t seconds)";
sleep( $t );

# Read the list from the file
open FH, '<', "$lessons/sentences.txt";
$i = 0;
@lessons = ();
for( <FH> ) {
	chomp;
	if( /^.+$/ ) {
		push @lessons, $_;
		$i++;
	} else {
		push @lessons, "" if $i < 3;
		$i = 0;
	}
}
close FH;

# The number of lessons
$n = ( 1 + $#lessons ) / 3;

# Create a biased probability distribution of the lessons
# (the last lesson has $p times more chance of occurring than the first)
@biased = ();
$p = 10;
for $i ( 1 .. $n ) {
	$m = int( 1.5 + ( $p - 1 ) * $i / $n );
	push @biased, $i while $m--;
}

# Pick a random lesson from the probability-biased list
$lesson = 3 * $biased[ int( rand( 0.5 + $#biased ) ) ];

# Set up tk main window
$mw = MainWindow->new;
$mw->withdraw();

# Load image if any and make it 150px wide
( $q, $a ) = ( 0, 1 );
if( $img = $lessons[$lesson + 2] ) {
	$file = "$lessons/Pictures/$img";
	($w, $k) = imgsize( $file );
	$k = $w / 150;
	$image = $mw->Photo( -file => $file );
	$resized = $mw->Photo( 'resized' );
	$resized->copy( $image, -subsample => $k, $k );
} else { ( $q, $a ) = ( 1, 0 ) if rand() < 0.5 }

# Display the question dialog and wait for OK
%args = (
	-title   => "Question",
	-message => decode( "UTF-8", $lessons[$lesson + $q] ),
	-buttons => [ "Ok" ]
);
$args{-image} = $resized if defined $resized;
$mw->messageBox( %args );

# Display the answre dialog and wait for OK
$mw->messageBox(
	-title   => "Answer",
	-message => decode( "UTF-8", $lessons[$lesson + $a] ),
	-buttons => [ "Ok" ]
);

exit 0;
