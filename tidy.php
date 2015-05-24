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
 * Version 0.2 beta
 */

class CodeTidy {

	private static $break = array();
	private static $opData;        // Preserved operand data
	private static $indent;
	private static $uniq = "\x07"; // A unique string to use in the replacement for preseving strings and comments
	private static $p = array();   // preserved string and comment data
	private static $i;             // General loops in class so they're available to callbacks
	private static $j;

	// Note, must be ordered from longest to shortest
	// ( operator, spaces before, spaces after ) false means don't touch the space state
	private static $ops = array(
		array( '===', 1, 1 ),
		array( '!==', 1, 1 ),
		array( '<<<', false, false ),
		array( '||', 1, 1 ),
		array( '&&', 1, 1 ),
		array( '++', 0, 1 ),
		array( '--', 0, 1 ),
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

		// Clear indenting state (continues across sections)
		self::$indent = 0;

		// Format the code into a uniform state ready for processing
		self::preprocess( $code );

		// Loop through all PHP sections in the content and tidy each
		// (but not ones that are a single line since it may mess up HTML formatting)
		$code = preg_replace_callback( "%<\?(php)?(.+?)(\?>|$)%s", function( $m ) {
			return preg_match( "%\n%", $m[2] ) ? "<?php\n" . self::tidySection( $m[2] ) . "\n?>" : '<?php ' . trim( $m[2] ) . " $m[3]";
		}, $code );

		// Allow only single empty lines
		$code = preg_replace( '%\n\n+%', "\n\n", $code );

		// Put all the preserved content back in place
		self::postprocess( $code );

		// Remove the final delimiter if any
		$code = preg_replace( '|\s*\?>\s*$|', '', $code );

		return $code;
	}

	/**
	 * Tidy a single PHP section of preprocessed code (without delimeters)
	 */
	private static function tidySection( $code ) {
		self::statements( $code );
		self::keywords( $code );
		self::indent( $code );
		self::operators( $code );
		return $code;
	}

	/**
	 * Tidy statements
	 */
	private static function statements( &$code ) {

		// Don't allow naked statements in for, if and else etc
		// - We fix them from last to first occurrence to handle the possibility of nested naked bracket statements
		if( preg_match_all( "%(^|;|\))\s*(for(each)?|(else\s*)?if|else)%m", $code, $m, PREG_OFFSET_CAPTURE ) ) {
			for( $i = count( $m[2] ) - 1; $i >= 0; $i-- ) {
				self::fixNaked( $m[2][$i][1], $code );
			}
		}

		// Put all statements on their own line
		$code = preg_replace( '%;(?!\n)%', ";\n", $code );

		// Restore the C-style for bracket content that was preserved by the fixNaked function
		self::restore( 'f', $code );
	}

	/**
	 * Put braces around naked statements in for/if/else etc
	 * - the location of the statement to process is passed
	 * - this also preserves the content of the C-style for loop brackets so they don't get included in one-statement-per-line process
	 * - Parse state:
	 *   0) keyword prior to brackets
	 *   0.5) whitespace after keyword
	 *   1) bracketed part
	 *   2) statement part after brackets
	 *   3) brace part after brackets
	 */
	private static function fixNaked( $loc, &$code ) {
		$changed = false;
		$state = 0;
		$level = 0;
		$i = $loc;
		$keyword = '';
		$brackets = '';
		$statement = '';
		$cfor = false;
		$done = false;
		while( !$done && $i < strlen( $code ) ) {
			$chr = $code[$i++];
			if( $state == 0 ) $keyword .= $chr;
			elseif( $state == 1 ) $brackets .= $chr;
			elseif( $state > 1 || $state == 0.5 ) $statement .= $chr;
			if( !preg_match( '%(\s|\()%', $chr ) && $state == 0.5 ) {
				$state = 2; // this statement had no bracket section, e.g. else
			}
			if( preg_match( '%\s%', $chr ) && $state == 0 ) {
				$state = 0.5;
			}
			if( $chr == '(' && $state < 2 ) {
				$state = 1;
				$level++;
			}
			elseif( $chr == ')' && $state < 2 ) {
				$level--;
				if( $level == 0 ) {
					$state = 2;
				}
			}
			elseif( $chr == ';' ) {
				if( $state == 1 ) {
					$cfor = true;
				} elseif( $state != 3 ) {
					$done = true;
				}
			}
			elseif( $chr == '{' ) {
				$state = 3;
				$level++;
			}
			elseif( $chr == '}' ) {
				$level--;
				if( $level == 0 ) {
					$done = true;
				}
			}
		}

		// If it was a C-style for, preserve the bracket contents
		if( $cfor ) {
			$brackets = self::preserve( 'f', $brackets );
			$changed = true;
		}

		// If the statement part is naked, surround in braces
		if( $state < 3 ) {
			$statement = '{' . "\n$statement\n" . '}' . "\n";
			$changed = true;
		}

		// Whole statement
		$whole = $keyword . $brackets . $statement;

		// If this whole statement is naked within another statement (prior non-whitespace is a closing bracket) wrap in braces
		if( preg_match( '%\)\s*$%s', substr( $code, 0, $loc - 1 ) ) ) {
			$whole = '{' . "" . $whole . "" . '}';
			$changed = true;
		}

		// If changed, update the code
		if( $changed ) {
			$code = substr_replace( $code, $whole, $loc, $i - $loc );
		}
	}

