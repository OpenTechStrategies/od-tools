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
 * Version 0.5 beta
 */

class CodeTidy {

	public static $debug = false;

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
		array( ',', false, 1 ),
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

		// Where are the PHP delimeters?
		preg_match_all( "%<\?%", $code, $m, PREG_OFFSET_CAPTURE );

		// If there are none, treat it all as PHP and add one at the start
		if( count( $m[0] ) < 1 ) {
			self::tidySection( $code );
			$code = "<?php\n" . $code;
		}

		// If there is one at the start remove it, process the whole script and re-add it
		// (saves doing preg_replace_callback on potentially very large files)
		elseif( count( $m[0] ) == 1 && $m[0][0][1] == 0 ) {
			$code = preg_replace( '%^<\?(php)?\s*%', '', $code );
			self::tidySection( $code );
			$code = "<?php\n" . $code;
		}

		// If there are various, loop through all PHP sections in the content and tidy each
		// (but not ones that are a single line since it may mess up HTML formatting)
		else {
			$code = preg_replace_callback( "%<\?(php)?(.+?)(\?>|$)%s", function( $m ) {
				$singleLine = preg_match( "%\n%", $m[2] );
				self::tidySection( $m[2] );
				return $singleLine ? "<?php\n$m[2]\n?>" : '<?php ' . trim( $m[2] ) . " $m[3]";
			}, $code );
		}

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
	private static function tidySection( &$code ) {
		self::statements( $code );
		self::indent( $code );
		self::operators( $code );
	}

	/**
	 * Tidy statements
	 */
	private static function statements( &$code ) {
		if( self::$debug ) print "Tidying statements\n";

		// Change all "else if" to "elseif"
		$code = preg_replace( '%else\s*if%', 'elseif', $code );

		// Don't allow naked statements in for, if and else etc
		// - We fix them from last to first occurrence so inner-most are always processed first avoiding recursion
		// - else and elseif are not passed here as they start from an if
		if( preg_match_all( "%(^|;|\))\s*(for(each)?|if|switch)%m", $code, $m, PREG_OFFSET_CAPTURE ) ) {
			for( $i = count( $m[2] ) - 1; $i >= 0; $i-- ) {
				self::fixNakedStatements( $m[2][$i][1], $code );
			}
		}

		// Put all statements on their own line
		//$code = preg_replace( '%;(?!\n)%', ";\n", $code );
	}

	/**
	 * Put braces around naked statements in for/if/else etc
	 * - the location of the statement to process is passed
	 * - this also preserves the content of the C-style for loop brackets so they don't get included in one-statement-per-line process
	 * - Parse state:
	 *   0) keyword prior to brackets
	 *   0.5) whitespace after keyword
	 *   1) bracketed part (can be none e.g. else)
	 *   2) naked statement part after brackets (moves straight to 3 if brace)
	 *   3) brace structure statement after brackets
	 *   4) statement part finished (end or start a new else/elseif chain statement)
	 */
	private static function fixNakedStatements( $loc, &$code ) {
		$state = 0;
		$level = 0;
		$i = $loc;
		$brackets = '';
		$statement = '';
		$naked = '';
		$done = false;
		while( !$done && $i < strlen( $code ) ) {
			$chr = $code[$i++];

			// Check if this is the space after the keyword
			if( preg_match( '%\s%', $chr ) && $state == 0 ) $state = 0.5;

			// Check if this statement has no bracket section, e.g. else
			if( !preg_match( '%(\s|\()%', $chr ) && $state == 0.5 ) $state = 2;

			if( $state == 1 ) $brackets .= $chr;
			elseif( $state == 2 ) $naked .= $chr;
			else $statement .= $chr;

			// Opening bracket found, either starting or within the bracket structure after keyword
			if( $chr == '(' && $state < 2 ) {
				$statement = preg_replace( '%\($%', ' (', $statement ); // Single space after keyword before bracket
				$state = 1;
				$level++;
			}

			// Final closing bracket in the bracket structure after keyword found
			elseif( $chr == ')' && $state < 2 && --$level == 0 ) {
				$statement .= $brackets;
				$brackets = '';
				$state = 2;
			}

			// Semicolon
			elseif( $chr == ';' ) {

				// This is a C-style for loop, mark the bracket structure for preservation
				if( $state == 1 ) $cfor = true;

				// This is the end of a naked statement, add braces
				elseif( $state == 2 ) {
					$statement .= preg_replace( '%^\s*(.+?);$%', '{$1;}', $naked );
					$state = 4;
				}
			}

			// Opening brace found either starting, or within the brace structure
			elseif( $chr == '{' ) {
				$level++;
				if( $state != 3 ) {
					$statement .= $naked;
					$state = 3;
				}
			}

			// Final closing bracket in brace structure found
			elseif( $chr == '}' && --$level == 0 ) $state = 4;

			// Statement has ended, if there's a following else or elseif, carry on building the statement, otherwise finished
			if( $state == 4 ) {
				if( preg_match( '%^(\s*)else%', substr( $code, $i ), $m ) ) {
					$i += strlen( $m[1] ); // Skip whitespace if any
					$naked = '';
					$state = 0;
				} else $done = true;
			}
		}

		// If this whole statement is naked within another statement (prior non-whitespace is a closing bracket) wrap in braces
		if( preg_match( '%\)\s*$%s', substr( $code, 0, $loc ) ) ) {
			$statement = '{' . $statement . '}';
		}

		// Update the code
		$code = substr_replace( $code, $statement, $loc, $i - $loc );
	}

