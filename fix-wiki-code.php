<?php
/**
 * Change the {{code|<LANG> syntax to <source lang="LANG" syntax
 */
$path = $_SERVER['argv'][0];
if( $path[0] != '/' ) die( "Please use absolute path to execute the script so I can assess where the code-base resides.\n" );
$IP = preg_replace( '|(^.+)/extensions/.+$|', '$1', $path );
putenv( "MW_INSTALL_PATH=$IP" );
require_once( "$IP/maintenance/Maintenance.php" );

class FixCode extends Maintenance {

	public function __construct() {
		parent::__construct();
		$this->mDescription = 'Change the {{code|<LANG> syntax to <source lang="LANG" syntax';
	}

	public function execute() {
		$dbr = wfGetDB( DB_MASTER );
		$res  = $dbr->select( 'templatelinks', 'tl_from', array( 'tl_namespace' => NS_TEMPLATE, 'tl_title' => 'Code' ) );
		foreach( $res as $row ) {
			$title = Title::newFromId( $row->tl_from );
			$article = new Article ( $title );
			$text = $article->getContent();
			$count = 0;
			$text = preg_replace_callback( '%\{\{code\|\s*<(.+?)>\s*(.+?)\s*</\\1>\s*\}\}%s', function( $m ) {
				if( $m[1] === 'math' ) return $m[0];
				$lang = $m[1] === 'pre' ? '' : " lang=\"$m[1]\"";
				return "<source$lang>\n$m[2]\n</source>";
			}, $text, -1, $count );
			if( $count > 0 ) $article->doEdit( $text, 'Change source-code blocks to standard format', EDIT_UPDATE );
			$this->output( 'Fixed "' . $title->getPrefixedText() . "\"\n" );
			sleep(5);
		}
	}
}

$maintClass = "FixCode";
require_once RUN_MAINTENANCE_IF_MAIN;
