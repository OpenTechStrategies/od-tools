#!/usr/bin/perl
# wikid.pl - Organic Design Wiki Daemon{{perl}}
# - Version 2.00 started on 2007-04-26
# - Version 3.00 started on 2009-04-29
# - See http://www.organicdesign.co.nz/Talk:Wikid.pl
# - copyright © 2007 Aran Dunkley
# - license GNU General Public Licence 2.0 or later
use POSIX qw(strftime setsid);
use FindBin qw($Bin);
use Cwd;
use HTTP::Request;
use LWP::UserAgent;
use Expect;
use Net::SCP::Expect;
use IO::Socket;
use IO::Select;
use MIME::Base64;
use Sys::Hostname;
use DBI;
require "$Bin/wiki.pl";

# Connect to DB
#my $dbh = DBI->connect('DBI:mysql:'.$::dbname, lc $::dbuser, $::dbpass) or die DBI->errstr;
#my $sth = $dbh->prepare('SELECT page_id FROM '.$::dbpfix.'page WHERE page_title = "Zhconversiontable"');
#$sth->execute();
#my @row = $sth->fetchrow_array;
#$sth->finish;
#my $sth = $dbh->prepare('SELECT page_namespace,page_title,page_is_redirect FROM '.$::dbpfix.'page WHERE page_id=?');

# Daemon parameters
$::daemon   = 'wikid';
$::host     = uc( hostname );
$::name     = hostname;
$::port     = 1729;
$::ver      = '3.2.12'; # 2009-06-11
$::dir      = $Bin;
$::log      = "$::dir/$::daemon.log";
my $motd    = "Hail Earthlings! $::daemon-$::ver is in the heeeeeouse! (rock)";

# Wiki - try and determine wikidb from wiki's localsettings.php
if ( -e '/var/www/domains/localhost/LocalSettings.php' ) {
	my $ls = readFile( '/var/www/domains/localhost/LocalSettings.php' );
	$::dbname = $1 if $ls =~ /\$wgDBname\s*=\s*['"](.+?)["']/;
	$::dbpre  = $1 if $ls =~ /\$wgDBprefix\s*=\s*['"](.+?)["']/;
	$::short  = $1 if $ls =~ /\$wgShortName\s*=\s*['"](.+?)["']/;
}

# Get DB user/pass from wikia.php
if ( -e '/var/www/extensions/wikia.php' ) {
	my $wikia = readFile( '/var/www/extensions/wikia.php' );
	$::dbuser = $1 if $wikia =~ /\$wgDBuser\s*=\s*['"](.+?)["']/;
	$::dbpass = $1 if $wikia =~ /\$wgDBpassword\s*=\s*['"](.+?)["']/;
}

# IRC server
$ircserver  = 'irc.organicdesign.co.nz';
$ircport    = 6667;
$ircchannel = '#organicdesign';
$ircpass    = '*****';

# Override default with config file
# TODO: config should come from shared record index
require "$Bin/$::daemon.conf";
$::name   = $name if $name;
$::port   = $port if $port;
$wikiuser = $::name unless $wikiuser;
$ircuser  = $::name unless $ircuser;
$ircuser  = 'bad-name' unless length $ircuser < 10;

# Run as a daemon (see daemonise.pl article for more details and references regarding perl daemons)
open STDIN, '/dev/null';
open STDOUT, ">>$::log";
open STDERR, ">>$::log";
defined ( my $pid = fork ) or die "Can't fork: $!";
exit if $pid;
setsid or die "Can't start a new session: $!";
umask 0;
$0 = "$::daemon ($::name)";

# Install the service into init.d and rc2-5.d if --install arg passed
if ( $ARGV[0] eq '--install' ) {
	writeFile( my $target = "/etc/init.d/$::daemon.sh", "#!/bin/sh\n/usr/bin/perl $::dir/$::daemon.pl\n" );
	symlink $target, "/etc/rc$_.d/S99$::daemon" for 2..5;
	chmod 0755, "/etc/init.d/$::daemon.sh";
	logAdd( "$::daemon.sh added to /etc/init.d" );
}

# Remove the named service and exit
if ( $ARGV[0] eq '--remove' ) {
	unlink "/etc/rc$_.d/S99$::daemon" for 2..5;
	unlink "/etc/init.d/$::daemon.sh";
	logAdd( "$::daemon.sh removed from /etc/init.d" );
	exit(0);
}

