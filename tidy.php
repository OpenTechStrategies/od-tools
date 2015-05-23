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

	private static $uniq = "\x07";
	private static $break = array();
	private static $i;
	private static $j;
	private static $opData;
	private static $indent;

	private static $strings1 = array();  // Preserved single-quote strings
	private static $strings2 = array();  // Preserved double-quote strings
	private static $strings3 = array();  // Preserved backticks
	private static $comments1 = array(); // Preserved multi-line comments
	private static $comments2 = array(); // Preserved single-line comments
	private static $for = array();       // Preserved semicolon syntax in C-style for loops

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

		// Handle braces and indenting 
		self::indent( $code );

		// Do operator spacing
		self::operators( $code );

		// Single space after if, for, while etc
		$code = preg_replace( '%(?<=\W)(for|if|elseif|while|foreach|switch)\s*\(%', '$1 (', $code );

		// Allow only single empty lines
		$code = preg_replace( '%\n\n+%', "\n\n", $code );

		return $code;
	}

	/**
	 * Handle braces and indenting for passed section
	 * - the indent level (self::$indent) is reset at the start of the whole script not the section
	 */
	private static function indent( &$code ) {

		// Put a newline after braces
		$code = preg_replace( '%\{(?!\n)%m', "{\n", $code );

		// Move orphan opening braces to previous line
		$code = preg_replace( '%(?<=\S)\s*\{[ \t]*$%m', ' {', $code );
		$code = preg_replace( '%(?<=\S)\s*\{([ \t]*//)%m', ' {$1', $code );

		self::$break = array();
		$code = preg_replace( '%\}\s*else\s*\{%', '} else {', $code );
		$code = preg_replace( '%^(\s*\S+\S*\{)\s*(?!=\/)(\S+.+?$)%', "$1\n$2", $code );
		$code = preg_replace_callback( "%^(.+?)$%m", function( $m ) {
			$i = preg_match( '%(\{|\()($|[ \t]*//)%', $m[1] );
			if( preg_match( '%^\s*case.+?:($|[ \t]*//)%', $m[1] ) ) {
				self::$break[] = true;
				$i = true;
			}
			if( preg_match( '%^\s*(for|while) %', $m[1] ) ) {
				self::$break[] = false;
			}
			$o = preg_match( '%^\s*(\}|\))%', $m[1] );
			if( preg_match( '%^\s*break;%', $m[1] ) ) {
				if( array_pop( self::$break ) ) $o = true;
			}
			if( $i && $o ) self::$indent--;
			if( $o && !$i ) self::$indent--;
			$line = preg_replace( "%^\s*%", self::$indent > 0 ? str_repeat( "\t", self::$indent ) : '', $m[1] );
			if( $i ) self::$indent++;
			return $line;
		}, $code );
	}

	/**
	 * Spacing around operators
	 */
	private static function operators( &$code ) {
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
				if( $newline && $op[1] !== false ) { // Handle multi line statements with operator at start of line
					if( $op[0] != ')' ) $before .= "\t";
				}
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
	}

	/**
	 * Format the code into a uniform state ready for processing
	 * - this is done to the whole file not just the PHP sections,
	 * - becuase strings and comments may contain symbols that confuse the process
	 */
	private static function preprocess( &$code ) {

		// Remove all indenting and trailing whitespace
		$code = preg_replace( '%^[ \t]*(.*?)[ \t]*$%m', '$1', $code );

		// Make all newlines uniform UNIX style
		$code = preg_replace( '%\r\n?%', "\n", $code );

		// Protect all escaped quotes
		$code = preg_replace( "%\\\\'%", 'q1' . self::$uniq, $code );
		$code = preg_replace( '%\\\\"%', 'q2' . self::$uniq, $code );

		// Preserve single-quote strings
		$code = preg_replace_callback( "%'(.+?)'%", function( $m ) {
			self::$strings1[] = $m[1];
			return "'s1" . ( count( self::$strings1 ) - 1 ) . self::$uniq . "'";
		}, $code );

		// Preserve double-quote strings
		$code = preg_replace_callback( '%"(.+?)"%', function( $m ) {
			self::$strings2[] = $m[1];
			return "\"s2" . ( count( self::$strings2 ) - 1 ) . self::$uniq . "\"";
		}, $code );

		// Preserve backticks
		$code = preg_replace_callback( '%`(.+?)`%', function( $m ) {
			self::$stringss[] = $m[1];
			return "`ss" . ( count( self::$strings3 ) - 1 ) . self::$uniq . "`";
		}, $code );

		// Change old perl-style comments to double-slash
		$code = preg_replace( '%#(#*)%', '//$1', $code );

		// Preserve multiline comments
		$code = preg_replace_callback( '%(?<=/\*)(.+?)(?=\*/)%s', function( $m ) {
			self::$comments1[] = $m[1];
			return 'c1' . ( count( self::$comments1 ) - 1 ) . self::$uniq;
		}, $code );

		// Preserve single-line comments
		$code = preg_replace_callback( '%(?<=//)(.+?)$%m', function( $m ) {
			self::$comments2[] = $m[1];
			return 'c2' . ( count( self::$comments2 ) - 1 ) . self::$uniq;
		}, $code );

		// Change all remaining whitespace to single spaces
		$code = preg_replace( '%[ \t]+%', ' ', $code );

		// Put all statements on their own line (need to preserve C-style for loops first)
		$code = preg_replace_callback( '%(\Wfor\s*)\(([^\)]*;[^\)]*)\)%m', function( $m ) {
			self::$for[] = $m[1];
			return 'f' . ( count( self::$for ) - 1 ) . self::$uniq;
		}, $code );
		$code = preg_replace( '%;(?!\n)%', ";\n", $code );
		$code = preg_replace_callback( '%f([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$for[$m[1]];
		}, $code );
	}

	/**
	 * Put all the preserved content back in place
	 */
	private static function postprocess( &$code ) {

		// Put multiline comments back
		$code = preg_replace_callback( '%c1([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$comments1[$m[1]];
		}, $code );
		// TODO, indent comments correctly

		// Put single-line comments back
		$code = preg_replace_callback( '%c2([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$comments2[$m[1]];
		}, $code );

		// Put single-strings back
		$code = preg_replace_callback( '%s1([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$strings1[$m[1]];
		}, $code );

		// Put double-strings back
		$code = preg_replace_callback( '%s2([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$strings2[$m[1]];
		}, $code );

		// Put backticks back
		$code = preg_replace_callback( '%s3([0-9]+)' . self::$uniq . '%', function( $m ) {
			return self::$strings3[$m[1]];
		}, $code );

		// Put escaped quotes back
		$code = preg_replace( '%q1' . self::$uniq . '%', "\\'", $code );
		$code = preg_replace( '%q2' . self::$uniq . '%', '\\"', $code );
	}

}

if( isset( $argv[1] ) ) {
	echo CodeTidy::tidy( file_get_contents( $argv[1] ) );
}
