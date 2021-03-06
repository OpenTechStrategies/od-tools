#!/usr/bin/perl
#
# wikid.pl - Organic Design Wiki Daemon
#
# - Version 2.00 started on 2007-04-26
# - Version 3.00 started on 2009-04-29
#
# - See http://www.organicdesign.co.nz/Talk:Wikid.pl
#
#
# Copyright (C) 2007-2010 Aran Dunkley and others.
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
qx( cd /var/www/tools );
$dir = '/var/www/tools';

# Dependencies
use POSIX qw( strftime setsid );
use HTTP::Request;
use LWP::UserAgent;
use Expect;
use Net::SCP::Expect;
use Crypt::CBC;
use IO::Socket;
use IO::Socket::SSL;
use IO::Select;
use MIME::Base64;
use HTML::Entities;
use Sys::Hostname;
use DBI;
use PHP::Serialization qw( serialize unserialize );
require "$dir/wiki.pl";

# Daemon parameters
$daemon   = 'wikid';
$host     = uc( hostname );
$name     = hostname;
$port     = 1729;
$ver      = '3.19.8'; # 2014-07-15
$log      = "$dir/$daemon.log";
$wkfile   = "$dir/$daemon.work";

# Wiki - try and determine wikidb from wiki's localsettings.php
if ( -e '/var/www/domains/localhost/LocalSettings.php' ) {
	my $ls = readFile( '/var/www/domains/localhost/LocalSettings.php' );
	$::dbname = $1 if $ls =~ /\$wgDBname\s*=\s*['"](.+?)["']/;
	$::dbpre  = $1 if $ls =~ /\$wgDBprefix\s*=\s*['"](.+?)["']/;
	$::short  = $1 if $ls =~ /\$wgShortName\s*=\s*['"](.+?)["']/;
}

# Pre-conf defaults
$motd       = "$daemon ($ver) has started";
$user       = lc $name;
$wiki       = 'http://localhost/wiki/index.php';
$dnsdomain  = 'organicdesign.tv';
$ircserver  = 'irc.organicdesign.co.nz';
$ircport    = 16667;
$ircchannel = '#organicdesign';
$ircpass    = '******';
$ircssl     = 1;

# Override default with conf file
# NOTE: this is included again at the end so that it can replace event functions
require "$dir/$daemon.conf";

# Post-conf defaults
$dbname   = $wgDBname     if defined $wgDBname;
$dbuser   = $wgDBuser     if defined $wgDBuser;
$dbpass   = $wgDBpassword if defined $wgDBpassword;
$dbpre    = $wgDBprefix   if defined $wgDBprefix;
$wikiuser = $daemon   unless defined $wikiuser;
$ircuser  = $name     unless defined $ircuser;
$netuser  = $wikiuser unless defined $netuser;
$netpass  = $wikipass unless defined $netpass;
$netself  = "$user.$dnsdomain:$port" unless defined $netself;

# If --rpc, send data down the running instance's event pipe and exit
if ( $ARGV[0] eq '--rpc' ) {
	die "No data supplied!" unless $ARGV[1];
	die "Data not encrypted!" unless decode_base64( $ARGV[1] ) =~ /^Salted__/;
	my $data = serialize( { 'wgScript' => $wiki, 'wgSitename' => 'RPC', 'args' => $ARGV[1] } );
	my $sock = IO::Socket::INET->new( PeerAddr => 'localhost', PeerPort => $port, Proto => 'tcp' );
	print $sock "GET RpcDoAction?$data HTTP/1.0\n\n\x00" if $sock;
	sleep 1;
	exit 0;
}

# Run as a daemon (see daemonise.pl article for more details and references regarding perl daemons)
open STDIN, '/dev/null';
open STDOUT, ">>$log";
open STDERR, ">>$log";
defined ( my $pid = fork ) or die "Can't fork: $!";
exit if $pid;
setsid or die "Can't start a new session: $!";
umask 0;
$0 = "$daemon ($name)";

# Install the service into init.d and rc2-5.d if --install arg passed
if ( $ARGV[0] eq '--install' ) {
	writeFile( my $target = "/etc/init.d/$daemon", "#!/bin/sh\n/usr/bin/perl $dir/$daemon.pl\n" );
	symlink $target, "/etc/rc$_.d/S99$daemon" for 2..5;
	symlink "$dir/$daemon.pl", "/usr/bin/$daemon";
	chmod 0755, "/etc/init.d/$daemon";
	logAdd( "$daemon added to /etc/init.d and /usr/bin" );
}

# Remove the named service and exit
if ( $ARGV[0] eq '--remove' ) {
	unlink "/etc/rc$_.d/S99$daemon" for 2..5;
	unlink "/etc/init.d/$daemon";
	logAdd( "$daemon.sh removed from /etc/init.d" );
	exit 0;
}

# Initialise services, current work, logins and connections
serverInitialise();
ircInitialise();
wikiLogin( $wiki, $wikiuser, $wikipass );
dbConnect() if defined $dbuser;
%streams = ();
workInitialise();
logIRC( $motd );

# Initialise watched files list
# TODO: this list should be drawn from shared record index
my @files = ( '/var/log/auth.log', '/var/log/syslog', '/var/log/svn.log' );
my %files = ();
for ( @files ) {
	if ( -e $_ ) {
		my @stat = stat $_;
		$files{$_} = $stat[7];
	}
}