# Initialise services, logins and connections
%::streams = ();
serverInitialise();
ircInitialise();
wikiLogin( $wiki, $wikiuser, $wikipass );
$::db = DBI->connect( "DBI:mysql:$::dbname", $::dbuser, $::dbpass );
logAdd( defined $::db ? "Connected '$::dbuser' to DBI:mysql:$::dbname" : "Could not connect '$::dbuser' to '$::dbname': " . DBI->errstr );
print $::ircsock "PRIVMSG $ircchannel :$motd\n";

# Initialise watched files list
# TODO: this list should be drawn from shared record index
my @files = ( '/var/log/auth.log', '/var/log/syslog' );
my %files = ();
for ( @files ) {
	my @stat = stat $_;
	$files{$_} = $stat[7];
}

#---------------------------------------------------------------------------------------------------------#
# MAIN SERVER & CRON LOOP
my $i = 0;
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

}


#---------------------------------------------------------------------------------------------------------#
# GENERAL SUPPORT FUNCTIONS

# Output a comment to the wiki and IRC channel
sub notify {
	my $comment = shift;
	wikiAppend( $wiki, 'Server log', "\n*" . localtime() . " : $comment", "\n$comment" );
	print $::ircsock "PRIVMSG $ircchannel :$comment\n";
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
	return logAdd( "No valid handle to close for stream$stream!" ) unless defined $handle;
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
		$::data   = $title =~ /^(.+?)\?(.+)$/s ? $2 : '';
		$title    = $1 if $::data;
		$::script = $::data =~ /'wgScript'\s*=>\s*\'(.+?)'/   ? $1 : '';
		$::site   = $::data =~ /'wgSitename'\s*=>\s*\'(.+?)'/ ? $1 : '';
		$::event  = "on$title";
		if ( $::script and defined &$::event ) {
			logAdd( "Processing \"$title\" hook from $::site" );
			&$::event;
		} else { logAdd( "Unknown event \"$title\" received!" ) }			

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

	# Log in to an IRC channel
	$::ircsock = IO::Socket::INET->new(
		PeerAddr => $ircserver,
		PeerPort => $ircport,
		Proto    => 'tcp'
	) or die "could not connect to the IRC server ($ircserver:$ircport)";

	print $::ircsock "PASS $ircpass\nNICK $ircuser\nUSER $ircuser 0 0 :$::daemon\n";

	while ( <$::ircsock> ) {

		# if the server asks for a ping
		print $::ircsock "PONG :" . ( split( / :/, $_ ) )[1] if /^PING/;

		# end of MOTD section
		if ( / (376|422) / ) {
			print $::ircsock "NICKSERV :identify $ircuser $ircpass\n";
			last;
		}
	}

	# Wait for a few secs and join the channel
	sleep 3;
	print $::ircsock "JOIN $ircchannel\n";

	$::ircselect = new IO::Select $::ircsock;
}

# Handle streams from select list needing attention
sub ircHandleConnections {
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

						# Respond to known messages
						&doInfo if $text =~ /^($ircuser|$::daemon) info/i;
					}
				}
			}
		}
	}
}

#---------------------------------------------------------------------------------------------------------#
# FILE EVENTS
sub onFileChanged {
	my $file    = shift;
	my $oldsize = shift;
	my $newsize = shift;
	my $text    = '';
	my $msg     = '';
	my @userfilter = ( 'root', 'nobody', 'fit' );

	# Read in difference
	if ( $newsize > $oldsize and open FH, '<', $file ) {
		binmode FH;
		seek FH, $oldsize, 0;
		sysread FH, $text, $newsize - $oldsize;
		close FH;
	}
	
	# User SSH start
	$msg = "$1 shelled in to $::host" if $text =~ /session opened for user (\w+) by/ && !grep $_ eq $1, @userfilter;

	# User SSH stop
	$msg = "$1 shelled out of $::host" if $text =~ /session closed for user (\w+)/ && !grep $_ eq $1, @userfilter;

	# Su to root
	$msg = "$1 is now root on $::host" if $text =~ /Successful su for root by (\w+)/;

	# VPN connection
	$msg = "VPN connection established from $1" if $text =~ /Peer Connection Initiated with ([0-9.]+):/;

	print $::ircsock "PRIVMSG $ircchannel :$msg\n" if $msg;
	logAdd( "$file changed: ($oldsize/$newsize" );

}



