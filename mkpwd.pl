#!/usr/bin/perl
#
# Makes 10 character passwords, parameter if used specifies number of passwords to make
#
sub rnd { return int(rand()*shift) }
$a = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
$s = '~!@#$%^&*()-_+={}[]:;/?.,<>|';
for( 1 .. ($ARGV[0] ? $ARGV[0] : 1) ) {
	$pwd = '';
	$pwd .= substr($a,rnd(length $a),1) for (0..rnd(3));
	$pwd .= substr($s,rnd(length $s),1);
	$pwd .= substr($a,rnd(length $a),1) for (1..rnd(3));
	$pwd .= substr($s,rnd(length $s),1);
	$pwd .= substr($a,rnd(length $a),1) for (1..rnd(3));
	$pwd .= substr($s,rnd(length $s),1);
	$pwd .= substr($a,rnd(length $a),1) while length $pwd < 10;
	print "$pwd\n" ;
}