	/**
	 * Spacing around operators
	 */
	private static function operators( &$code ) {
		if( self::$debug ) print "Fixing operators\n";
		self::$i = 0;
		self::$opData = array();

		// First preserve them all storing data about their before and after spacing
		// - done because e.g. == will match inside an ===
		if( self::$debug ) print "\tPreserving\n";
		foreach( self::$ops as self::$j => $op ) {
			$before = $op[1];
			$after = $op[2];
			$op = preg_quote( $op[0] );
			$code = preg_replace_callback( "#(\n?)([ \t]*)$op([ \t]*)(\n?)#", function( $m ) {
				//if( self::$ops[self::$j][0] == ')' ) print_r($m);
				self::$i++;
				self::$opData[self::$i] = array( self::$j, $m[1], $m[2], $m[3], $m[4] );
				return 'o' . self::$i . self::$uniq;
			}, $code );
		}

		// Restore them applying the correct spacing
		if( self::$debug ) print "\tRestoring\n";
		foreach( self::$opData as $i => $data ) {
			$code = preg_replace_callback( "%o($i)" . self::$uniq . '%', function( $m ) {
				list( $op, $newline, $before, $after, $endline ) = self::$opData[$m[1]];
				$op = self::$ops[$op];
				if( $newline && $op[1] !== false ) {
					// Do nothing if multiline expression with operator at start
				}
				elseif( $op[1] === 0 ) $before = '';
				elseif( $op[1] ) {
					if( !$op[0] == ')' && !preg_match( '%\t%', $before ) ) $before = ' '; // Leave closing brackets alone if they have indenting
				}
				if( $op[2] === 0 ) $after = '';
				elseif( $op[2] && empty( $endline ) ) $after = ' ';
				return $newline . $before . $op[0] . $after . $endline;
			}, $code );
		}

		// Special condition for multiline && and || statements, drop the end bracket and brace to its own line
		if( self::$debug ) print "\tMultiline && and ||\n";
		$code = preg_replace( '%^(\t*?)\t((&&|\|\|).*?)\s*(\)\s*\{($|[ \t]*//.*$))%m', "$1\t$2\n$1$4", $code );

		// Hack: Fix double spaces
		$code = preg_replace( '% +%', ' ', $code );

		// Fix case/default colons
		$code = preg_replace( '%^(\s*)(case.+?|default)\s*:%m', '$1$2:', $code );

		// Special case for empty brackets
		$code = preg_replace( '%\(\s+\)%', '()', $code );
	}

