#!/usr/bin/perl
#
# Copyright (C) 2008-2015 Aran Dunkley, Marcus Davy and others.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
# http://www.gnu.org/copyleft/gpl.html
#
# - Source:  http://www.organicdesign.co.nz/wiki.pl
# - Started: 2008-03-16
# - Changes login and edit to API in Nov 2013 which will prevent it from working in older MediaWiki versions
#

$::wikipl_version = '1.17.6'; # 2017-02-23

use HTTP::Request;
use LWP::UserAgent;
use Encode qw( encode );
use XML::Simple;
use POSIX qw( strftime );
use Digest::MD5 qw( md5_hex );
use Data::Dumper;

sub wikiLogin;
sub wikiLogout;
sub wikiEdit;
sub wikiAppend;
sub wikiFirstEdit;
sub wikiLastEdit;
sub wikiRawPage;
sub wikiStructuredPage;
sub wikiGetVersion;
sub wikiGetNamespaces;
sub wikiGetNamespaceAliases;
sub wikiGetList;
sub wikiDelete;
sub wikiRestore;
sub wikiUploadFile;
sub wikiDeleteFile;
sub wikiGetFileUrl;
sub wikiDownloadFile;
sub wikiDownloadFiles;
sub wikiProtect;
sub wikiUpdateTemplate;
sub wikiMove;
sub wikiExamineBraces;
sub wikiGuid;
sub wikiGetConfig;
sub wikiAllPages;
sub wikiUpdateAccount;
sub wikiParse;
sub wikiGetProperties;
sub wikiGetPreferences;
sub wikiPropertyChanges;
sub wikiGetHashPath;
sub wikiGetArticleID;

# Set up a global client for making HTTP requests as a browser
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
$::client = LWP::UserAgent->new(
	cookie_jar => {},
	agent      => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; it; rv:1.8.1.14)',
	from       => 'wiki.pl@organicdesign.co.nz',
	timeout    => 60,
	max_size   => 1000000,
	ssl_opts   => { verify_hostname => 0, SSL_verify_mode => SSL_VERIFY_NONE }
);

# Do a form post that special-character friendly
sub post {
	my $url = shift;
	my $data = shift;
	my @encdata = ();
	while ( my( $k, $v ) = each %{$data} ) { push @encdata, "$k=" . urlencode($v) };
	return $::client->post(
		$url,
		'Content-type' => "application/x-www-form-urlencoded",
		'Content' => join '&', @encdata,
	);
}

# Url-encode a wiki title
sub encodeTitle {
	my $url = shift;
	$url =~ s/ /_/g;
	$url =~ s/([\W])/ "%" . uc( sprintf( "%2.2x", ord( $1 ) ) ) /eg;
	return $url;
}

