#!/usr/bin/php
<?php
$uniq = uniqid( 'f', true );
$strings1 = array();
$strings2 = array();
$comments1 = array();
$comments2 = array();
$code = file_get_contents( $argv[1] );

// Remove trailing whitespace
$code = preg_replace( '|^(.*?)[ \t]+$|m', '$1', $code );

// Make all newlines uniform UNIX style
$code = preg_replace( '|\r\n?|', "\n", $code );

// Protect all escaped quotes
$code = preg_replace( "|\\\\'|", "q1$uniq", $code );
$code = preg_replace( '|\\\\"|', "q2$uniq", $code );

// Protect all strings
$code = preg_replace_callback( "|'(.+?)'|", function( $m ) {
	global $strings1, $uniq;
	$strings1[] = $m[1];
	return "'s1$uniq'";
}, $code );
$code = preg_replace_callback( '|"(.+?)"|', function( $m ) {
	global $strings2, $uniq;
	$strings2[] = $m[1];
	return "\"s2$uniq\"";
}, $code );

// Protect comments
$code = preg_replace_callback( '|(?<=//)(.+?)$|m', function( $m ) {
	global $comments1, $uniq;
	$comments1[] = $m[1];
	return "c1$uniq";
}, $code );
$code = preg_replace_callback( '|(?<=/\*)(.+?)(?=\*/)|s', function( $m ) {
	global $comments2, $uniq;
	$comments2[] = $m[1];
	return "c2$uniq";
}, $code );

// Move orphan opening braces to previous line
$code = preg_replace( '#(?<=\S)\s*\{[ \t]*$#m', ' {', $code );
$code = preg_replace( '#(?<=\S)\s*\{([ \t]*//)#m', ' {$1', $code );

// Clean up brackets
$code = preg_replace_callback( '|\([ \t]*(.+?)[ \t]*\)|', function( $m ) {
	return '( ' . preg_replace( '|\s*,\s*|', ', ', $m[1] ) . ' )';
}, $code );

// Fix indenting
$indent = 0;
$code = preg_replace_callback( "|^(.+?)$|m", function( $m ) {
	global $indent;
	$i = preg_match( '#(\{|\()($|[ \t]*//)#', $m[1] );
	$o = preg_match( '#^\s*(\}|\))#', $m[1] );
	if( $i && $o ) $indent--;
	if( $o && !$i ) $indent--;
	$line = preg_replace( "|^\s*|", $indent > 0 ? str_repeat( "\t", $indent ) : '', $m[1] );
	if( $i ) $indent++;
	return $line;
}, $code );

// Put strings back
$code = preg_replace_callback( "|s1$uniq|", function( $m ) {
	global $strings1;
	return array_shift( $strings1 );
}, $code );
$code = preg_replace_callback( "|s2$uniq|", function( $m ) {
	global $strings2;
	return array_shift( $strings2 );
}, $code );

// Put comments back
$code = preg_replace_callback( "|c1$uniq|", function( $m ) {
	global $comments1;
	return array_shift( $comments1 );
}, $code );
$code = preg_replace_callback( "|c2$uniq|", function( $m ) {
	global $comments2;
	return array_shift( $comments2 );
}, $code );

// Put escaped quotes back
$code = preg_replace( "|q1$uniq|", "\\'", $code );
$code = preg_replace( "|q2$uniq|", '\\"', $code );

print $code;
