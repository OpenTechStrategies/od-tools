<?php
/**
 * codeTidy cleans up PHP code to conform to the MediaWiki coding conventions
 * - see https://www.mediawiki.org/wiki/Manual:Coding_conventions
 * - and https://www.mediawiki.org/wiki/Manual:Coding_conventions/PHP
 *
 * @author Aran Dunkley [http://www.organicdesign.co.nz/aran Aran Dunkley]
 * @copyright © 2015 Aran Dunkley
 * @licence GNU General Public Licence 2.0 or later
 * 
 * Version 0.1 beta
 */

class CodeTidy {

	private static $uniq = 'BAQCmB6Z9txRD8xdE13SusTjBf9kH7n25DX5ZjJ9uXtU';
	private static $i;
	private static $indent;
	private static $strings1 = array();
	private static $strings2 = array();
	private static $comments1 = array();
	private static $comments2 = array();

	// Note, must be ordered from longest to shortest
	private static $ops = array(
		'===', '!==',
		'||', '&&', '+=', '-=', '*=', '/=', '.=', '%=', '==', '!=', '<=', '>=', '&=', '|=', '^=', 
		'<', '>', '=', '.', '+', '-', '*', '/', '%', '?', ':', '&', '|', '^',
	);

	function tidy( $code ) {
		self::$indent = 0;

		// Remove trailing whitespace
		$code = preg_replace( '|^(.*?)[ \t]+$|m', '$1', $code );

		// Make all newlines uniform UNIX style
		$code = preg_replace( '|\r\n?|', "\n", $code );

		// Protect all escaped quotes
		$code = preg_replace( "|\\\\'|", 'q1' . self::$uniq, $code );
		$code = preg_replace( '|\\\\"|', 'q2' . self::$uniq, $code );

		// Protect strings
		$code = preg_replace_callback( "|'(.+?)'|", function( $m ) {
			self::$strings1[] = $m[1];
			return "'s1" . self::$uniq . "'";
		}, $code );
		$code = preg_replace_callback( '|"(.+?)"|', function( $m ) {
			self::$strings2[] = $m[1];
			return "\"s2" . self::$uniq . "\"";
		}, $code );

		// Change old perl-style comments to double-slash
		$code = preg_replace( '|#(#*)|', '//$1', $code );

		// Protect comments
		$code = preg_replace_callback( '|(?<=/\*)(.+?)(?=\*/)|s', function( $m ) {
			self::$comments1[] = $m[1];
			return 'c1' . self::$uniq;
		}, $code );
		$code = preg_replace_callback( '|(?<=//)(.+?)$|m', function( $m ) {
			self::$comments2[] = $m[1];
			return 'c2' . self::$uniq;
		}, $code );

		// Move orphan opening braces to previous line
		$code = preg_replace( '#(?<=\S)\s*\{[ \t]*$#m', ' {', $code );
		$code = preg_replace( '#(?<=\S)\s*\{([ \t]*//)#m', ' {$1', $code );

		// Clean up brackets
		$code = preg_replace_callback( '|\([ \t]*(.+?)[ \t]*\)|', function( $m ) {
			return '( ' . preg_replace( '|\s*,\s*|', ', ', $m[1] ) . ' )';
		}, $code );

		// Fix indenting
		$code = preg_replace_callback( "|^(.+?)$|m", function( $m ) {
			$i = preg_match( '#(\{|\()($|[ \t]*//)#', $m[1] );
			$o = preg_match( '#^\s*(\}|\))#', $m[1] );
			if( $i && $o ) self::$indent--;
			if( $o && !$i ) self::$indent--;
			$line = preg_replace( "|^\s*|", self::$indent > 0 ? str_repeat( "\t", self::$indent ) : '', $m[1] );
			if( $i ) self::$indent++;
			return $line;
		}, $code );

		// Single space around operators
		foreach( self::$ops as self::$i => $op ) {
			$code = preg_replace_callback( '#[ \t]*(' . preg_quote( $op ) . '+)[ \t]*#', function( $m ) {
				return strlen( $m[1] ) == strlen( self::$ops[self::$i] ) ? 'o' . self::$i . self::$uniq : $m[0];
			}, $code );
		}
		foreach( self::$ops as $op ) {
			$code = preg_replace_callback( '#o([0-9]+)' . self::$uniq . '#', function( $m ) {
				return ' ' . self::$ops[$m[1]] . ' ';
			}, $code );
		}

		// Put strings back
		$code = preg_replace_callback( '|s1' . self::$uniq . '|', function( $m ) {
			return array_shift( self::$strings1 );
		}, $code );
		$code = preg_replace_callback( '|s2' . self::$uniq . '|', function( $m ) {
			return array_shift( self::$strings2 );
		}, $code );

		// Put comments back
		$code = preg_replace_callback( '|c1' . self::$uniq . '|', function( $m ) {
			return array_shift( self::$comments1 );
		}, $code );
		$code = preg_replace_callback( '|c2' . self::$uniq . '|', function( $m ) {
			return array_shift( self::$comments2 );
		}, $code );

		// Put escaped quotes back
		$code = preg_replace( '|q1' . self::$uniq . '|', "\\'", $code );
		$code = preg_replace( '|q2' . self::$uniq . '|', '\\"', $code );

		return $code;
	}
}

if( isset( $argv[1] ) ) {
	echo CodeTidy::tidy( file_get_contents( $argv[1] ) );
}