	/**
	 * Handle braces and indenting for passed section
	 * - the indent level (self::$indent) is reset at the start of the whole script not the section
	 */
	private static function indent( &$code ) {
		if( self::$debug ) print "Indenting\n";

		// Put a newline after braces that have things after them
		$code = preg_replace( '%(\{|\})(?!\n)%m', "$1\n", $code );

		// Move orphan opening braces to previous line
		$code = preg_replace( '%(?<=\S)\s*\{[ \t]*$%m', ' {', $code );
		$code = preg_replace( '%(?<=\S)\s*\{([ \t]*//)%m', ' {$1', $code );

		// Format else statements
		$code = preg_replace( '%\}\s*else\s*\{%', '} else {', $code );

		// Do a character parse loop that maintains the level of braces and brackets
		$state = 0;               // Only two states, 0 = Not in a bracket structure, 1 = in a bracket structure
		$line = '';               // The current line
		$keyword = '';            // Last keyword
		$ktmp = '';
		$bracketLevel = 0;
		$lastBracketLevel = 0;
		$braceKeyword = array();  // Stack of keywords that the braces apply to
		$lastIndent = self::$indent;
		$newcode = '';
		for( $i = 0; $i < strlen( $code ); $i++ ) {
			$chr = $code[$i];
			$line .= $chr;

			// In a bracket structure
			if( $state == 1 ) {
				if( $chr == '(' ) {
					$bracketLevel++;
					self::$indent++;
				}
				elseif( $chr == ')' ) {
					if( --$bracketLevel == 0 ) $state = 0;
					self::$indent--;
				}
			}

			// Not in a bracket structure
			else {

				// If the current character is alpha or underscore then append it to current keyword, else clear keyword ready for next one to start
				if( preg_match('%[a-z_]%', $chr ) ) $ktmp .= $chr;
				else {
					$keyword = $ktmp;
					$ktmp = '';
				}

				// Start a bracket structure
				if( $chr == '(' ) {
					self::$indent++;
					$bracketLevel = 1;
					$state = 1;
				}

				elseif( $chr == '{' ) {
					self::$indent++;
					$braceKeyword[] = $keyword;
				}

				elseif( $chr == '}' ) {
					if( --self::$indent == 0 ) array_pop( $braceKeyword );
				}

				// Semicolon, if no newline after it, break the line now
				elseif( $chr == ';' && !preg_match( '%^[ \t]*(\n|//)%', substr( $code, $i + 1 ) ) ) {
					$chr = "\n";
					$line .= $chr;
				}
			}

			// Newline, add the line to the new version of the code with indenting
			if( $chr == "\n" ) {
				$n = ( self::$indent - $lastIndent > 0 ) ? $lastIndent : self::$indent; // K&R: If this line indented, wait until next line else change now
				if( preg_match( '%^\s*(case |default[ :]|\}.+?\{)%', $line ) ) $n--;    // if case/default or }...{ subtract 1 from the intented amount
				if( $bracketLevel < $lastBracketLevel && preg_match( '%[^\s\(\);]+%', $line ) ) $n++; // Special case for content with a closing bracket
				$line = preg_replace( '%^\t*%', '', $line );
				if( trim( $line ) ) $newcode .= $n > 0 ? str_repeat( "\t", $n ) : '';   // Only indent if the line is not empty
				$newcode .= $line;
				$line = '';
				$lastIndent = self::$indent;
				$lastBracketLevel = $bracketLevel;
			}

		}
		$code = $newcode;
	}

	/**
	 * Format the code into a uniform state ready for processing
	 * - this is done to the whole file not just the PHP sections,
	 * - becuase strings and comments may contain symbols that confuse the process
	 */
	private static function preprocess( &$code ) {
		if( self::$debug ) print "Preprocessing\n";

		// Make all newlines uniform UNIX style
		$code = preg_replace( '%\r\n?%', "\n", $code );

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

				// We're within a single-quote string
				case "'":
					if( substr( $content, -1 ) == "'" ) {
						$newcode .= self::preserve( 's1', $content ) . $chr;
						$state = $content = '';
					} else {
						$content .= $chr;
					}
				break;

				// We're within a double-quote string
				case '"':
					if( substr( $content, -1 ) == '"' ) {
						$newcode .= self::preserve( 's2', $content ) . $chr;
						$state = $content = '';
					} else {
						$content .= $chr;
					}
				break;

				// We're within a backtick string
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
						$newcode .= self::preserve( 'c2', $content, 0 ) . $chr;
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
		if( self::$debug ) print "Postprocessing\n";

		// Put all the preserved code back in opposite order it was preserved
		foreach( array( 'c1', 'c2', 's4', 's3', 's2', 's1' ) as $k ) {
			self::restore( $k, $code );
		}

		// Modify multiline comment content to match indent
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
	 * - $end is set because content includes closing delimeter which is usually a single character
	 */
	private static function preserve( $type, $s, $end = 1 ) {
		if( !array_key_exists( $type, self::$p ) ) self::$p[$type] = array();
		self::$p[$type][] = $end ? substr( $s, 0, strlen( $s ) - $end ) : $s;
		return $type . ( count( self::$p[$type] ) - 1 ) . self::$uniq . ( $end ? substr( $s, -$end ) : '' );
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