#---------------------------------------------------------------------------------------------------------#
# MAIN SERVER & CRON LOOP
my $i = 0;
my $mins = 0;
my $minute = 0;
while( 1 ) {

	# Check one of the files in the list for size change each iteration
	my $file = $files[ $i = $i < $#files ? $i + 1 : 0 ];
	my @stat = stat $file;
	my $size = $stat[7];
	if ( $size != $files{$file} ) {
		onFileChanged( $file, $files{$file}, $size );
		$files{$file} = $size;
	}

	# Handle current socket connections
	serverHandleConnections();

	# Handle current IRC connections
	ircHandleConnections();

	# Execute a job from the current work
	workExecute();
	
	# Run regular functions ("every-n-minute" functions)
	if ( time() > $minute ) {
		for ( keys %:: ) {
			if ( /^(.+)_every([0-9]+)minutes?$/i and defined &$_ and $mins % $2 == 0 ) {
				logAdd( "Executing periodic \"$1\" function" ) unless $2 < 10;
				&$_;
			}
		}
		$minute = time() + 60;
		$mins++;
	}

	sleep( 1 );
}


#---------------------------------------------------------------------------------------------------------#
# IN-BUILT SCHEDULED TASKS
# - "every-n-minute" functions - having names matching /^(.+)_every([0-9]+)minutes?$/i

# Keep wiki DB connection alive
sub DatabaseKeepAlive_every1minute {
	if ( defined $::db ) {
		my $q = $::db->prepare( 'SELECT 0' ) or die "Couldn't prepare DB: $!";
		$q->execute() or logAdd( "DB connection gone away, reconnecting..." ) && dbConnect();
		$q->finish;
	}
}

# Update the dynamic DNS
sub DynamicDNS_every10minutes {
	if ( defined $::dnspass ) {
		my $host = lc $::name;
		my $url = "http://dynamicdns.park-your-domain.com/update?host=$host&domain=$dnsdomain&password=$dnspass";
		my $response = $::client->get( $url );
		logAdd( "DDNS update error: $1" ) if $response->content =~ m/<Err1>(.+?)<\/Err1>/;
	}
}

# Update the extensions and tools each day and restart
sub UpdateEnvironment_every1440minutes {
	if ( $::wiki ) {

		# Update /var/www/extensions
		#qx( /var/www/tools/update-extensions.sh );
		#logAll( "Updated /var/www/extensions from OD snapshot" );

		# Update /var/www/tools
		#qx( /var/www/tools/update-tools.sh );
		#logAll( "Updated /var/www/tools from OD snapshot" );

		# Update the local wiki's content to the OD content snapshot
		#qx( /var/www/tools/update-content.sh );
		#logAll( "Updated local wiki content from OD snapshot" );

	}
}

#---------------------------------------------------------------------------------------------------------#
# GENERAL SUPPORT FUNCTIONS

# Output a comment to the wiki and IRC channel
sub notify {
	my $comment = shift;
	wikiAppend( $wiki, 'Server log', "\n*" . localtime() . " : $comment", "\n$comment" );
	logIRC( $comment );
}

# Read and return content from passed file
sub readFile {
	my $file = shift;
	if ( open FH, '<', $file ) {
		binmode FH;
		sysread FH, ( my $out ), -s $file;
		close FH;
		return $out;
	}
}

# Write passed content to passed file
sub writeFile {
	my $file = shift;
	if ( open FH,'>', $file ) {
		binmode FH;
		print FH shift;
		close FH;
		return $file;
	}
}

# Read in and execute a snippet
sub declare {
	$::subname = shift;
	if ( open FH, '<', $::subname ) {
		logAdd( "Declaring \"$::subname\"" ) unless $@;
		binmode FH;
		sysread FH, ( my $code ), -s $::subname;
		close FH;
		eval $code;
		logAdd( "\"$::subname\" failed: $@" ) if $@;
	}
	else { logAdd( "Couldn't declare $::subname!" ) }
	$::subname = '';
}

# Function for spawning a child to execute a function by name
sub spawn {
	my $subname = shift;
	my $subref = eval '\&$subname';
	$SIG{CHLD} = 'IGNORE';
	if ( defined( my $pid = fork ) ) {
		if ( $pid ) { logAdd( "Spawned child ($pid) for \"$subname\"" ) }
		else {
			$::subname = $subname;
			$0 = "$::daemon: $::name ($subname)";
			&$subref( @_ );
			exit;
		}
	}
	else { logAdd( "Cannot fork a child for \"$subname\": $!" ) }
}

# Function to start an instance of this daemon
sub start {
	qx( $::daemon );
}

# Establish a connection to the local wiki DB
sub dbConnect {
	my $msg = '';
	if ( $::db = DBI->connect( "DBI:mysql:$::dbname", $::dbuser, $::dbpass ) ) {
		$msg = "Connected '$::dbuser' to DBI:mysql:$::dbname";
	} else { $msg = "Could not connect '$::dbuser' to '$::dbname': " . DBI->errstr }
	logAdd( $msg );
}

# Execute a Unison file synchronisation
sub unison {
	my $dir = shift;
	my @opt = ( @_ );

	# Bail if unison is all ready running for this dir
	$ps = qx( ps x );
	logAll( "Not spawning unison child for \"$dir\", last instance still running" ) if $ps =~ /$::daemon-unison $dir/;

	# Start a thread to synchronise this dir (glob)
	$SIG{CHLD} = 'IGNORE';
	if ( defined( my $pid = fork ) ) {
		if ( $pid ) { logAdd( "Spawning child thread ($pid) for \"$dir\"" ) }
		else {
			
			# Set the child process name so we can see if it's still running next time
			$0 = "$::daemon-unison $dir";
			
			# Build the unison options
			my $options = '';
			while ( $#opt > 0 ) {
				my $k = shift @opt;
				my $v = shift @opt;
				$options .= " -$k \"$v\"";
			}

			# Loop through the dirs (that the glob resolves to) and sync each with the same dir in the next peer
			for ( glob $dir ) {
				$cmd = "unison $_ ssh://$::netuser\@$::netpeer/$_ -owner -group -batch -log -logfile /var/log/syslog $options";
				logAdd( $cmd );
				$exp = Expect->spawn( $cmd );
				$exp->expect( undef,
					[ qr/password:/ => sub { my $exp = shift; $exp->send( "$::netpass\n" ); exp_continue; } ]
				);
				$exp->soft_close();
			}

			exit;
		}
	} else { logAdd( "Could not fork unison child: $!" ) }

}

#---------------------------------------------------------------------------------------------------------#
# SERVER FUNCTIONS

# Initialise server listening on our port
sub serverInitialise {
	$::server = new IO::Socket::INET( Listen => 1, LocalPort => $::port, Proto => 'tcp', ReuseAddr => 1 )
		or die "Port $::port in use, exiting.";
	$::select = new IO::Select $::server;
	logAdd( "Listening on port $::port" );
}

# Handle streams from select list needing attention
sub serverHandleConnections {
	for my $handle ( $::select->can_read( 1 ) ) {
		my $stream = fileno $handle;

		# Handle is the server, set up a new stream
		if ( $handle == $::server ) {
			my $newhandle = $::server->accept;
			$stream = fileno $newhandle;
			$::select->add($newhandle);
			$::streams{$stream}{buffer} = '';
			$::streams{$stream}{handle} = $newhandle;
			logAdd( "New connection: Stream$stream", 'main/new' );
		}

		# Handle is an existing stream with data to read
		# NOTE: we should disconnect after certain size limit
		# - Process (and remove) all complete messages from this peer's buffer
		elsif ( sysread $handle, my $input, 10000 ) {
			$::streams{$stream}{buffer} .= $input;
			if ( $::streams{$stream}{buffer} =~ s/^(.*\r?\n\r?\n\x00)//s ) {
				serverProcessMessage( $stream, $_ ) for split /\r?\n\r?\n\x00/, $1;
			}
		}

		# Handle is an existing stream with no more data to read
		else { serverDisconnect( $handle ) }

	}
}

# Close a handle and clean up
sub serverDisconnect {
	my $stream = shift;
	my $handle = $::streams{$stream}{handle};
	return unless defined $handle;
	$::select->remove( $handle );
	delete $::streams{$stream};
	$handle->close();
	logAdd( "Stream$stream disconnected." );
}

# Process an incoming HTTP message
sub serverProcessMessage {
	my ( $stream, $msg ) = @_;
	my $handle = $::streams{$stream}{handle};
	my $headers = '';
	my $http = '200 OK';
	my $respond = 1;
	my $date = strftime "%a, %d %b %Y %H:%M:%S %Z", localtime;
	my $response = 'done';

	# Extract info from the HTTP request
	my ( $title, $ver ) =
		$msg =~ /(GET|POST)\s+(.*?)\s+(HTTP\/[0-9.]+)/s ? ( $2, $3 ) : ( 'default', 'HTTP/1.1' );

	# If request authenticates service it, else return 401
	if ( $ct =~ /^cmd/ ? ( $msg =~ /Authorization: Basic (\w+)/ and decode_base64( $1 ) eq "$::name:$::password" ) : 1 ) {

		# Call event handler for received event if one exists
		if ( $::data = $title =~ /^(.+?)\?(.+)$/s ? $2 : '' ) {
			$hook     = $1;
			$::data   = unserialize( $::data );
			$::script = $$::data{wgScript};
			$::site   = $$::data{wgSitename};
			$::event  = "on$hook";
			if ( $::script and defined &$::event ) {
				logAdd( "Processing \"$hook\" hook from $::site" );
				&$::event;

				# Handle property changes separately from RevisionInsertComplete
				if ( $hook eq 'RevisionInsertComplete' ) {
					my %revision = %{$$::data{args}[0]};
					my $title = $revision{mTitle};
					my( $type, $args1, $args2, $args ) = wikiPropertyChanges( $::script, $title );
					my $handler = 'on' . $type . 'PropertyChange';
					if ( defined &$handler ) {
						&$handler( $title, $args1, $args2, $args );
						logAdd( "$type properties changed in $::site" );
					}
				}

			} else { logAdd( "Unknown event \"$hook\" received!" ) }
		}

	} else { $http = "401 Authorization Required\r\nWWW-Authenticate: Basic realm=\"private\"" }

	# Send response back to requestor
	if ( $respond ) {
		$headers = "$ver $http\r\nDate: $date\r\nServer: $::daemon::$::name\r\n$headers";
		$headers .= "Content-Type: $ct\r\n";
		$headers .= "Connection: close\r\n";
		$headers .= "Content-Length: " . ( length $response ) . "\r\n";
		print $handle "$headers\r\n$response";
		serverDisconnect( $stream );
	}
}

#---------------------------------------------------------------------------------------------------------#
# IRC FUNCTIONS

sub ircInitialise {
	return unless $::ircserver;

	# If retrying connection, return unless retry period expired
	if ( defined $::ircLastTry ) {
		return unless time() - $::ircLastTry > 30;
	}

	# Attempt connection with the IRC server
	if ( $::ircssl ) {
		$::ircsock = new IO::Socket::SSL( PeerAddr => $::ircserver, PeerPort => $::ircport, Proto => 'tcp' );
	} else {
		$::ircsock = new IO::Socket::INET( PeerAddr => $::ircserver, PeerPort => $::ircport, Proto => 'tcp' );
	}

	# If connected, do login sequence
	if ( $::ircsock ) {
		print $::ircsock "PASS $ircpass\nNICK [$ircuser]\nUSER $ircuser 0 0 :$::daemon\n";
		while ( <$::ircsock> ) {

			# if the server asks for a ping
			print $::ircsock "PONG :" . ( split( / :/, $_ ) )[1] if /^PING/;

			# end of MOTD section
			if ( / (376|422) / ) {
				print $::ircsock "NICKSERV :identify $ircuser $ircpass\n";
				last;
			}
		}

		# Set up listener on the socket
		$::ircselect = new IO::Select $::ircsock;

		# Don't retry anymore
		$::ircLastTry = undef;

		# Wait for a few secs and join the channel
		sleep 3;
		print $::ircsock "JOIN $ircchannel\n";
		logAdd( "$ircuser connected to $ircserver:$ircport" );
	}

	# Connecting to the IRC server failed, try again soon
	else {
		 logAdd( "Couldn't connect to the IRC server ($ircserver:$ircport), will try again soon..." );
		 $::ircLastTry = time();
	}
}

# Handle streams from select list needing attention
sub ircHandleConnections {
	return unless $::ircserver;
	ircInitialise() if defined $::ircLastTry;
	return unless $::ircselect;
	for my $handle ( $::ircselect->can_read( 1 ) ) {
		my $stream = fileno $handle;
		if ( sysread $handle, my $data, 100 ) {

			# Append the data to the appropriate stream
			$::streams{$stream} = exists( $::streams{$stream} ) ? $::streams{$stream} . $data : $data;

			# Remove and process any complete messages in the stream
			if ( $::streams{$stream} =~ s/^(.*\r?\n)//s ) {
				for ( split /\r?\n/, $1 ) {

					( $command, $text ) = split( / :/, $_ );

					# Respond to pings if any
					if ( $command eq 'PING' ) {
						$text =~ s/[\r\n]//g;
						print $handle "PONG $text\n";
						next;
					}

					# Extract info and tidy
					my( $nick, $type, $chan ) = split( / /, $_ );
					my( $nick, $host ) = split( /!/, $nick );
					$nick =~ s/://;
					$text =~ s/[:\r\n]+//;

					# Process if the line is a message in the channel
					if ( $chan eq $ircchannel ) {
						$ts = localtime();
						$ts = $1 if $ts =~ /(\d\d:\d\d:\d\d)/;
						logAdd( "[IRC/$nick] $text" ) if $ircserver eq '127.0.0.1';

						# Perform an action if it exists
						if ( $text =~ /^($ircuser|$::daemon) do (.+)(\s+(.+))?$/i ) {
							$title = ucfirst $2;
							$::args = $4;
							$::action = "do$title";
							if ( defined &$::action ) {
								logAll( "Processing \"$title\" action issued by $nick" );
								&$::action;
							} else { logAll( "Unknown action \"$title\" requested!" ) }
						}
					}
				}
			}
		}

		# Stream closed, try reconnecting
		else {
			logAdd( "Disconnected from $::ircserver:$::ircport" );
			ircDisconnect( $handle );
			ircInitialise();
		}
	}
}

# Close an IRC handle and clean up
sub ircDisconnect {
	my $handle = shift;
	$::ircselect->remove( $handle );
	delete $::streams{$stream};
	$handle->close();
	logAdd( "IRC Stream$stream disconnected." );
}

# Output a comment into the IRC channel
sub logIRC {
	my $msg = shift;
	print $::ircsock "PRIVMSG $ircchannel :$msg\n" if $::ircsock;
	return $msg;
}

# OUtput a comment to both IRC and normal log
sub logAll {
	my $msg = shift;
	logAdd( $msg );
	logIRC( $msg );
	return $msg;
}


#---------------------------------------------------------------------------------------------------------#
# FILE EVENTS

sub onFileChanged {
	my $file    = shift;
	my $oldsize = shift;
	my $newsize = shift;
	my $text    = '';
	my $msg     = '';
	my @userfilter = ( $::netuser, 'root', 'nobody', 'fit', 'munin', 'svn' );

	# Read in difference
	if ( $newsize > $oldsize and open FH, '<', $file ) {
		binmode FH;
		seek FH, $oldsize, 0;
		sysread FH, $text, $newsize - $oldsize;
		close FH;
	}
	
	# User SSH start
	$msg = "$1 shelled in to $::host" if $text =~ /session opened for user ([-_a-z0-9]+) by/ && !grep $_ eq $1, @userfilter;

	# User SSH stop
	$msg = "$1 shelled out of $::host" if $text =~ /session closed for user ([-_a-z0-9]+)/ && !grep $_ eq $1, @userfilter;

	# Su to root
	$msg = "$1 is now root on $::host" if $text =~ /Successful su for root by ([-_a-z0-9]+)/;

	# VPN connection
	$msg = "VPN connection established from $1" if $text =~ /Peer Connection Initiated with ([0-9.]+):/;

	# Unison synchronisation of file changes completed
	$msg = $text if $text =~ /Synchronization complete/;

	# SVN commits
	$msg = $text if $text =~ /repo updated to revision/;

	logIRC( $msg ) if $msg;

}



#---------------------------------------------------------------------------------------------------------#
# WIKI EVENTS
# $::script, $::site, $::event, $::data available

# Run an action sent from another peer
sub onRpcDoAction {

	# Decrypt $::data if encrypted
	my $cipher = Crypt::CBC->new( -key => $::netpass, -cipher => 'Blowfish' ); 
	my @args   = @{ unserialize( $cipher->decrypt( decode_base64( $$::data{args} ) ) ) };

	# Extract the arguments
	my $from   = $$::data{from}   = shift @args;
	my $to     = $$::data{to}     = shift @args;
	my $action = $$::data{action} = shift @args;
	my $func   = "do$action";

	if ( $action ) {

		# Run the action
		defined &$func ? &$func( @args ) : logAdd( "No such action \"$action\" requested over RPC by $from" );

		# If the "to" field is empty (a broadcast message), send the action to the next peer
		rpcSendAction( $from, $::netpeer, $action, @args ) unless $to;

	} else { logAdd( "No action specified!" ) }

}

sub onStartJob {
	my %job = %{$$::data{args}};
	$::job = \%job;
	workStartJob( $job{type}, -e $job{id} ? $job{id} : undef );
}

sub onStopJob {
	my $id = $$::data{args};
	return if workSetJobFromId( $id ) < 0;
	$$::job{errors} = "Job cancelled\n" . $$::job{errors};
	logAll( "Job $id cancelled" ) if workStopJob( $id );
}

sub onPauseJobToggle {
	my $id = $$::data{args};
	workSetJobFromId( $id );
	$$::job{paused} = $$::job{paused} ? 0 : 1;
	workSave();
	logAll( "Job $id " . ( $$::job{paused} ? '' : 'un' ) . "paused" );
}

sub onUserLoginComplete {
	my $user = $$::data{args}[0]{mName};
	logIRC( "$user logged in to $::site" ) if $user;
}

sub onPrefsPasswordAudit {
	if ( $$::data{args}[2] eq 'success' ) {
		my $user = $$::data{args}[0]{mName};
		my $pass = $$::data{args}[1];
		doUpdateAccount( $user, $pass );
	}
}

sub onAddNewAccount {
	my $user = $$::data{args}[0]{mName};
	my $pass = $$::data{REQUEST}{wpPassword};
	doUpdateAccount( $user, $pass ) if $user and $pass;
}

sub onRevisionInsertComplete {
	my %revision = %{$$::data{args}[0]};
	return if $revision{mMinorEdit};
	my $id       = $revision{mId};
	my $page     = $revision{mPage};
	my $user     = $revision{mUserText};
	my $parent   = $revision{mParentId};
	my $comment  = $revision{mComment};
	my $title    = $revision{mTitle};
	my $wgServer = $$::data{wgServer};
	if ( $page and $user ) {
		if ( lc $user ne lc $wikiuser ) {
			my $action = $parent ? 'changed' : 'created';
			my $utitle = $title;
			$title  =~ s/_/ /g;
			$utitle =~ s/ /_/g;
			$comment =~ s/\\("')/$1/g;
			logIRC( "$user $action: $wgServer/$utitle" );
			logIRC( "Comment: $comment" ) if $comment;
		}
	} else { logAdd( "Not processing (page='$page', user='$user', title='$title')" ) }
}


#---------------------------------------------------------------------------------------------------------#
# RECORD PROPERTY EVENTS

# Person record property changes
sub onPersonPropertyChange {
	my ( $title, $args1, $args2, $args ) = @_;
	checkEmailProperties( $title, $args2 );
}

# Role record property changes
sub onRolePropertyChange {
	my ( $title, $args1, $args2, $args ) = @_;
	checkEmailProperties( $title, $args2 );	
}

# Update email config if any email related properties have changed
# - Person and Role records have email properties
sub checkEmailProperties {
	my ( $title, $args ) = @_;
	return unless exists $$args{Email};
	return unless $$args{Email};
	my $email    = $$args{Email};
	my $euser    = $1 if $email =~ /^(.+)@/;
	my $user     = exists $$args{User} ? $$args{User} : $euser;
	$user        =~ s/\W+/_/g;
	$user        = lc $user;
	return unless $user;
	my $elocal   = "$user\@localhost";

	# Config file locations
	my $vuserf = '/etc/exim4/virtual.users';
	my $vdomf  = '/etc/exim4/virtual.domains';
	my $vdom = readFile( $vdomf );

	# Bail if IMAP property not enabled for this user
	return logAdd( "IMAP option not enabled for user \"$user\", exiting without changing server configuration." ) unless $$args{IMAP};

	# Bail if primary email invalid
	return logAll( "Email address \"$email\" not valid, exiting without changing server configuration." ) unless $email =~ /^.+@(.+)$/;
	my $domain = $1;

	# Bail if not managed by this server
	logAll( "Email address \"$email\" not managed by this server, exiting without changing configuration." ) unless $vdom =~ /$domain/;

	# Bail if no home dir for this user
	logAll( "No unix account for \"$user\", exiting without changing configuration." ) unless -d "/home/$user";

	# Obtain the current rules from the virtual.users file and remove all rules for this user
	my $vuser  = readFile( $vuserf );
	my %tmp    = ( $vuser =~ /^\s*(\S+?)\s*:\s*(\S+?)\s*$/gim );
	my %rules  = ();
	for ( keys %tmp ) {
		$rules{$_} = $tmp{$_} unless $tmp{$_} eq $elocal;
	}

	# Ensure the primary email address exists and is conrrect in config
	if ( exists $rules{$email} ) {
		my $r = $rules{$email};
		logAll( "Email address $e was assigned to user \"$r\", but has been changed to \"$user\"" ) if $r ne $elocal;
	}
	$rules{$email} = $elocal;

	# If this user has an AutoReply set, update the .forward content and .vacation.msg
	if ( exists $$args{AutoReply} ) {
		my $reply = $$args{AutoReply};
		my $msgf   = "/home/$user/.vacation.msg";
		my $fwdf   = "/home/$user/.forward";
		my $fwd    = readFile( $fwdf );
		my $fwd2   = $fwd;
		my $comment = "No valid email address for \"$user\", not changing autoreply!";

		my $msg = readFile( $msgf );
		$fwd2 = $1 if $fwd2 =~ /^(.+?endif)/s;
		if ( $reply ) {
			if ( $msg ne $reply ) {
				writeFile( $msgf, $reply );
				$fwd2 = "$fwd2\n\n" . eximVacation( $domain, "Out of office auto-reply" );
				logAll( "Changing AutoReply for user \"$user\" (from \"$msg\" to \"$reply\")" )
			}
		} else {
			unlink $msgf;
			logAll( "Clearing AutoReply for user \"$user\"" );
		}

		# Update this users .forward file if changed
		if ( $fwd ne $fwd2 ) {
			writeFile( $fwdf, $fwd2 );
			logAll( "$fwdf updated" );
		}
	}

	# Loop through five potential sub-accounts for this user (base account plus up to four additional)
	for my $i ( '', 2, 3, 4, 5 ) {
		if ( $$args{"User$i"} ) {
			my $account = $user . $i;
			$account =~ s/\W+/_/g;
			$account = lc $account;
			if ( -d "/home/$account" ) {
				my $alocal = "$account\@localhost";
			
				# If this account has EmailAliases, add them to the virtual.users rules
				if ( exists $$args{"EmailAliases$i"} ) {
					$rules{$_} = $alocal for split /\s+/, $$args{"EmailAliases$i"};
				}
				
				# If this account has EmailForwards, update the account's .forward file
				my $fwdf = "/home/$account/.forward";
				my $fwd  = readFile( $fwdf );
				my $fwd2 = $fwd;
				$fwd2 = $1 if $fwd2 =~ /^(.+?)\s*# Forwards/s;
				if ( exists $$args{"EmailForwards$i"} ) {
					my @forwards = split /\s+/, $$args{"EmailForwards$i"};
					if ( $#forwards >= 0 ) {
						$fwd2 .= "\n\n# Forwards\n";
						$fwd2 .= "deliver $_\n" for @forwards;
					}
					if ( $fwd ne $fwd2 ) {
						writeFile( $fwdf, $fwd2 );
						logAll( "$fwdf updated" );
					}
				}
			} else { logAll( "No unix account for \"$account\", set password for user \"$user\" to create it." ) }
		}
	}

	# Remove any virtual.users rules which are not listed in virtual.domains
	$vdom =~ s/^\s*//g;
	$vdom =~ s/\s*$//g;
	$vdom =~ s/\s+/\|/g;
	my %tmp = ( %rules );
	my %rules = ();
	for my $k ( keys %tmp ) {
		$rules{$k} = $tmp{$k} if $k =~ /\@$vdom/;
	}

	# Build nicely spaced virtual.users file from the rules
	my $vuser2 = '';
	my $longest = 0;
	my $last = 0;
	for my $k ( keys %rules ) {
		my $l = length $k;
		$longest = $l if $l > $longest;
	}
	for my $k ( sort { ( $a =~ /^(.+)\@(.+)$/ . $2 . $1 ) cmp ( $b =~ /^(.+)\@(.+)$/ . $2 . $1 ) } keys %rules ) {
		if ( $k =~ /^.+\@(.+)$/ and $1 ne $last ) {
			$vuser2 .= "\n" if $last;
			$last = $1;
		}
		my $v = $rules{$k};
		my $l = length $k;
		my $line = $k . ( ' ' x ( $longest + 2 - $l ) ) . ": $v";
		$vuser2 .= "$line\n";
	}

	# Update virtual.users file if changed
	if ( $vuser ne $vuser2 ) {
		writeFile( $vuserf, $vuser2 );
		logAll( "$vuserf updated" );
	}
}

# Returns a vacation statement for an exim .forward file
sub eximVacation {
	my $domain = shift;
	my $subject = shift;
"if
	not error_message and
	\$message_headers does not contain \"\\nList-\" and
	\$h_auto-submitted: does not contain \"auto-\" and
	\$h_precedence: does not contain \"bulk\" and
	\$h_precedence: does not contain \"list\" and
	\$h_precedence: does not contain \"junk\" and
	foranyaddress \$h_to: ( \$thisaddress contains \"\$local_part\@\" ) and
	not foranyaddress \$h_from: (
		\$thisaddress contains \"server@\" or
		\$thisaddress contains \"daemon@\" or
		\$thisaddress contains \"root@\" or
		\$thisaddress contains \"listserv@\" or
		\$thisaddress contains \"majordomo@\" or
		\$thisaddress contains \"-request@\" or
		\$thisaddress matches  \"^owner-[^@]+@\"
	)
then
	vacation
	from \$local_part\@$domain
	subject \"$subject\"
endif"
}


#---------------------------------------------------------------------------------------------------------#
# ACTIONS

# A user password of prefs has changed
# - if in the @netsync list changes are propagated around the wikis
# - if the user has IMAP, SSH or FTP access enabled, unix account is created/sync'd
# - the samba passwords are built from the system passwords
# - sub-accounts have the same name but with a number appended and are also password-sync'd
# - this should only ever be called for master accounts, not sub-accounts
sub doUpdateAccount {
	my $user  = lc shift; # ensure usernames are lowercase
	my $pass  = shift;
	$user =~ s/\W/_/g;    # only allow word characters in usernames
	$user =~ s/\d+$//;    # ensure master accounts don't end in numbers
	my $User = ucfirst $user;
	my %prefs = (@_);

	# Everything here requires that the global DB connection be active
	return logAll( "No DB connection available, bailing without updating user account for \"$user\"!" ) unless $::db;

	# If the @netsync array exists, and this user is in it, do the RPC stuff
	# - this will propagate regardless of whether there is an associated unix account
	unless ( defined @$::netsync and not grep /$user/i, @$::netsync ) {

		# If there are prefs then this is from RPC so we may need to create/update the local wiki account
		my @npref = keys %prefs;
		if ( $#npref >= 0 ) {

			# Update/create the local wiki account if non existent or not up to date
			# - this can happen if its an RPC action from another peer
			# - update directly in DB so that the event doesn't propagate again
			wikiUpdateAccount( $::wiki, $user, $pass, $::db, %prefs );
		}

		# Otherwise this is a local wiki account event and needs to be propagated over RPC
		else {
			%prefs = wikiGetPreferences( $user );
			rpcBroadcastAction( 'UpdateAccount', $user, $pass, %prefs );
		}
	}

	# For unix account synchronisation to occur, the user must have a Person record with IMAP,SSH or FTP enabled
	return logAll( "Not synchronising a unix account for \"$user\" because no IMAP, SSH or FTP access enabled" )
		unless $prefs{IMAP} or $prefs{SSH} or $prefs{FTP};

	# Update the master account's password or create the account and same for any sub-accounts
	# - only master accounts have an associated Samba password
	syncUnixAccount( $user, $pass, 1 );
	for ( 2 .. 5 ) { syncUnixAccount( $user.$_, $pass, 0 ) if $prefs{"User$_"} }

	# Check email properties incase account creation has occured and requires email config updates
	checkEmailProperties( $user, \%prefs );

	logIRC( "Done." );
}

# Called internally by doUpdateAccount to update/create a unix account & password
# - if $smb set then also update the corresponding Samba password
sub syncUnixAccount {
	my $user = shift;
	my $pass = shift;
	my $smb  = shift;

	# If unix account exists, set its password
	if ( -d "/home/$user" ) {
		logAll( "Updating unix account details for user \"$user\"" );
		my $exp = Expect->spawn( "passwd $user" );
		$exp->expect( 5,
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); exp_continue; } ],
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); } ],
		);
		$exp->soft_close();
	}

	# Otherwise create it now
	else {
		logAll( "Creating unix account for user \"$user\"" );
		my $exp = Expect->spawn( "adduser $user" );
		$exp->expect( 5,
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); exp_continue; } ],
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n\n\n\n\n\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/correct?/  => sub { my $exp = shift; $exp->send( "Y\n" ); exp_continue; } ],
		);
		$exp->soft_close();
	}

	# Update the samba password for this master account
	if ( $smb ) {
		if ( my $exp = Expect->spawn( "smbpasswd -a $user" ) ) {
			logAll( "Synchronising samba account" );
			$exp->expect( 5,
				[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); exp_continue; } ],
				[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); } ],
			);
			$exp->soft_close();
		}
	}
}