sub urlencode {
	my $str = shift;
	$str =~ s/([^-_A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	return $str;
}

sub logAdd {
	my $entry = shift;
	$::lastEntry = $entry;
	if( $::log ) {
		open LOGH, '>>', $::log or die "Can't open $::log for writing!";
		binmode LOGH, ':utf-8';
		print LOGH localtime() . " : $entry\n";
		close LOGH;
	} else { print STDERR "$entry\n" }
	return $entry;
}

sub logHash {
	my $href = shift;
	while ( ( $key, $value ) = each %$href ) {
		print STDERR "$key => $value\n";
	}
}

# Login to a MediaWiki
# todo: check if logged in first
sub wikiLogin {
	my( $api, $user, $pass, $domain ) = @_;
	$api =~ s/index/api/;
	%data = (
		action     => 'login',
		format     => 'xml',
		lgname     => $user,
		lgpassword => $pass
	);
	$res = post $api, \%data;
	logAdd Dumper($res) unless $res->content;
	$xml = XMLin( $res->content );
	$data{lgtoken} = $xml->{'login'}->{'token'};
	$res = post $api, \%data;
	$xml = XMLin( $res->content );
	if( $xml->{'login'}->{'result'} eq 'Success' ) {
		$success = 1;
		logAdd "$user successfully logged in to $api.";
	} else {
		$success = 0;
		logAdd "ERROR: couldn't log $user in to $wiki (" . $xml->{'login'}->{'result'} . ")";
	}
	return $success;
}

# Logout of a MediaWiki
sub wikiLogout {
	my $wiki = shift;
	my $success = $::client->get( "$wiki?title=Special:UserLogout&useskin=standard" )->is_success;
	logAdd $success
		? "Successfully logged out of $wiki."
		: "WARNING: couldn't log out of $wiki!";
	return $success;
}

# Edit a MediaWiki page
# todo: don't return success if edited succeeded but made no changes
sub wikiEdit {
	my( $api, $title, $content, $comment, $minor ) = @_;
	$api =~ s/index/api/;

	# Get edit token
	$res = post $api, {
		action => 'tokens',
		format => 'xml',
		type   => 'edit'
	};
	$xml = XMLin( $res->content );
	$token = $xml->{'tokens'}->{'edittoken'};

	# Do the edit
	logAdd "Attempting to edit \"$title\" on $api";
	$res = post $api, {
		action  => 'edit',
		title   => $title,
		token   => $token,
		text    => $content,
		summary => $comment,
		minor   => $minor ? 1 : 0,
		format  => 'xml',
	};
	my $content = $res->content;
	if( $content =~ /^<\?xml.+<\/api>$/ ) {
		$xml = XMLin( $content );
		if( $xml->{'edit'}->{'result'} eq 'Success' ) {
			$success = 1;
			logAdd "\"$title\" updated.";
		} else {
			$success = 0;
			logAdd "ERROR: couldn't edit \"$title\" in on \"$api\"! (" . $xml->{'edit'}->{'result'} . ")";
		}
	} else {
		$success = 0;
		$content =~ s/<[^>]+>//g;
		$content =~ s/^\s*(.+?)\s*$/$1/;
		logAdd "Error: PHP returned \"$content\"";
	}
	return $success;
}

# Append a wiki page
sub wikiAppend {
	my( $wiki, $title, $append, $comment ) = @_;
	my $content = wikiRawPage( $wiki, $title );
	$content = '' if $content eq '(There is currently no text in this page)';
	return wikiEdit( $wiki, $title, $content . $append, $comment );
}

# Return date, user, oldid and comment of last edit of an article
sub wikiLastEdit {
	my( $wiki, $title ) = @_;
	my $response = $::client->request( HTTP::Request->new( GET => "$wiki?title=$title&action=history&limit=1&useskin=standard" ) );
	my $comment = $response->content =~ /<span class=['"]comment['"]>\((.+?)\)/ ? $1 : '';
	return ( $2, $3, $1, $comment ) if $response->content =~ /oldid=(\d+).+?>(\d+:\d+,.+?)<\/a>.+?['"]User:(.+?)['"]/;
}

# Return date, user, oldid and comment of the first edit of an article
sub wikiFirstEdit {
	my( $wiki, $title ) = @_;
	# some query
	my $comment = $response->content =~ /<span class=['"]comment['"]>\((.+?)\)/ ? $1 : '';
	return ( $2, $3, $1, $comment ) if $response->content =~ /oldid=(\d+).+?>(\d+:\d+,.+?)<\/a>.+?['"]User:(.+?)['"]/;
}

# Retrieve the raw content of a page
sub wikiRawPage {
	my( $wiki, $title, $expand, $oldid ) = @_;
	$oldid = $oldid ? "&oldid=$oldid" : "";
	$title = encodeTitle( $title );
	my $response = $::client->get( "$wiki?title=$title&action=raw$oldid" . ( $expand ? '&templates=expand' : '' ) );
	return $response->content if $response->is_success;
}

# Return a hash of sections, each containing text, lists, links and templates
# - if only one parameter supplied, then it's assumed to be the wikitext content to extract structure from
sub wikiStructuredPage {
	my( $wiki, $title ) = @_;
	$page = $title ? wikiRawPage( $wiki, $title, 1 ) : $wiki;
	my %page = ();
	for ( split /^=+\s*/m, $page ) {
		/(.+?)\s*=+\s*(.+?)\s*/s;
		my( $heading, $content ) = ( $1, $2 );

		# todo: extract lists, links, templates from content

		# if heading, add a node and put content, lists, links in it, else put under root
		if( $1 ) {
			print "$1\n----\n";
		}
	}
	return %page;
}

# Returns mediawiki version string
sub wikiGetVersion {
	my $wiki = shift;
	my $response = $::client->get( "$wiki?title=Special:Version&action=render" );
	return $1 if $response->content =~ /MediaWiki.+?: ([0-9.]+[0x20-0x7e]+)/;
}

# Return a hash (number => name) of the wiki's namespaces
sub wikiGetNamespaces {
	my $wiki = shift;
	my $response = $::client->get( "$wiki?title=Special:Allpages&useskin=standard" );
	$response->content =~ /<select id="namespace".+?>\s*(.+?)\s*<\/select>/s;
	return ( $1 =~ /<option.*?value="([0-9]+)".*?>(.+?)<\/option>/gs, 0 => '' );
}

# Return a hash (number => name) of the wiki's namespace aliases
sub wikiGetNamespaceAliases {
	my $wiki = shift;
	my %aliases = ();
	my $response = $::client->get( "$wiki?useskin=standard" );
	if( $response->content =~ /wgNamespaceIds\s*=\s*\{(.+?)\}/s ) {
		my @wgNamespaceIds = $1 =~ /(".+?":\s*[-0-9]+)/g;
		my %tmp = ();
		foreach( @wgNamespaceIds ) {
			/"(.*?)":\s*([-0-9]+)/;
			my $n = $2;
			my $text = ucfirst $1;
			$text =~ s/_/ /g;
			defined $tmp{$n} ? ( $aliases{$n} = $text ) : ( $tmp{$n} = 1 );
		}
	}
	return %aliases;
}

# return a hash (name => number) of all the 
sub wikiGetNamespacesAndAliases {
	my $wiki = shift;
	my %ns = ();
	my $response = $::client->get( "$wiki?useskin=standard" );
	if( $response->content =~ /wgNamespaceIds\s*=\s*\{(.+?)\}/s ) {
		my @wgNamespaceIds = $1 =~ /(".+?":\s*[-0-9]+)/g;
		foreach( @wgNamespaceIds ) {
			/"(.*?)":\s*([-0-9]+)/;
			$n = $2;
			$text = ucfirst $1;
			$text =~ s/_/ /g;
			$ns{$text} = $n;
		}
	}
	return %ns;
}


# Returns hash (anchor => href) list elements in article content
sub wikiGetList {
	my( $wiki, $title ) = @_;
	$title = encodeTitle( $title );
	my $response = $::client->get( "$wiki?title=$title&useskin=standard" );
	$response->content =~ /<!-- start content -->(.+)<!-- end content -->/s;
	my $html = $1;
	my %list = $html =~ /<li>.*?<a.*?href="(.+?)".*?>(.+?)<\/a>\s*<\/li>/gs;
	my %tmp = (); # bugfix: swap keys/vals
	while ( my( $k, $v ) = each %list ) { $tmp{$v} = $k };
	return %tmp;
}

# Todo error checking on the type of failure, e.g. no user rights to delete
# Capture error if article already deleted
sub wikiDelete {
	my( $wiki, $title, $reason ) = @_;
	$title = encodeTitle( $title );
	my $url = "$wiki?title=$title&action=delete";
	$reason = "content was: \'$title\'" unless $reason;
	my $success = 0;
	my $err = 'ERROR';
	my $retries = 1;
	while ( $retries-- ) {
		my $html = '';
		my $response = $::client->get( $url );
		if( $response->is_success && $response->content =~ m/<input name=['"]wpEditToken["'].*? value=['"](.*?)["'].*?<\/form>/s ) {
			$response = post $url, { wpEditToken => $1, wpReason => $reason };
			$html = $response->content;
			$success = $response->is_success && $html =~ /Action complete/;
		}
		if( $success ) {
			logAdd "$user successfully deleted $title.";
			$retries = 0;
		}
		# Parser response to determine if user has sysop privileges
	}
	return $success;
}

# Todo logAdd the revision/all revisions
sub wikiRestore {
	my( $wiki, $title, $reason, $revision ) = @_;
	$title = encodeTitle( $title );
	my $url = "$wiki?title=Special:Undelete";
	$reason = "Restoring: \'$title\'" unless $reason;
	my $success = 0;
	my $err = 'ERROR';
	my $retries = 1;
	while ( $retries-- ) {
		my $html = '';
		my $response = $::client->get( "$url&target=$title" );
		if( $response->is_success && $response->content =~ m/<input name=['"]wpEditToken["'].*? value=['"](.*?)["'].*?<\/form>/s ) {
			my %form = ( wpComment => $reason, target => $title, wpEditToken => $1, restore=>"Restore" );
			my @timestamps = $response->content =~ m/<input .*?['"](ts\d*?)["'].*?/g;

			# Restore specified $revision
			if( $revision ) {
				if( $#timestamps < ( $revision - 1 ) ) {
					$revision = $#timestamps;
					logAdd("Warning: \$revision specifed does not exist");
				}
				$form{$timestamps[$revision - 1]} = 1;
			} else { @form{@timestamps} = (undef) x @timestamps }

			$response = post "$url&action=submit", \%form;
			$html     = $response->content;
			$success  = $response->is_success && $html =~ /has been restored/;
		}
		if( $success ) {
			logAdd "$user successfully restored $title.";
			$retries = 0;
		}
		# Parser response to determine if user has sysop privileges
	}
	return $success;
}

 
# Upload a files into a wiki using its Special:Upload page
# - if dst name is empty, the name of the source file will be used
sub wikiUploadFile {
    my( $wiki, $sourcefile, $destname, $summary ) = @_;
    my $url = "$wiki?title=Special:Upload&useskin=standard";

	# Set dst name from source if empty
	unless ( $destname ) {
		$destname = $1 if $sourcefile =~ m|^.+/(.+?)$|;
	}

	# Populate a basic upload form
	%form = (
		wpDestFile           => $destname,
		wpUploadDescription  => $summary,
		wpUpload             => "Upload file",
		wpDestFileWarningAck => '',
		wpWatchthis          => '0',
	);

	# Check whether the source file is local or an URL
	if( $sourcefile =~ /^(ftp|http)s?(:\/\/.+)$/ ) {
		$sourcefile = $1 . $2;
		$form{wpSourceType} = $::client->get( $url )->content =~ /name=['"]wpSourceType["'].+?value=["']web['"]/i ? 'web' : 'url';
		$form{wpUploadFileURL} = $sourcefile;
	} else {
		$form{wpSourceType} = 'file';
		$form{wpUploadFile} = [$sourcefile => $destname];
	}

	# Post the upload form
	my $response = $::client->post( $url, \%form, Content_Type => 'multipart/form-data' );

	# If the response is another form with a session-key post again
	if( $response->content =~ /name=['"]wpSessionKey["'].+?value=["'](.+?)["']/ ) {
		$form{wpSessionKey}         = $1;
		$form{wpIgnoreWarning}      = 'true';
		$form{wpDestFileWarningAck} = 1,
		$form{wpLicense}            = '';
		$form{wpUpload}             =  "Save file",
		$response = $::client->post( $url, \%form, Content_Type => 'multipart/form-data' );
		logAdd( "Uploaded a new version of $destname" );
	}

	# Or if it's a form with an edit token, post that
	elsif( $response->content =~ /value=["'](.+?)["'][^>]+?name=['"]wpEditToken["'].+?/ ) {
		$form{'wpEditToken'}         = $1;
		$form{'wpIgnoreWarning'}      = 'true';
		$form{'wpDestFileWarningAck'} = 1,
		$form{'wpLicense'}            = '';
		$form{'wpUpload'}             =  "Upload file",
		$response = $::client->post( $url, \%form, Content_Type => 'multipart/form-data' );
		logAdd( "Uploaded a new version of $destname" );
	}
	
	# Assumed file uploaded ok (should check if that's true)
	else { print "$destname\n\n"; logAdd( "Uploaded $destname" ); }

    return 1;
}


# Delete an uploaded file from a wiki
sub wikiDeleteFile {
	my( $wiki, $imagename, $comment ) = @_;
	my $url     = "$wiki?title=Image:$imagename&action=delete";
	my $success = 0;
	my $err     = 'ERROR';
	my $retries = 1;
	while ( $retries-- ) {
		my $response = $::client->get( $url );
			if( $response->is_success &&
				$response->content =~ m/Permission error.+?The action you have requested is limited to users in the group/s ) {
				logAdd( "Error: $user does not have the permissions to delete $imagename" );
				return $success;
			}
			if( $response->is_success &&
				$response->content =~ m/Internal error.+?Could not delete the page or file specified/s ) {
				logAdd( "Error: Could not delete $imagename - already deleted?" );
				return $success;
			}
			if( $response->is_success &&
				$response->content =~ m/Delete $imagename.+?<input.+?name=['"]wpEditToken["'].+?value=['"](.*?)["'].+?Reason for deletion:/is ) {
				logAdd( "Deleted Image:$imagename" );
				$response = post $url, {
					'wpEditToken'          => $1,
					'wpDeleteReasonList'   => "other",
					'wpReason'             => $comment || "",
					'mw-filedelete-submit' => "Delete",
				};

				my $html = $response->content;
				$success = $response->is_success && $html =~ /Action complete/;
			}
	}
	return $success;
}


# Obtain the URL of a file/image in a wiki given the filename
# - don't supply namespace
sub wikiGetFileUrl {
	my( $wiki, $file ) = @_;
	my $desc = $::client->get( "$wiki?title=Image:$file&useskin=standard" )->content;
	return '' unless $desc =~ m|<a href=['"]([^"']+)['"]><img alt=['"]\w+:$file['"]|;
#	<a href="/files/f/fb/Big_daisy.gif"><img alt="File:Big daisy.gif" 
	my $url = $1;
	$url = $1 . $url if $wiki =~ m|^(https?://.+?)/|;
	return $url;
}


# Download an uploaded file by name from a wiki to a local file
# - don't supply namespace on source file article name
# - if no destination filename is specified, the image name is used
sub wikiDownloadFile {
	my( $wiki, $src, $dst ) = @_;
	if( my $url = wikiGetFileURL( $wiki, $src ) ) {
		logAdd( "Downloading \"$src\" from \"$url\"" );
		my $file = $1 if $url =~ m|^.+/(.+?)$|;
		open FH, '>', $file;
		binmode FH;
		print FH $::client->get( $url )->content;
		close FH;
	}
}


# Download all uploaded files from a wiki to a local directory
# - to a maximum of 500 images
sub wikiDownloadFiles {
	my( $wiki, $dir ) = @_;
	$dir = $wiki =~ /(https?:\/\/(.+?))\// ? $2 : 'wiki-downloaded-files';
	my $base  = $1;
	my $list  = $::client->get( "$wiki?title=Special:Imagelist&limit=500&useskin=standard" )->content;
	my @files = $list =~ /href\s*=\s*['"](\/[^"']+?\/.\/..\/[^'"]+?)["']/g;

	mkdir $dir;
	for my $url ( @files ) {
		if( my $file = $url =~ /.+\/(.+?)$/ ? $1 : 0 ) {
			logAdd( "Dwonloading \"$file\"" );
			open FH, '>', "$dir/$file";
			binmode FH;
			print FH $::client->get( $base . $url )->content;
			close FH;
		}
	}
}


# Change protection state of an article
# - relevant from 1.8+. From 1.12+ so may as well use API
# - see http://www.mediawiki.org/wiki/API:Edit_-_Protect
# - we need this working so that we can use a bot to change #security annotations to protection when SS4 ready
sub wikiProtect {
	# Standard way first, use API later with wikiGetVersion check
	 my(
		$wiki,
		$title,
		$comment ,
		$restrictions, # hashref of action=group pairs
		$expiry,       # optional expiry date string
		$cascade,      # optional boolean for cascading restrictions over transcluded articles
	) = @_;
	$title = encodeTitle( $title );

	if( not $restrictions ) { $restrictions = { "edit" => "", "move" => "" } }

	# A list of defaults which could be used in usage logAdd reporting
	#	my $defaults = {
	#						"(default)"                => "",
	#						"block unregistered users" => "autoconfirmed",
	#						"Sysops only"              => "sysop"
	#					};

	my $url = "$wiki?title=$title&action=protect&useskin=standard";
	my $success = 0;
	my $err = 'ERROR';
	my $retries = 1;
	while ( $retries-- ) {
		my $response = $::client->get( $url );
			if( $response->is_success and
				$response->content =~ m/Confirm protection.+?The action you have requested is limited to users in the group/s ) {
				logAdd( "$user does not have permission to protect $title" );
				return $success;
			}
		if( $response->is_success and
			$response->content =~ m/Confirm protection.+?You may view and change the protection level here for the page/s ) {
			# Same problem, post on line 392 doesn't return content
			$success = $response->is_success && $response->content =~ m/<input.+?name=['"]wpEditToken["'].+?value=['"](.*?)["']/s;

			%form = (
				"wpEditToken"       => $1,
				"mwProtect-expiry"  => $expiry  || "",
				"mwProtect-reason"  => $comment || "",
			);

			$form{"mwProtect-level-$_"} = $restrictions->{$_} for keys %{$restrictions};
			# Allowing for cascade option
			if( $cascade && $restrictions->{'edit'} == "sysop" ) { $form{"mwProtect-cascade"} = 1 }
			$response = post $url, \%form;
			logAdd( "Setting protect article permissions" );
			logHash( \%form );
		}
	}
	return $success;
}

# Replace parameters in a template call using examineBraces
# (done) - allow for no param hash which would result in {{template}}
# - account for both templates or parser-functions, i.e. {{foo|args..}} or {{#foo:args...}}
# - allow for multiple templates of same name by matching first param, then second etc
#
# - e.g.
#   wikiUpdateTemplate( $wiki, $title, "#foo", { 'id' => 123, 'bar' => 'baz' } )
#
#   if two #foo calls exist, then only one having an "id" param equal to 123 would be updated
#   if two have such an id, then the comparison would resort to the second arg and so on
#   if this process cannot result in an unambiguous update it should fail with an error saying so
sub wikiUpdateTemplate {
	my(
		$wiki,
		$title,
		$template, # Name of template to update
		$params  , # hashref of param/value pairs to update the template with
		$ambig   , #
		$comment ,
		$minor
	) = @_;

	$success = 0;

	$template || ( $template = "template" );
	my $wtext = wikiRawPage( $wiki, $title );
	$title = encodeTitle( $title );

	# Use examine braces to get all content
	my @articleBraces = examineBraces( $wtext );

	# Array of matches
	my @matches  = ();
	# Array of ambig braces
	my @brace    = ();
	my$templateParams;
	my $newparams;
	foreach ( @articleBraces ) {
		if( $_->{'NAME'} eq $template ) {
			push @matches, $_;
		}
	}

	if( scalar( @matches ) < 1 ) { return $success }     # no braces of matching name
	elsif( scalar( @matches ) == 1 ) {
		$templateParams = substr( $wtext, $matches->[0]->{'OFFSET'}, $matches->[0]->{'LENGTH'} );
		push @brace, $matches[0];
	}   												  # single match
	else{ 												  # ambiguous
		if( ref( $params ) !="HASH" || scalar( %$params ) < 1 ) { # no params
			return $success;
		}
		# Check $ambig is in instances of $template
			my $ambkey = (keys %{$ambig} )[0];
			my $ambvalue = $ambig->{$ambkey};
			for ( @matches ) {

				$templateParams = substr( $wtext, $_->{'OFFSET'}, $_->{'LENGTH'} );
				if( $templateParams =~ m/$ambkey\s*=\s*$ambvalue/g ) {
					push @brace, $_;
				}
			}

			if( scalar @brace > 1 ) { # None found
				logAdd( "Aborting ambiguous parameter match found" );
				return $success;
			} else {
				# Update with new parameters
				$newparams = "{{$brace[0]->{'NAME'}";
				my $isparser = ( $brace[0]->{'NAME'} =~ /:$/ );
				my $sep = ( $isparser ? "" : "|" );
				foreach( keys %$params ) {
					$newparams .= "${sep}$_=$params->{$_}";
					if( $isparser ) {
						$sep = "|";
						$isparser = 0;
					}
				}
				$newparams .= "}}";
			}
			# Update template content in article - this is NOT WORKING!
			substr( $wtext, $brace[0]->{'OFFSET'}, $brace[0]->{'LENGTH'}, $newparams );
			$success = wikiEdit( $wiki, $title, $wtext, $comment, $minor );
	}
	return $success;
}

# Using Special:Movepage/article
# wpNewTitle
# wpMovetalk (logical checkbox)
# wpMove (action=submit)
sub wikiMove {
	my( $wiki, $oldname, $newname, $reason, $movetalk ) = @_;
	$oldname = encodeTitle( $oldname );
	my $url = "$wiki?title=Special:Movepage&target=$oldname&useskin=standard";
	logAdd( "URL=>$url" );
	my $success = 0;
	my $err = 'ERROR';
	my $retries = 1;
	while ( $retries-- ) {
		my $response = $::client->get( $url );

		# Todo: Need to catch output where user does not have move privileges

		# Permissions Errors
		#You must be a registered user and logged in to move a page

		# Special:Movepage seems to move any non-existent page then throw the message after posting;
		# This action cannot be performed on this page
		# <input type="hidden" value="095485e50db577baa80c407d0e032e43+\" name="wpEditToken"/>
		#### Interesting 'value' and 'name' can be reversed, and single or double quoted

		if( $response->is_success && $response->content =~ m/<h1 class="firstHeading">Permissions Errors<\/h1>/ ) {
			logAdd( "User $user does not have permissions to move $oldname" );
			return 0;
		}

		if( $response->is_success && $response->content =~ m/<h1 class="firstHeading">Move page<\/h1>/ ) {
			$success = $response->is_success;
			$response->content =~ m/<input.+?name=['"]wpEditToken["'].+?value=['"](.*?)["']/s;
			%form = (
				wpEditToken   => $1,
				wpNewTitle    => $newname,
				wpReason      => $reason   || "",
				wpMovetalk    => $movetalk || ""
			);
			$response = post "$url&action=submit", \%form;
			logAdd( "Moving $oldname to $newname" );
		}
	}
	return $success;
}

# Return information on brace-structure in passed wikitext
# - see http://www.organicdesign.co.nz/MediaWiki_code_snippets
sub wikiExamineBraces {
	my $content = shift;
	my @braces  = ();
	my @depths  = ();
	my $depth   = 0;
	while ( $content =~ m/\G.*?(\{\{\s*([#a-z0-9_]+:?)|\}\})/sig ) {
		my $offset = pos( $content ) - length( $2 ) - 2;
		if( $1 eq '}}' ) {
			if( $depth > 0 ) {
				$brace = $braces[$depths[$depth - 1]];
				$$brace{LENGTH} = $offset - $$brace{OFFSET} + 2;
				$$brace{DEPTH}  = $depth--;
			}
			$depth = 0 if $depth < 0;
		} else {
			push @braces, { NAME => $2, OFFSET => $offset };
			$depths[$depth++] = $#braces;
		}
	}
	return @braces;
}

# Create a GUID article title compatible with the RecordAdmin extension
# - allow a date to be sent if the GUID is being back-dated
sub wikiGuid {
	my $date = shift;
	my $guid;
	if( $date ) {
		$guid = '01' if $date =~ /jan/i;
		$guid = '02' if $date =~ /feb/i;
		$guid = '03' if $date =~ /mar/i;
		$guid = '04' if $date =~ /apr/i;
		$guid = '05' if $date =~ /may/i;
		$guid = '06' if $date =~ /jun/i;
		$guid = '07' if $date =~ /jul/i;
		$guid = '08' if $date =~ /aug/i;
		$guid = '09' if $date =~ /sep/i;
		$guid = '10' if $date =~ /oct/i;
		$guid = '11' if $date =~ /nov/i;
		$guid = '12' if $date =~ /dec/i;
		$guid = $guid . '0' . $2 if $date =~ /(^|[, ])(\d{1}) /;
		$guid = $guid . $2 if $date =~ /(^|[, ])(\d{2}) /;
		$guid = $1 . $guid if $date =~ /(\d{4})/;
	} else {
		$guid = strftime( '%Y%m%d', localtime );
	}
	$guid .= '-';
	$guid .= chr( rand() < 0.72 ? int( rand( 26 ) + 65 ) : int( rand( 10 ) + 48 ) ) for 1 .. 5;
	return $guid;
}

# Get a configuration variable value from wikia.php
sub wikiGetConfig {
	my $var = shift;
	return $1 if qx( cat /var/www/extensions/wikia.php|grep $var ) =~ /'(.+)'/;
}

# Return a list of all page titles in the passed namespace
sub wikiAllPages {
	my $wiki = shift;
	my $ns = shift;
	$ns = 0 unless $ns;
	$wiki =~ s/index.php/api.php/;
	my $url = "$wiki?action=query&list=allpages&format=json&apfilterredir=nonredirects&apnamespace=$ns&aplimit=5000";
	my $json = $::client->get( $url )->content;
	my @list = $json =~ /"title":"(.+?[^\\])"/g;
	for( @list ) {
		s/\\u([0-9a-f]{4})/chr hex $1/eg;
		$_ = encode( 'utf-8', $_ );
		s/\\//g;
	}
	return @list;
}

# Create or update a user account
sub wikiUpdateAccount {
	my( $wiki, $user, $pass, $db, %prefs ) = @_;
	my $User = ucfirst $user;
	my @row = ();

	# DB connection supplied, update directly
	if( defined $db ) {

		# If prefs were supplied, update or create the row
		if( %prefs ) {

			# Build the prefs into a format compatible with SET
			my @values = ();
			delete $prefs{user_id};
			delete $prefs{user_name};
			delete $prefs{user_password};
			push @values, "$k='$v'" while( $k, $v ) = each %prefs;
			my $values = join ',', @values;

			# Get the user id if the user already exists
			my $query = $db->prepare( 'SELECT user_id FROM ' . $::dbpre . 'user WHERE user_name="' . $User . '"' );
			$query->execute();
			my $id = $row[0] if @row = $query->fetchrow;
			$query->finish;

			# Update the values in the existing row if the id was found
			if( defined $id ) {
				my $query = $db->prepare( 'UPDATE ' . $::dbpre . 'user SET ' . $values . 'WHERE user_id=' . $id );
				$query->execute();
				$query->finish;
				logAdd( "Prefs set for user \"$User\" (user_id $id) in $::dbname.$::dbpre user table" );
			}

			# Otherwise insert the values into a new row
			else {
				my $query = $db->prepare( 'INSERT INTO ' . $::dbpre . 'user SET user_name="' . $User . '",' . $values );
				$query->execute();
				$query->finish;
				logAdd( "User \"$User\" added to $::dbname.$::dbpre user table" );
			}
		}

		# Get the row (reading again incase it was just inserted)
		my $query = $db->prepare( 'SELECT user_id FROM ' . $::dbpre . 'user WHERE user_name="' . $User . '"' );
		$query->execute();
		my $id = $row[0] if @row = $query->fetchrow;
		$query->finish;

		# Set the password for the id
		my $encpass = md5_hex( $id . '-' . md5_hex( $pass ) );
		my $query = $db->prepare( 'UPDATE ' . $::dbpre . 'user SET user_password="' . $encpass . '" WHERE user_id=' . $id );
		$query->execute();
		$query->finish;
		logAdd( "Password set for \"$User\" (user_id $id)" );
	}

	# No DB connection supplied, use HTTP
	else {
		die "HTTP account update/create not implemented yet.";
	}
}


# Use edit-preview to parse wikitext into HTML
# - set $links to 1 to return as a list of link titles instead of HTML
sub wikiParse {
	my( $wiki, $content, $links ) = @_;

	# Request the page for editing and extract the edit-token
	my $html = '';
	my $marker = '<p class="wikiParseMarker"></p>';
	my $response = $::client->get( "$wiki?title=Sandbox&action=edit&useskin=standard" );
	if( $response->is_success and (
		$response->content =~ m|<input type=['"]hidden["'] value=['"](.+?)["'] name=['"]wpEditToken["'] />|
	)) {

		# Got token etc, construct a form data structure to post
		my %form = ( wpEditToken => $1, wpTextbox1 => "$marker\n$content\n$marker", wpPreview => 'Show preview' );
		$form{wpSection}     = $1 if $response->content =~ m|<input type=['"]hidden["'] value=['"](.*?)["'] name=['"]wpSection["'] />|;
		$form{wpStarttime}   = $1 if $response->content =~ m|<input type=['"]hidden["'] value=['"](.*?)["'] name=['"]wpStarttime["'] />|;
		$form{wpEdittime}    = $1 if $response->content =~ m|<input type=['"]hidden["'] value=['"](.*?)["'] name=['"]wpEdittime["'] />|;
		$form{wpAutoSummary} = $1 if $response->content =~ m|<input name=['"]wpAutoSummary["'] type=['"]hidden["'] value=['"](.*?)["'] />|;

		# Post the form
		$response = post "$wiki?title=Sandbox&action=submit&useskin=standard", \%form;
		$html = $response->content if $response->content =~ m|<div class=["']previewnote["']>|;

		# Extract preview content out of resulting page
		$html = $1 if $html =~ m|$marker\s*(.+)\s*$marker|s;
	}

	return $links ? $html =~ m|title="(.+?)"|g : $html;
}

# Get the preferences for the passed user name
# - requires globals for DB connection and table prefix, $::db and $::dbpre
# - actually this returns a hash of the users whole DB row including prefs in user_options
# - add the fields from the Person Record if there is one
sub wikiGetPreferences {
	my $user = ucfirst shift;
	return logAdd( "Could not get preferences for user \"$user\", no DB connection!" ) unless defined $::db;

	# Fetch a hash of the users DB row
	my $query = $::db->prepare( 'SELECT * FROM ' . $::dbpre . 'user WHERE user_name="' . $user . '"' );
	$query->execute();
	my %prefs = %{ $query->fetchrow_hashref };
	$query->finish;

	# If the user has a corresponding Person record, grab that too
	if( $prefs{user_real_name} ) {

		# Get the text of the Person record from the DB
		my $name = $prefs{user_real_name};
		$name =~ s/ /_/g;
		my $query = $::db->prepare( 'SELECT page_latest FROM ' . $::dbpre . 'page WHERE page_title="' . $name . '"' );
		$query->execute();
		my $rev_id = $query->fetchrow;
		$query->finish;
		my $query = $::db->prepare( 'SELECT rev_text_id FROM ' . $::dbpre . 'revision WHERE rev_id=' . $rev_id );
		$query->execute();
		my $text_id = $query->fetchrow;
		$query->finish;
		my $query = $::db->prepare( 'SELECT old_text FROM ' . $::dbpre . 'text WHERE old_id=' . $text_id );
		$query->execute();
		my $text = $query->fetchrow;
		$query->finish;

		# Extract the parameters from the record text
		my @braces = wikiExamineBraces( $text );
		my $text = substr $text, $braces[0]->{OFFSET}, $braces[0]->{LENGTH};
		my %person = $text =~ /(?<=\|)\s*(\w+)\s*=\s*(.*?)\s*$\s*[|}]/msg;
		
		# Copy the parameters into the prefs hash
		$prefs{$_} = $person{$_} for keys %person;
	}
	
	return %prefs;
}

# Return a hash of properties from the first template of the passed title
sub wikiGetProperties {
	my( $wiki, $title ) = @_;
	my $text   = wikiRawPage( $wiki, $title );
	my @braces = wikiExamineBraces( $text );
	my $text = substr $text, $braces[0]->{OFFSET}, $braces[0]->{LENGTH};
	return ( $text =~ /(?<=\|)\s*(\w+)\s*=\s*(.*?)\s*$\s*[|}]/msg );
}

# Return a hash of properties that have changed in the last revision
# - we assume that the passed title has at least two revisions
# - and that it is a record with the first brace structure being the record type
# - an array of record type and three hashrefs is returned, original values, new values, changed values
sub wikiPropertyChanges {
	my( $wiki, $title ) = @_;
	$title = encodeTitle( $title );

	# Get the second to last revision if there is one
	my $response = $::client->request( HTTP::Request->new( GET => "$wiki?title=$title&action=history&limit=1&useskin=standard" ) );
	if( $response->is_success and $response->content =~ m|<a.+?\?title=.+?&(amp;)?diff=\d+&(amp;)?oldid=(\d+)| ) {

		# Get the text of the last two revisions
		my $text1 = wikiRawPage( $wiki, $title, 0, $3 );
		my $text2 = wikiRawPage( $wiki, $title );

		# Get the first brace statement of the last and previous revisions
		my @brace1 = wikiExamineBraces( $text1 );
		my @brace2 = wikiExamineBraces( $text2 );

		# Return nothing if results aren't sane
		return undef if $#brace1 < 0 or $#brace2 < 0;
		return undef if $brace1[0]->{NAME} ne $brace2[0]->{NAME};
		
		# Extract the brace segments from their respective content
		my $text1 = substr $text1, $brace1[0]->{OFFSET}, $brace1[0]->{LENGTH};
		my $text2 = substr $text2, $brace2[0]->{OFFSET}, $brace2[0]->{LENGTH};

		# Convert both sets of parameters into hashes
		my %args1 = ( $text1 =~ /(?<=\|)\s*(\w+)\s*=\s*(.*?)\s*$\s*[|}]/msg );
		my %args2 = ( $text2 =~ /(?<=\|)\s*(\w+)\s*=\s*(.*?)\s*$\s*[|}]/msg );

		# Ensure their are no keys in the first that aren't in the second
		for my $k ( keys %args1 ) {
			$args2{$k} = '' unless exists $args2{$k};
		}

		# Merge the two sets into a single one containing just the changes
		my %args = ();
		for my $k ( keys %args2 ) {
			my $v = $args2{$k};
			if( exists $args1{$k} ) {
				$args{$k} = $v if $args1{$k} ne $v;
			} else {
				$args{$k} = $v;
			}
		}

		# Return the record type and the hash of changed properties
		return ( $brace1[0]->{NAME}, \%args1, \%args2, \%args );
	}
}

# Return the hash path for the passed file title
sub wikiGetHashPath {
	my $hash = md5_hex( shift );
	my $path = '';
	$path .= substr( $hash, 0, $_ ) . '/' for( 1 .. 2 );
	return $path;
}

# Return the article ID of the passed title
sub wikiGetArticleID {
	my $api = shift;
	$api =~ s/index/api/;
	$res = post $api, {
		action => 'query',
		titles => shift,
		format => 'xml',
		prop => 'info'
	};
	$xml = XMLin( $res->content );
	return $xml->{'query'}->{'pages'}->{'page'}->{'pageid'};
}
