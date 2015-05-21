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

	// Operator-like things that shouldn't have space modified
	private static $nops = array( '<?', '::', '//', '/*', '*/', '->', '=>', '@' );

	/**
	 * Main entry point, tidt the passed PHP file content
	 */
	public static function tidy( $code ) {

		// Format the code into a uniform state ready for processing
		self::preprocess( $code );

		// Loop through all PHP sections in the content and tidy each
		// (but not ones that are a single line since it may mess up HTML formatting)
		$code = preg_replace_callback( "%<\?(php)?(.+?)(\?>|$)%s", function( $m ) {
			return preg_match( "|\n|", $m[2] ) ? "<?php\n" . self::tidySection( $m[2] ) . "\n?>" : "<?php$m[2]$m[3]";
		}, $code );

		// Remove the final delimiter if any
		$code = preg_replace( '|\s*\?>\s*$|', '', $code );

		return $code;
	}

	/**
	 * Tidy a single PHP section of code (without delimeters)
	 */
	private static function tidySection( $code ) {
		self::$indent = 0;

		// Move orphan opening braces to previous line
		$code = preg_replace( '%(?<=\S)\s*\{[ \t]*$%m', ' {', $code );
		$code = preg_replace( '%(?<=\S)\s*\{([ \t]*//)%m', ' {$1', $code );

		// Put a newline after braces
		$code = preg_replace( '%\{%m', "{\n", $code );

		// Clean up brackets
		$code = preg_replace_callback( '|\([ \t]*(.+?)[ \t]*\)|', function( $m ) {
			return '( ' . preg_replace( '|\s*,\s*|', ', ', $m[1] ) . ' )';
		}, $code );
		$code = str_replace( '))', ') )', $code );

		// Fix indenting
		$code = preg_replace( '|\}\s*else\s*\{|', '} else {', $code );
		$code = preg_replace( '|^(\s*\S+\S*\{)\s*(?!=\/)(\S+.+?$)|', "$1\n$2", $code );
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
		foreach( self::$nops as self::$i => $nop ) {
			$code = preg_replace_callback( '#' . preg_quote( $nop ) . '#', function( $m ) {
				return 'n' . self::$i . self::$uniq;
			}, $code );
		}
		foreach( self::$ops as self::$i => $op ) {
			$code = preg_replace_callback( '#[ \t]*(' . preg_quote( $op ) . '+)[ \t]*#', function( $m ) {
				return strlen( $m[1] ) == strlen( self::$ops[self::$i] ) ? 'o' . self::$i . self::$uniq : $m[0];
			}, $code );
		}
		foreach( self::$ops as $nop ) {
			$code = preg_replace_callback( '#n([0-9]+)' . self::$uniq . '#', function( $m ) {
				return self::$nops[$m[1]];
			}, $code );
		}
		foreach( self::$ops as $op ) {
			$code = preg_replace_callback( '#o([0-9]+)' . self::$uniq . '#', function( $m ) {
				return ' ' . self::$ops[$m[1]] . ' ';
			}, $code );
		}

		// Put all the preserved content back in place
		self::postprocess( $code );

		// Allow only single empty lines
		$code = preg_replace( '%\n\n+%', "\n\n", $code );

		return trim( $code );
	}

	/**
	 * Format the code into a uniform state ready for processing
	 * - this is done to the whole file not just the PHP,
	 * - becuase strings and comments may contain symbols that confuse the process
	 */
	private static function preprocess( &$code ) {

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
			return "'s1" . ( count( self::$strings1 ) - 1 ) . self::$uniq . "'";
		}, $code );
		$code = preg_replace_callback( '|"(.+?)"|', function( $m ) {
			self::$strings2[] = $m[1];
			return "\"s2" . ( count( self::$strings2 ) - 1 ) . self::$uniq . "\"";
		}, $code );

		// Change old perl-style comments to double-slash
		$code = preg_replace( '|#(#*)|', '//$1', $code );

		// Protect comments
		$code = preg_replace_callback( '|(?<=/\*)(.+?)(?=\*/)|s', function( $m ) {
			self::$comments1[] = $m[1];
			return 'c1' . ( count( self::$comments1 ) - 1 ) . self::$uniq;
		}, $code );
		$code = preg_replace_callback( '|(?<=//)(.+?)$|m', function( $m ) {
			self::$comments2[] = $m[1];
			return 'c2' . ( count( self::$comments2 ) - 1 ) . self::$uniq;
		}, $code );
	}

	/**
	 * Put all the preserved content back in place
	 */
	private static function postprocess( &$code ) {

		// Put comments back
		$code = preg_replace_callback( '|c1([0-9]+)' . self::$uniq . '|', function( $m ) {
			return self::$comments1[$m[1]];
		}, $code );
		$code = preg_replace_callback( '|c2([0-9]+)' . self::$uniq . '|', function( $m ) {
			return self::$comments2[$m[1]];
		}, $code );

		// Put strings back
		$code = preg_replace_callback( '|s1([0-9]+)' . self::$uniq . '|', function( $m ) {
			return self::$strings1[$m[1]];
		}, $code );
		$code = preg_replace_callback( '|s2([0-9]+)' . self::$uniq . '|', function( $m ) {
			return self::$strings2[$m[1]];
		}, $code );

		// Put escaped quotes back
		$code = preg_replace( '|q1' . self::$uniq . '|', "\\'", $code );
		$code = preg_replace( '|q2' . self::$uniq . '|', '\\"', $code );
	}

}

if( isset( $argv[1] ) ) {
	echo CodeTidy::tidy( file_get_contents( $argv[1] ) );
}
