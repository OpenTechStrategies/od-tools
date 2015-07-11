<?php
/**
 * WikiSpeedTest - reads file contents and makes articles from them
 *
 * Use wget and date to record execution time, e.g.
 * date +%s.%N && wget -qO /dev/null "http://localhost/Main_Page?speedtest=1"  && date +%s.%N
 *
 * @package MediaWiki
 * @subpackage Extensions
 * @author Aran Dunkley (http://www.organicdesign.co.nz/aran)
 * @licence GNU General Public Licence 2.0 or later
 */

$wgTestGlob = $IP . '/includes/*.php';
$wgTestNum = 5;

if( array_key_exists( 'speedtest', $_GET ) ) $wgExtensionFunctions[] = 'wfSpeedTest';

function wfSpeedTest() {
	global $wgTestGlob, $wgTestNum;

	$n = 0;
	foreach( glob( $wgTestGlob ) as $file ) {
		if( $n++ < $wgTestNum ) {
			$content = file_get_contents( $file );
			$summary = 'Article created from ' . basename( $file ) . ' for WikiSPeedTest';
			$title = Title::newFromText( md5( microtime() . ':' . $file . ':' . $content ) );
			$article = new Article( $title );
			$article->doEdit( "<source lang=\"php\">\n$content\n</source>", $summary, EDIT_NEW|EDIT_FORCE_BOT );
		}
	}
}
