#!/usr/bin/perl
#{{perl}}{{Category:OD2}}{{#security:*|sysop}}
# External script for handling our rewrite rules for friendly-url's, request logging/filtering
# Apache is configured to send all requests URL's through STDIN to this script along with the main environment variables,
# This script then analyses the request and then rewrites the url and sends it down STDOUT
#
# - Licenced under LGPL (http://www.gnu.org/copyleft/lesser.html)
# - Author:  http://www.organicdesign.co.nz/nad
# - Started: 2007-09-04
# - Version: 0.0.3 (2007-09-18)

$|       = 1;
$domains = '/var/www/domains';
$filter  = '/var/www/filter-rules';
$log     = '/var/www/rewrite.log';
@types   = ('ip','ua','user','session'); # Types are fields containing patterns
$head    = "{"."{#security:*|admin}"."}{"."{#filesync:$filter}"."}\n{"."{#tree:\n";
$tail    = "}"."}\n[[Category:OD2]]";

open LOG, '>', $log;
select((select(LOG), $|=1)[0]);

# Wait for input from Apache
while (<>) {

	# Split the input into requested URL and Apache environment vars
	# s/[\x00-\x1f]+//g;
	@args = split /--/, $_;
	($url,$host,$ip,$ua,$cookie,$qs) = @args;
	$_ = $url;

	# Process the request information
	$info    = '';
	$host    =~ s/^www.//;
	$user    = $cookie =~ /UserName=(.+?);/      ? $1 : '';
	$session = $cookie =~ /_session=([0-9a-z]+)/ ? $1 : '';

	# Read in LocalSettings.php and filter-rules files
	$ls = readFile("$domains/$host/LocalSettings.php");

	# Apply the rewrite rule if $wgRewriteRule is set in LocalSettings.php
#	if ($ls =~ /^\s*\$wgRewriteRule\s*=\s*['"](\w*)["'];/m) {
#		$rw ="rewrite$1";
#		&$rw if $rw;
#		}
#	else { &rewriteFriendly }
&rewriteFriendly;

	# Filter the final request
	#&filter;

	print "$host/$_\n";

	# Output the log entry
	$qs = "?$qs" if $qs;
	print LOG localtime().": ($ip:$user:$session) $host/$url$qs(->$_)\n$info";
	}

# Read file and cache locally
sub readFile {
	$file = shift;
	$ts = '';
	$curts = (stat $file)[9];
	if (exists($cache{$file})) { ($content,$ts) = @{$cache{$file}} }
	if ($ts ne $curts) {
		if (open FH,'<',$file) {
			sysread FH, $content, -s $file;
			close FH;
			$cache{$file} = [$content,$curts];
			$changed = 1;
			$info .= "   Cache entry for '$file' ".($ts ? 'updated' : 'created')."\n";
			}
		}
	return $content;
	}

# Maintain a tree of identified requesters and apply rules
sub filter {

	# Read rules file into a hash of rules[ID][TYPE][PATTERN => COMMENT]
	$changed = 0;
	$fr = readFile($filter);
	if ($changed) {
		%rules = ();
		$id    = '';
		$type  = '';
		for (split /^/, $fr) {
			$id   = $1 if /^\*\s*(\w+)/;
			$type = lc $1 if /^\*{2}\s*(action|ip|ua|user|session)/i;
			$rules{$id}{$type}{$1} = $2 if /^\*{3}\s*(.+?)(#.+)?$/;
			}
		}

	# Check if the request matches any rules and update rules with any new inferences
	# eg. if the request's session matches one of the ID's session-patterns,
	#     then we can add the request's IP and user to that ID if not already present
	$match  = '';
	$update = 0;
	for $id (keys %rules) {  # Check rules for each ID
		for $type (@types) { # Check each matchable type in this ID's rules
			for $pattern (keys %{$rules{$id}{$type}}) { # Loop through all patterns listed in this type
				if ($$type =~ /$pattern/) {   # Check if the pattern matches the current request's value of this type
					$match = $id;
					for $other (@types) {      # If so, loop through all other types that have values in the current request
						if ($other ne $type and $$other ne '') {
							$add = "^$$other\$";
							if (!exists($rules{$id}{$type}{$add})) { # and update the tree with an inferred value
								$update  = 1;
								$comment = "inferred by $type match ($$type)";
								$rules{$id}{$type}{$add} = " # $ts: $comment";
								$entry  .= "   $other $comment\n";
								}
							}
						}
					}
				}
			}
		}
	$info .= "    MATCH: $id\n";

	# If the tree has changed (either from file update, or new inferences) rebuild as text & update local cache
	if ($changed or $update) {	
		$tree = $head;
		for $id (keys %rules) {
			$tree .= "*$id\n";
			for $type (keys %{$rules{$id}}) {
				$tree .= "**$type\n";
				for (keys %{$rules{$id}{$type}}) {
					$comment = $rules{$id}{$type}{$_};
					$tree .= "***$_$comment\n" 
					}
				}
			}
		$tree .= $tail;
		$cache{$filter}[0] = $tree; # Update cache content
		}

	# Write back to file if tree changed from new inferences
	if (0 && $update) {
		open FH,'>',$filter;
		print FH $tree;
		close FH;
		$cache{$filter}[1] = (stat $filter)[9]; # update cache lastmod time
		}

	$info .= $tree;

	}

# URL-rewrite rules for MediaWiki Friendly URL's
# - the first rule allows naked URL to map to main page
# - the second rule allows dynamic thumbnail generation via URL
# - the third allows friendly URL's for all requests outside /wiki/ or /files/
sub rewriteFriendly {
	if ($_ eq '') { $_ = 'wiki/index.php?title=Main_Page' }
	elsif (/^files\/thumb\/.\/..\/(.+?)\/([0-9]+)px-/ && !/\.svg/) { $_ = "wiki/thumb.php?w=$2&f=$1" }
 	else { s|^(.+)$|wiki/index.php?title=$1| unless /^(wiki\/|files\/|config\/|[rR]obots\.txt|[fF]avicon\.ico)/ }
	}
