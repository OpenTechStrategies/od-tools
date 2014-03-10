#!/usr/bin/perl
$dev = 'Atmel Atmel maXTouch Digitizer';
$matrix = qx( xinput list-props '$dev'|grep 'Coordinate Transformation Matrix' );
$matrix =~ s/^.+?:\s*//gs;
$matrix =~ s/\.\d+,?//gs;
chomp $matrix;
if( $matrix eq '1 0 0 0 1 0 0 0 1' ) {
	$matrix = '0 1 0 -1 0 1 0 0 1' ;
	$rotate = 'right';
}
else {
	$matrix = '1 0 0 0 1 0 0 0 1' ;
	$rotate = 'normal';
}
qx( xrandr -o $rotate );
qx( xinput set-prop '$dev' 'Coordinate Transformation Matrix' $matrix );