	/**
	 * Tidy keywords
	 */
	private static function keywords( &$code ) {

		// Single space after if, for, while etc
		$code = preg_replace( '%(?<=\W)(for|if|elseif|while|foreach|switch)\s*\(%', '$1 (', $code );

	}

	/**
	 * Spacing around operators
	 */
	private static function operators( &$code ) {
		self::$i = 0;
		self::$opData = array();

		// First preserve them all storing data about their before and after spacing
		// - done because e.g. == will match inside an ===
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

		// Unpreserve them applying the correct spacing
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

		// Hack: Fix double spaces
		$code = preg_replace( '% +%', ' ', $code );

		// Fix case colons
		$code = preg_replace( '%^(\s*case.+?)\s*:%m', '$1:', $code );

		// Clean up brackets
		$code = preg_replace_callback( '%\([ \t]*(.+?)[ \t]*\)%', function( $m ) {
			return '( ' . preg_replace( '%\s*,\s*%', ', ', $m[1] ) . ' )';
		}, $code );
		$code = preg_replace( '%\([ \t]+\)%', '()', $code );
	}

	/**
	 * Handle braces and indenting for passed section
	 * - the indent level (self::$indent) is reset at the start of the whole script not the section
	 */
	private static function indent( &$code ) {

		// Put a newline after braces that have things after them
		$code = preg_replace( '%(\{|\})(?!\n)%m', "$1\n", $code );

		// Move orphan opening braces to previous line
		$code = preg_replace( '%(?<=\S)\s*\{[ \t]*$%m', ' {', $code );
		$code = preg_replace( '%(?<=\S)\s*\{([ \t]*//)%m', ' {$1', $code );

		self::$break = array();

		// Format else statements
		$code = preg_replace( '%\}\s*else\s*\{%', '} else {', $code );

		// Loop through all lines to do main indent work
		$code = preg_replace_callback( "%^(.+?)$%m", function( $m ) {

			// Set indent state to true if line ends in open brace or bracket
			$i = preg_match( '%(\{|\()($|[ \t]*//)%', $m[1] );

			// Set indent state to true if line ends in case:
			if( preg_match( '%^\s*case.+?:($|[ \t]*//)%', $m[1] ) ) {
				self::$break[] = true;
				$i = true;
			}

			// Account for breaks not being associated with last case (needs fixing)
			if( preg_match( '%^\s*(for|while) %', $m[1] ) ) {
				self::$break[] = false;
			}

			// Set outdent state to true if line starts with close brace or bracket
			$o = preg_match( '%^\s*(\}|\))%', $m[1] );

			// Or a break
			if( preg_match( '%^\s*break;%', $m[1] ) ) {
				if( array_pop( self::$break ) ) $o = true;
			}

			// Outdent depth if outdent state set
			if( $o ) self::$indent--;

			// Set the indenting of the line to the current depth
			$line = preg_replace( "%^\s*%", self::$indent > 0 ? str_repeat( "\t", self::$indent ) : '', $m[1] );

			// Indent depth if indent state set
			if( $i ) self::$indent++;

			return $line;
		}, $code );
	}