#---------------------------------------------------------------------------------------------------------#
# WIKI EVENTS
# $::script, $::site, $::event, $::data available

sub onUserLoginComplete {
	print $::ircsock "PRIVMSG $ircchannel :$1 logged in to $site\n" if $::data =~ /'mName'\s*=>\s*'(.+?)'/s;
}

sub onPrefsPasswordAudit {
	if ( $::data =~ /'mName'\s*=>\s*'(.+?)'.+?\)\),.+?=>\s*'(.+?)'.+success/s ) {
		my( $user, $pass ) = ( $1, $2 );
		doUpdateAccount( $user, $pass );
	}
}

sub onAddNewAccount {
	if ( $::data =~ /'mName'\s*=>\s*'(.+?)'.+'wpPassword'\s*=>\s*'(.+?)'/s ) {
		my( $user, $pass ) = ( $1, $2 );
		doUpdateAccount( $user, $pass );
	}
}

sub onRevisionInsertComplete {
	my $minor   = $::data =~ /'mMinorEdit'\s*=>\s*1/       ? return : '';
	my $id      = $::data =~ /'mId'\s*=>\s*([0-9]+)/       ? $1 : '';
	my $page    = $::data =~ /'mPage'\s*=>\s*([0-9]+)/     ? $1 : '';
	my $user    = $::data =~ /'mUserText'\s*=>\s*'(.+?)'/  ? $1 : '';
	my $parent  = $::data =~ /'mParentId'\s*=>\s*([0-9]+)/ ? $1 : '';
	my $comment = $::data =~ /'mComment'\s*=>\s*'(.+?)'/   ? $1 : '';
	my $title   = $::data =~ /'title'\s*=>\s*'(.+?)'/      ? $1 : '';
	if ( $page and $user ) {
		if ( lc $user ne lc $wikiuser ) {
			my $action = $parent ? 'changed' : 'created';
			my $utitle = $title;
			$title  =~ s/_/ /g;
			$utitle =~ s/ /_/g;
			$comment =~ s/\\("')/$1/g;
			$comment = " ($comment)" if $comment;
			print $::ircsock "PRIVMSG $ircchannel :\"$title\" $action by $user$comment\n";
		}
	} else { logAdd( "Not processing (page='$page', user='$user', title='$title')" ) }
}


#---------------------------------------------------------------------------------------------------------#
# COMMANDS

# Synchronise the unix system passwords and samba passwords with the wiki users and passwords
# - users must be in the wiki group for their passwd to be valid (updatable by this action)
# - the samba passwords are built from the system passwords
sub doUpdateAccount {
	my $user = lc shift;
	my $pass = shift;
	$user =~ s/ /_/g;

	# If unix account exists, change its password
	if ( -d "/home/$user" ) {
		print $::ircsock "PRIVMSG $ircchannel :Updating unix account details for user \"$user\"\n";
		my $exp = Expect->spawn( "passwd $user" );
		$exp->expect( 5,
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); exp_continue; } ],
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); } ],
		);
		$exp->soft_close();
	}

	# Unix account doesn't exist, create now
	else {
		print $::ircsock "PRIVMSG $ircchannel :Creating unix account for user \"$user\"\n";
		my $exp = Expect->spawn( "adduser $user" );
		$exp->expect( 5,
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); exp_continue; } ],
			[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n\n\n\n\n\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/\[\]:/     => sub { my $exp = shift; $exp->send( "\n" ); exp_continue; } ],
			[ qr/correct?/  => sub { my $exp = shift; $exp->send( "Y\n" ); } ],
		);
		$exp->soft_close();
	}

	# Update the samba passwd too
	print $::ircsock "PRIVMSG $ircchannel :Synchronising samba account\n";
	my $exp = Expect->spawn( "smbpasswd -a $user" );
	$exp->expect( 5,
		[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); exp_continue; } ],
		[ qr/password:/ => sub { my $exp = shift; $exp->send( "$pass\n" ); } ],
	);
	$exp->soft_close();

	# Restart samba
	#print $::ircsock "PRIVMSG $ircchannel :Restarting Samba server...\n";
	#$exp = Expect->spawn( "/etc/init.d/samba restart" );
	#$exp->soft_close();
	
	print $::ircsock "PRIVMSG $ircchannel :Done.\n";
}

# Output information about self
sub doInfo {
	print $::ircsock "PRIVMSG $ircchannel :I'm a $::daemon version $::ver listening on port $::port.\n";
}