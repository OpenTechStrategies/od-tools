#!/usr/bin/perl
$sender = $ENV{SENDER};
$id = $ENV{MESSAGE_ID};
@recipients = $ARGV[0] =~ /([0-9a-z_.&-]+@[0-9a-z_.&-]+)/gi;
$file = "/etc/exim4/virtual.users";
if( open FH,'<', $file ) {
	sysread FH, $users, -s $file;
	close FH;

	# Find the local user from the sender address
	if( $users =~ /^$sender\s*:\s*(.+?)\@localhost\s*$/m ) {
		$user = $1;

		# Scan the new messages in their Sent folder
		for my $msg (glob "/home/$user/Maildir/.Sent/new/*") {
			print FH "$msg\n";
			if( open FMSG,'<', $msg ) {
				
				# Read the message header
				sysread FMSG, $content, 600;
				close FMSG;

				# Check if its ours by ID
				if( $content =~ /\s$id\s/s ) {

					# Get the whole message
					open FMSG,'<', $msg;
					sysread FMSG, $content, -s $msg;
					close FMSG;

					# Turn the To and CC headers into lists and then hashes
					$to = $content =~ /^\s*To:\s*(.+?)\s+(\w: )/mis ? $1 : '';
					@to = $to =~ /([0-9a-z_.&-]+@[0-9a-z_.&-]+)/gi;
					%to = map { $_ => 1 } @to;
					$cc = $content =~ /^\s*CC:\s*(.+?)\s+(\w: )/mis ? $1 : '';
					@cc = $cc =~ /([0-9a-z_.&-]+@[0-9a-z_.&-]+)/gi;
					%cc = map { $_ => 1 } @cc;

					# Build a Bcc header from all the recipients not in the To or Cc headers
					@bcc = ();
					for(@recipients) {
						push @bcc, $_ unless exists $to{$_} or exists $cc{$_};
					}
					$bcc = $#bcc < 0 ? 0 : 'Bcc: ' . join(', ', @bcc);
					
					# Add the Bcc header after the To header
					$content =~ s/(^\s*To:.+?$)/$1\n$bcc/mi if $bcc;

					# Write the new content to the file
					if(open FMSG,'>', $msg) {
						syswrite FMSG, $content;
						close FMSG;
					}

					# Mark as read
					rename $msg, "$msg:2,S";
				}
			}
		}
	}
}