# Output information about self
sub doInfo {
	
	# General info
	logIRC( "I'm a $::daemon version $::ver listening on port $::port." );

	# Job info
	logIRC( "There are currently $n jobs in progress" ) unless ( $n = $#::work ) < 0;
	my $jobs = $#::types < 0 ? 'none' : join ', ', @::types;
	logIRC( "Installed job types: $jobs" );

	# Scheduled functions info
	my @f = ();
	for ( keys %:: ) { push @f, $_ if defined &$_ and /^.+_every[0-9]+minutes?$/i }
	logIRC( "Periodic functions: " . join ', ', @f );

	# Events info
	@f = ();
	for ( keys %:: ) { push @f, $1 if defined &$_ and /^on(\w+)$/ }
	logIRC( "Event handlers: " . join ', ', @f );

	# Actions info
	@f = ();
	for ( keys %:: ) { push @f, $1 if defined &$_ and /^do(\w+)$/ }
	logIRC( "Known actions: " . join ', ', @f );

}

# Obtain and return IP address
sub doIP {
	my $response = $::client->get( 'http://www.organicdesign.co.nz/wiki/info.php' );
	if( $response->is_success and $response->content =~ /REMOTE_ADDR.+?(\d+\.\d+\.\d+\.\d+)/ ) {
		logIRC( "My current IP address is $1" );
	} else { logIRC( "Unable to comply for some reason." ) }
}

# Restart
sub doRestart {
	logIRC( "Restarting..." );
	logAdd( "Closing handles..." );
	serverDisconnect $_ for keys %$::streams;
	logAdd( "Stopping listeners..." );
	$::server->shutdown(2);
	$::ircsock->shutdown(2);
	spawn "start";
	exit(0);
}

# Stop
sub doStop {
	logIRC( "Stopping..." );
	logAdd( "Closing handles..." );
	serverDisconnect $_ for keys %$::streams;
	logAdd( "Stopping listeners..." );
	$::server->shutdown(2) if $::server;
	$::ircsock->shutdown(2) if $::ircsock;
	exit 0;
}

# Update
sub doUpdate {
	if ( my $exp = Expect->spawn( "cd /var/www/tools && svn update" ) ) {
		logIRC( "Updating /var/www/tools from svn..." );
		$exp->expect( 5,
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); exp_continue; } ],
			[ qr/(^.+revision [0-9]+.*$)/ => sub { logIRC( $1 ); } ],
		);
		$exp->soft_close();
	}
}