	/**
	 * Format the code into a uniform state ready for processing
	 * - this is done to the whole file not just the PHP sections,
	 * - becuase strings and comments may contain symbols that confuse the process
	 */
	private static function preprocess( &$code ) {

		// Make all newlines uniform UNIX style
		$code = preg_replace( '%\r\n?%', "\n", $code );

		// Remove all indenting and trailing whitespace
		$code = preg_replace( '%^[ \t]*(.*?)[ \t]*$%m', '$1', $code );

		// Preserve escaped quotes and backslashes
		$code = preg_replace( "%\\\\\\\\%", 'q1' . self::$uniq, $code );
		$code = preg_replace( "%\\\\'%", 'q2' . self::$uniq, $code );
		$code = preg_replace( '%\\\\"%', 'q3' . self::$uniq, $code );

		// Scan the code chr-by-chr to preserve strings and comments since they can contain one-another's syntaxes
		$state = '';
		$content = '';
		$newcode = '';
		for( $i = 0; $i < strlen( $code ); $i++ ) {
			$chr = $code[$i];
			switch( $state ) {

				// We're not in any area that needs preserving
				case '':
					if( $chr == '#' ) {
						$newcode .= '//'; // Change old Perl style comments to forward slashes
					} else {
						$newcode .= $chr;
					}
					if( substr( $newcode, -1 ) == "'" ) $state = "'";
					if( substr( $newcode, -1 ) == "`" ) $state = "`";
					if( substr( $newcode, -1 ) == '"' ) $state = '"';
					if( substr( $newcode, -2 ) == '//' ) $state = '//';
					if( substr( $newcode, -2 ) == '/*' ) $state = '/*';
					if( substr( $newcode, -3 ) == '<<<' ) {
						$state = '<<<';
						$id = '';
					}
				break;

				// We're withint a single-quote string
				case "'":
					if( substr( $content, -1 ) == "'" ) {
						$newcode .= self::preserve( 's1', $content ) . $chr;
						$state = $content = '';
					} else {
						$content .= $chr;
					}
				break;

				// We're withint a double-quote string
				case '"':
					if( substr( $content, -1 ) == '"' ) {
						$newcode .= self::preserve( 's2', $content ) . $chr;
						$state = $content = '';
					} else {
						$content .= $chr;
					}
				break;

				// We're withint a backtick string
				case '`':
					if( substr( $content, -1 ) == '`' ) {
						$newcode .= self::preserve( 's3', $content ) . $chr;
						$state = $content = '';
					} else {
						$content .= $chr;
					}
				break;

				// We're within a multiline comment
				case "/*":
					if( substr( $content, -2 ) == '*/' ) {
						$newcode .= self::preserve( 'c1', $content, 2 ) . "\n";
						$state = $content = '';
					} else {
						$content .= $chr;
					}
				break;

				// We're within a single line comment
				case "//":
					if( $chr == "\n" ) {
						$newcode .= self::preserve( 'c2', $content ) . $chr;
						$state = $content = '';
					} else {
						$content .= $chr;
					}
				break;

				// We're within a Heredoc string
				case "<<<":
					if( $id ) {
						if( $chr == ';' && substr( $content, -strlen( $id ) ) == $id ) {
							$newcode .= self::preserve( 's4',"$id\n$content" ) . $chr;
							$state = $content = '';
						} else {
							$content .= $chr;
						}
					} else {
						if( $chr == "\n" ) {
							$id = $content;
							$content = '';
						} else {
							$content .= $chr;
						}
					}
				break;
			}
		}
		$code = $newcode;

		// Remove all indenting and trailing whitespace
		$code = preg_replace( '%^[ \t]*(.*?)[ \t]*$%m', '$1', $code );

		// Change all remaining whitespace to single spaces
		$code = preg_replace( '%[ \t]+%', ' ', $code );
	}

	/**
	 * Put all the preserved content back in place
	 */
	private static function postprocess( &$code ) {

		// Put all the preserved code back in opposite order it was preserved
		foreach( array( 'c1', 'c2', 's4', 's3', 's2', 's1' ) as $k ) {
			self::restore( $k, $code );
		}

		// Modify multiline comment content to match indentint
		$code = preg_replace_callback( '%^(\t*)(/\*.+?\*/)%sm', function( $m ) {
			$indent = $m[1];
			$lines = explode( "\n", $m[2] );
			if( count( $lines ) < 2 ) return $m[0];
			$result = $indent . array_shift( $lines );
			foreach( $lines as $line ) {
				$line = trim( $line );
				if( substr( $line, 0, 1 ) == '*' ) {
					$line = ' ' . $line;
				}
				$result .= "\n" . $indent . $line;
			}
			return $result;
		}, $code );

		// Put escaped quotes and backslashes back
		$code = preg_replace( '%q3' . self::$uniq . '%', '\\"', $code );
		$code = preg_replace( '%q2' . self::$uniq . '%', "\\'", $code );
		$code = preg_replace( '%q1' . self::$uniq . '%', '\\\\\\\\', $code );
	}

	/**
	 * Preserve the passed content and return a unique string to replace it with
	 */
	private static function preserve( $type, $s, $end = 1 ) {
		if( !array_key_exists( $type, self::$p ) ) self::$p[$type] = array();
		self::$p[$type][] = substr( $s, 0, strlen( $s ) - $end );
		return $type . ( count( self::$p[$type] ) - 1 ) . self::$uniq . substr( $s, -$end );
	}

	/**
	 * Restore all the preseved items of the passed type
	 */
	private static function restore( $type, &$code ) {
		self::$i = $type;
		$code = preg_replace_callback( "%$type([0-9]+)" . self::$uniq . '%', function( $m ) {
			return self::$p[self::$i][$m[1]];
		}, $code );
	}
}

// If called from command-line, tidy the specified file
// TODO: allow glob
if( isset( $argv[1] ) ) {
	echo CodeTidy::tidy( file_get_contents( $argv[1] ) );
}
