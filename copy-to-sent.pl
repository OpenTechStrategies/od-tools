#!/usr/bin/perl
#
# This script copies outgoing emails into the "Sent" maildir so that the client doesn't have to do it.
#
# The script is called by the accompanying "exim-copy-to-sent" script which is an Exim4 "system filter"
#
# See the following URL for details:
# https://www.organicdesign.co.nz/Configure_mail_server#Copying_emails_into_the_Sent_folder
#
#
# Copyright (C) 2013-2015 Aran Dunkley
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

# Get the neccesary info about the sent message
$sender = $ENV{SENDER};
$id = $ENV{MESSAGE_ID};
@recipients = $ARGV[0] =~ /([0-9a-z_.&-]+@[0-9a-z_.&-]+)/gi;

# Start logging if the file exists or output to /dev/null otherwise
$log = '/var/www/copy-to-sent.log';
open LOG, '>>', -e $log ? $log : '/dev/null';
print LOG $content . "ID: $id\n";
print LOG $content . "\nSender: $sender\n";
print LOG 'Recipients: ' . $ARGV[0] . "\n";

# Local users are in virtual.users in our configuration
$file = "/etc/exim4/virtual.users";
if( open FH, '<', $file ) {
	sysread FH, $users, -s $file;
	close FH;

	# Find the local user from the sender address
	if( $users =~ /^$sender\s*:\s*(.+?)\@localhost\s*$/m ) {
		$user = $1;

		# Filter the users who use web-mail and have it copy to sent for them
		if( $user ne 'beth' ) {

			# Scan the new messages in their Sent folder
			for my $msg (glob "/home/$user/Maildir/.Sent/new/*") {
				if( open FMSG,'<', $msg ) {
					
					# Read the message header
					sysread FMSG, $content, 1000;
					close FMSG;
					print LOG "Header:\n$content\n\n";

					# Check if its ours by ID
					if( $content =~ /id\s$id/s ) {
						print LOG "ID matches\n";

						# Extract the addresses from the To header
						$to = $content =~ /^\s*To:\s*(.+?)\s+(\w+: )/mis ? $1 : '';
						@to = $to =~ /([0-9a-z_.&-]+@[0-9a-z_.&-]+)/gi;
						%to = map { $_ => 1 } @to;
						print LOG 'To: ' . ( join ', ', keys %to ) . "\n";

						# Extract the addresses from the Cc header
						$cc = $content =~ /^\s*CC:\s*(.+?)\s+(\w+: )/mis ? $1 : '';
						@cc = $cc =~ /([0-9a-z_.&-]+@[0-9a-z_.&-]+)/gi;
						%cc = map { $_ => 1 } @cc;
						print LOG 'Cc: ' . ( join ', ', keys %cc ) . "\n";

						# Build a Bcc header from all the recipients not in the To or Cc headers
						@bcc = ();
						for(@recipients) { push @bcc, $_ unless exists $to{$_} or exists $cc{$_} }
						$bcc = $#bcc < 0 ? 0 : 'Bcc: ' . join(', ', @bcc);
						print LOG 'Bcc: ' . ( join ', ', @bcc ) . "\n";
						
						# Get the whole message
						open FMSG, '<', $msg;
						sysread FMSG, $content, -s $msg;
						close FMSG;

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
}
close LOG;

