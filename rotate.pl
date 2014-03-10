#!/usr/bin/perl
$dev = 'Atmel Atmel maXTouch Digitizer';
$prop = 'Coordinate Transformation Matrix';

# Get the current matrix
$matrix = qx( xinput list-props '$dev'|grep '$prop' );
$matrix =~ s/^.+?:\s*//gs;
$matrix =~ s/\.\d+,?//gs;
chomp $matrix;

# Get the new value for the display and input
if( $matrix eq '1 0 0 0 1 0 0 0 1' ) {
	$matrix = '0 1 0 -1 0 1 0 0 1' ;
	$rotate = 'right';
} else {
	$matrix = '1 0 0 0 1 0 0 0 1' ;
	$rotate = 'normal';
}

# Commit the changes to the devices
qx( xrandr -o $rotate );
qx( xinput set-prop '$dev' '$prop' $matrix );