#---------------------------------------------------------------------------------------------------------#
# RPC

# Broadcast actions are just normal RPC with the "from" set to self and an empty "to" arg
sub rpcBroadcastAction {
	rpcSendAction( $::netaddr, '', @_ );
}

# Encrypt the action and its arguments and start a job to send them
sub rpcSendAction {
	my $args   = \@_;
	my $from   = $_[0];
	my $to     = $_[1];
	my $action = $_[2];

	# no propagation if next peer not defined
	return unless $::netpeer;

	# Propagation finsihed if "to" and "from" are the same
	return if $from eq $to;

	# Initialise the job hash
	%$::job = ();
	$$::job{from} = $from;
	$$::job{to}   = $to;
	$$::job{wait} = 0;

	# Resolve peer and port of recipient
	if ( $to =~ /^(.+):([0-9]+)$/ ) {
		$$::job{peer} = $1;
		$$::job{port} = $2;
	}
	elsif ( $::netpeer =~ /^(.+):([0-9]+)$/ ) {
		$$::job{peer} = $1;
		$$::job{port} = $2;
	}
	else {
		logAdd( "initRpcSendAction: invalid recipient, \"$action\" action not propagated!" );
		return 1;
	}

	# Encrypt the data so its not stored in the work hash or sent in clear text
	$cipher = Crypt::CBC->new( -key => $::netpass, -cipher => 'Blowfish' );
	$$::job{args} = encode_base64( $cipher->encrypt( serialize( $args ) ), '' );

	# Start the job
	workStartJob( 'RpcSendAction' );
	logAdd( "initRpcSendAction: \"$action\" queued for sending to $$::job{peer}:$$::job{port}" );
}

