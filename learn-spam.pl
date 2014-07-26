#!/usr/bin/perl

# Handle false positives
for (glob "/home/*/Maildir/.INBOX.Not\\ Spam/[cn]??") {
	s/ /\\ /;
	print "$_: " . ( qx "sa-learn --ham $_" );
	qx "rm -fr $_/*";
}

# Handle false negatives
for (glob "/home/*/Maildir/.INBOX.Spam/[cn]??") {
	s/ /\\ /;
	print "$_: " . ( qx "sa-learn --spam $_" );
	qx "rm -fr $_/*";
}
