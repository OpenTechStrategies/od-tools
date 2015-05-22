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
	private static $j;
	private static $opData;
	private static $indent;
	private static $strings1 = array();
	private static $strings2 = array();
	private static $comments1 = array();
	private static $comments2 = array();

	// Note, must be ordered from longest to shortest
	// ( operator, space before, space after ) false means don't touch the space state
	private static $ops = array(
		array( '===', 1, 1 ),
		array( '!==', 1, 1 ),
		array( '||', 1, 1 ),
		array( '&&', 1, 1 ),
		array( '+=', 1, 1 ),
		array( '-=', 1, 1 ),
		array( '*=', 1, 1 ),
		array( '/=', 1, 1 ),
		array( '.=', 1, 1 ),
		array( '%=', 1, 1 ),
		array( '==', 1, 1 ),
		array( '!=', 1, 1 ),
		array( '<=', 1, 1 ),
		array( '>=', 1, 1 ),
		array( '&=', 1, 1 ),
		array( '|=', 1, 1 ),
		array( '^=', 1, 1 ),
		array( '<?', false, false ),
		array( '::', 0, 0 ),
		array( '//', false, false ),
		array( '/*', false, false ),
		array( '*/', false, false ),
		array( '->', 0, 0 ),
		array( '=>', 1, 1 ),
		array( '<', 1, 1 ),
		array( '>', 1, 1 ),
		array( '=', 1, 1 ),
		array( '.', 1, 1 ),
		array( '+', 1, 1 ),
		array( '-', 1, 1 ),
		array( '*', 1, 1 ),
		array( '/', 1, 1 ),
		array( '%', 1, 1 ),
		array( '?', 1, 1 ),
		array( ':', 1, 1 ),
		array( '&', 1, 1 ),
		array( '|', 1, 1 ),
		array( '^', 1, 1 ),
		array( '@', false, 0 ),
		array( '!', false, 0 ),
		array( ')', 1, false ),
		array( '(', false, 1 ),
	);

	/**
	 * Main entry point, tidt the passed PHP file content
	 */
	public static function tidy( $code ) {

		// Cleat indenting state (continues across sections)
		self::$indent = 0;

		// Format the code into a uniform state ready for processing
		self::preprocess( $code );

		// Loop through all PHP sections in the content and tidy each
		// (but not ones that are a single line since it may mess up HTML formatting)
		$code = preg_replace_callback( "%<\?(php)?(.+?)(\?>|$)%s", function( $m ) {
			return preg_match( "|\n|", $m[2] ) ? "<?php\n" . self::tidySection( $m[2] ) . "\n?>" : "<?php$m[2]$m[3]";
		}, $code );

		// Put all the preserved content back in place
		self::postprocess( $code );

		// Remove the final delimiter if any
		$code = preg_replace( '|\s*\?>\s*$|', '', $code );

		return $code;
	}

	/**
	 * Tidy a single PHP section of code (without delimeters)
	 */
	private static function tidySection( $code ) {

		// Put a newline after braces
		$code = preg_replace( '%\{(?!\n)%m', "{\n", $code );

		// Move orphan opening braces to previous line
		$code = preg_replace( '%(?<=\S)\s*\{[ \t]*$%m', ' {', $code );
		$code = preg_replace( '%(?<=\S)\s*\{([ \t]*//)%m', ' {$1', $code );

		// Fix indenting
		$code = preg_replace( '%\}\s*else\s*\{%', '} else {', $code );
		$code = preg_replace( '%^(\s*\S+\S*\{)\s*(?!=\/)(\S+.+?$)%', "$1\n$2", $code );
		$code = preg_replace_callback( "%^(.+?)$%m", function( $m ) {
			$i = preg_match( '%(\{|\(|^\s*case.+?:)($|[ \t]*//)%', $m[1] );
			$o = preg_match( '%^\s*(\}|\)|break;)%', $m[1] );
			if( $i && $o ) self::$indent--;
			if( $o && !$i ) self::$indent--;
			$line = preg_replace( "%^\s*%", self::$indent > 0 ? str_repeat( "\t", self::$indent ) : '', $m[1] );
			if( $i ) self::$indent++;
			return $line;
		}, $code );

		// Operator spacing
		self::$i = 0;
		self::$opData = array();
		foreach( self::$ops as self::$j => $op ) {
			$before = $op[1];
			$after = $op[2];
			$op = preg_quote( $op[0] );
			$code = preg_replace_callback( "#(\n?)([ \t]*)$op([ \t]*)(\n?)#", function( $m ) {
				self::$i++;
				self::$opData[self::$i] = array( self::$j, $m[1], $m[2], $m[3], $m[4] );
				return 'o' . self::$i . self::$uniq;
			}, $code );
		}
		foreach( self::$opData as $i => $data ) {
			$code = preg_replace_callback( "%o($i)" . self::$uniq . '%', function( $m ) {
				list( $op, $newline, $before, $after, $endline ) = self::$opData[$m[1]];
				$op = self::$ops[$op];
				if( $newline && $op[1] !== false ) $before .= "\t"; // Handle multi line statements with operator at start of line
				elseif( $op[1] === 0 ) $before = '';
				elseif( $op[1] ) $before = ' ';
				if( $op[2] === 0 ) $after = '';
				elseif( $op[2] && empty( $endline ) ) $after = ' ';
				return $newline . $before . $op[0] . $after . $endline;
			}, $code );
		}

		// Special condition for multiline && and || statements, drop the end bracket and brace to its own line
		$code = preg_replace( '%^(\t*?)\t((&&|\|\|).*?)\s*(\)\s*\{($|[ \t]*//.*$))%m', "$1\t$2\n$1$4", $code );

		// Fix case colons
		$code = preg_replace( '%^(\s*case.+?)\s*:%m', '$1:', $code );

		// Clean up brackets
		$code = preg_replace_callback( '%\([ \t]*(.+?)[ \t]*\)%', function( $m ) {
			return '( ' . preg_replace( '%\s*,\s*%', ', ', $m[1] ) . ' )';
		}, $code );
		$code = preg_replace( '%\([ \t]+\)%', '()', $code );

		// Single space after if, for, while etc
		$code = preg_replace( '%(?<=\W)(for|if|elseif|while|foreach|switch)\s*\(%', '$1 (', $code );

		// Allow only single empty lines
		$code = preg_replace( '%\n\n+%', "\n\n", $code );

		return $code;
	}

	/**
	 * Format the code into a uniform state ready for processing
	 * - this is done to the whole file not just the PHP,
	 * - becuase strings and comments may contain symbols that confuse the process
	 */
	private static function preprocess( &$code ) {

		// Remove trailing whitespace
		$code = preg_replace( '%^(.*?)[ \t]+$%m', '$1', $code );

		// Make all newlines uniform UNIX style
		$code = preg_replace( '%\r\n?%', "\n", $code );

		// Protect all escaped quotes
		$code = preg_replace( "%\\\\'%", 'q1' . self::$uniq, $code );
		$code = preg_replace( '%\\\\"%', 'q2' . self::$uniq, $code );

		// Protect strings
		$code = preg_replace_callback( "%'(.+?)'%", function( $m ) {
			self::$strings1[] = $m[1];
			return "'s1" . ( count( self::$strings1 ) - 1 ) . self::$uniq . "'";
		}, $code );
		$code = preg_replace_callback( '%"(.+?)"%', function( $m ) {
			self::$strings2[] = $m[1];
			return "\"s2" . ( count( self::$strings2 ) - 1 ) . self::$uniq . "\"";
		}, $code );

		// Change old perl-style comments to double-slash
		$code = preg_replace( '%#(#*)%', '//$1', $code );

		// Protect comments
		$code = preg_replace_callback( '%(?<=/\*)(.+?)(?=\*/)%s', function( $m ) {
			self::$comments1[] = $m[1];
			return 'c1' . ( count( self::$comments1 ) - 1 ) . self::$uniq;
		}, $code );
		$code = preg_replace_callback( '%(?<=//)(.+?)$%m', function( $m ) {
			self::$comments2[] = $m[1];
			return 'c2' . ( count( self::$comments2 ) - 1 ) . self::$uniq;
		}, $code );
	}

	/**
	 * Put all the preserved content back in place
	 */
	private static function postprocess( &$code ) {

		// Put comments back
		$code = preg_replace_callback( '%c1([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$comments1[$m[1]];
		}, $code );
		$code = preg_replace_callback( '%c2([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$comments2[$m[1]];
		}, $code );

		// Put strings back
		$code = preg_replace_callback( '%s1([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$strings1[$m[1]];
		}, $code );
		$code = preg_replace_callback( '%s2([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$strings2[$m[1]];
		}, $code );

		// Put escaped quotes back
		$code = preg_replace( '%q1' . self::$uniq . '%', "\\'", $code );
		$code = preg_replace( '%q2' . self::$uniq . '%', '\\"', $code );
	}

}

if( isset( $argv[1] ) ) {
	echo CodeTidy::tidy( file_get_contents( $argv[1] ) );
}