# Try and send the action, set time for next retry if unsuccessful
sub mainRpcSendAction {

	# Bail if not ready for a retry
	return 1 if $$::job{wait} > time();

	# Get args for the remote command
	my $user = lc $::wikiuser;
	my $peer = $$::job{peer};
	my $port = $$::job{port};
	my $args = $$::job{args};
	my $ssh  = 0;

	# Attempt to execute the command remotely over SSH
	# - Net::SSH2 way would be better, but is failing
	my $exp  = Expect->spawn( "ssh -p $port $::netuser\@$peer 'wikid --rpc $args'" );
	$exp->expect( 30,
		[ qr/password:/ => sub {
			my $exp = shift;
			$exp->send( "$::netpass\n" );
			$ssh = 1;
		} ],
	);
	$exp->soft_close();
		
	# Stop job if the command was executed on the remote host (even if it failed)
	workStopJob() if $ssh;

	# If the SSH connection was not established try again in 5min or so
	unless ( $ssh ) {
		logAll( "RpcSendAction job could not establish an SSH connection with $peer, retrying in 5 minutes" );
		$$::job{wait} = time() + 300;
	}

	1;
}


#---------------------------------------------------------------------------------------------------------#
# JOBS

# Make the Restart action available as a job
sub mainRestart {
	workStopJob();
	doRestart();
}


# Read in or initialise the persistent work hash
sub workInitialise {

	# Load existing work file or create a new empty one
	if ( -e $::wkfile ) {
		workLoad();
	} else {
		@::work = ();
		$::wptr = 0;
		logAll( "New work file created" );
	}
	
	# Rebuild installed work types
	@::types = ();
	for ( keys %:: ) { push @::types, $1 if defined &$_ and /^main(\w+)$/ }
	logAll( "Installed job types: " . join ', ', @::types ) if $#::types >= 0;

	# Save any changes
	workSave();
}

# Set the global $::job hash from passed job ID
# - returns index of job in work array
sub workSetJobFromId {
	my $id = shift;
	my $i = -1;
	$::job = undef;
	for ( 0 .. $#::work ) {
		if ( $::work[$_]{id} eq $id ) {
			$::job = $::work[$_];
			$i = $_;
		}
	}
	logAll( "Job $id not found in work list!" ) if $i < 0;
	return $i;
}

# Call current jobs "main" then rotates work pointer and saves state if returned success
sub workExecute {

	# Bail if no work items
	return if $#::work < 0;

	# Move work pointer to next item and set $::job
	$::job = $::work[$::wptr++%($#::work+1)];

	# Bail if the job is paused
	return if $$::job{paused};

	# Bail if the job has no "main" to call
	my $main = 'main' . $$::job{type};
	return unless defined &$main;

	# Call the job's "main" and check for success
	if ( &$main == 1 ) {

		# Increment the *job* work pointer and stop if finished
		if ( $$::job{length} > 0 && ++$$::job{wptr} > $$::job{length} ) {
			my $id = $$::job{id};
			logAll( "Job $id has finished successfully" );
			workStopJob();
		}

		# Write back the changes to the work file
		workSave();

	} else {

		# Log an error and stop the job if its "main" doesn't return success
		my $msg = "$main() did not return success on iteration " . $$::job{wptr};
		workLogError( $msg );
		workStopJob();
		logAll( $msg );
	}
}

# Add a new job to the work queue
# - called with Type, ID (if ID not supplied, a GUID is created)
# - the new job created is $::job
# - returns the job ID
sub workStartJob {
	my $type = shift;
	my $id   = shift || wikiGuid();
	my $init = "init$type";
	my $main = "main$type";

	if ( defined &$main ) {

		# Add the new job to the work hash
		$$::job{id}        = $id;
		$$::job{type}      = $type;
		$$::job{wiki}      = $::script ? $::script : $::wiki;
		$$::job{user}      = $::wikiuser;
		$$::job{start}     = time();
		$$::job{finish}    = 0;
		$$::job{progress}  = 0;
		$$::job{revisions} = 0;
		$$::job{length}    = 0;
		$$::job{paused}    = 0;
		$$::job{status}    = '';
		$$::job{errors}    = '';
		push @::work, $::job;

		# Execute the init if defined
		&$init if defined &$init;

		# Write changes to work file
		workSave();

		logAll( "$type job started with ID $id" );

	} else { logAdd( "Unknown job type \"$type\"!" ) }
}

# Remove a job from the work queue (called to cancel and when finished)
# - if no job ID is passed, then the ID of $::job is used
sub workStopJob {
	my $id = shift;
	$id = $$::job{id} unless $id;
	my $i = workSetJobFromId( $id );
	return 0 if $i < 0;

	# Update progress
	my $progress = ( $$::job{length} > 0 ) ? ( $$::job{wptr} - 1 ) . ' of ' . $$::job{length} : $$::job{wptr};
	if ( $$::job{wptr} == $$::job{length} && $$::job{length} > 0 ) { $progress = "Job completed" }

	# Execute the job type's stop function if defined
	$$::job{finish} = time();
	my $stop = 'stop' . $$::job{type};
	&$stop if defined &$stop;

	# Append final job info to log
	$entry  = "[$id]\n";
	$entry .= "   Wiki      : " . $$::job{wiki}      . "\n";
	$entry .= "   Type      : " . $$::job{type}      . "\n";
	$entry .= "   User      : " . $$::job{user}      . "\n";
	$entry .= "   Start     : " . $$::job{start}     . "\n";
	$entry .= "   Finish    : " . $$::job{finish}    . "\n";
	$entry .= "   Progress  : " . $progress          . "\n";
	$entry .= "   Revisions : " . $$::job{revisions} . "\n";
	$entry .= "   Length    : " . $$::job{length}    . "\n";
	$entry .= "   Status    : " . $$::job{status}    . "\n";
	$entry .= "   Errors    : " . $$::job{errors}    . "\n\n";
	open WKLOGH, '>>', "$::wkfile.log" or die "Can't open $::wkfile.log for writing!";
	print WKLOGH $entry;
	close WKLOGH;

	# Remove the item from work list and write changes to work file
	my @tmp = ();
	for ( 0 .. $#::work ) { push @tmp, $::work[$_] if $i ne $_ }
	@::work = @tmp;
	workSave();
	
	delete $$::job{$id};
	1;
}

# Read the contents of the work file into the local work array, work pointer and work types array
sub workLoad {
	my $tmp  = unserialize( readFile( $::wkfile ) );
	@::work  = @{$$tmp[0]};
	$::wptr  = $$tmp[1];
	@::types = @{$$tmp[2]};
}

# Write the work array and pointer to the work file
sub workSave {
	writeFile( $::wkfile, serialize( [ \@::work, $::wptr, \@::types ] ) );
}

# Add a line to a jobs error log
sub workLogError {
	my $err = shift;
	$$::job{errors} .= $$::job{errors} ? "|$err" : $err;
	return $err;
}


# Include the config again so that it can replace default functions
require "$::dir/$::daemon.conf";
