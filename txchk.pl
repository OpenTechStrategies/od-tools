#!/usr/bin/perl
#
# A simple script to be called on crontab to notify users by email when they receive bitcoin transactions
#
# It requires a file in the same directory called txchk.conf which has a bitcoin address and email address on each line, e.g.
# 19BcAkFCok8VRM7kktc4kRhKnr5D51NxJd (Organic Design donations)		donations@organicdesign.co.nz
#
# - The friendly name for the bitcoin address is optional
# - The email address is separated from the bitcoin address information by any number of tabs or spaces
#
# Author    : Aran Dunkley (http://www.organicdesign.co.nz/aran)
# License   : GPL (http://www.gnu.org/copyleft/gpl.html)
# Donations : 19BcAkFCok8VRM7kktc4kRhKnr5D51NxJd
#
use HTTP::Request;
use LWP::UserAgent;
use JSON qw( decode_json );
use Cwd qw( realpath );
use Data::Dumper;

# Set up a client for making HTTP requests and don't bother verifying SSL certs
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
$ua = LWP::UserAgent->new();

# Change to the directory the code's in
chdir $1 if realpath($0) =~ m|^(.+)/|;

# Get the current bitcoin price from blockchain.info
$src = $ua->get( "http://blockchain.info/ticker" )->content;
$btc = $src =~ /USD.+?15m.+?([0-9.]{3,})/ ? $1 : 'ERROR';

# Load the last historical data containing the last txid for each address
%hist = ();
if(-e "txchk.hist") {
	open FH, '<', "txchk.hist";
	while(<FH>) { $hist{$1} = $2 if /^(.+) (\S+)$/ }
	close FH;
}

# Loop through each line in the config
$changed = 0;
open FH, '<', "txchk.conf";
while(<FH>) {

	# If the line has a bitcoin and email address,
	if( /^\s*(.+)\s+(\S+)\s*$/ ) {

		# Get the info from the config line
		($addr,$email) = ($1,$2);

		# get all transactions to this address that have occurred since the last recorded one
		$raw = $addr =~ /^(\w+)/ ? $1 : $addr;
		@txs = get_tx_list( $raw, $hist{$raw} );

		# Don't do anything if there's no transactions in the list
		if( $#txs >= 0 ) {

			# Update the last txid if its different and mark history as changed
			$changed = 1 if $hist{$raw} ne $txs[0];
			$hist{$raw} = $txs[0];

			# Loop through all the transactions by txid
			for my $txid ( @txs ) {

				# Get the amount sent to our address in this transaction
				$tx = get_tx_info( $raw, $txid );
				$txd = dollar( $tx * $btc );
				$tx =~ s/(\d{8})\d+/$1/;		

				# Compose a message about this transaction
				$msg = "You received $tx BTC (\$$txd) to address $addr\n\nThe transaction ID is $txid\n\nThe current bitcoin price is \$" . dollar($btc) . " USD";

				# Send the message to the listed email address
				$tmp = "/tmp/mail.txt";
				open MSG,'>', $tmp;
				print MSG $msg;
				close MSG;
				$email =~ s/@/\\@/;
				qx( mail -s "You received $tx BTC" $email < $tmp );
				qx( rm -f $tmp );
			}
		}
	}
}
close FH;

# Update the historical data if any's changed
if($changed) {
	open FH, '>', "txchk.hist";
	print FH "$_ $hist{$_}\n" for keys %hist;
	close FH;
}

# Sub to format numbers as 2dp with commas
sub dollar {
	my $x = (shift) + 0.0001;
	$x =~ s/^(.+?\...).+/$1/;
	$x =~ s/(\d)(?=\d\d\d\.)/$1,/;
	$x =~ s/(\d)(?=\d\d\d,)/$1,/;
	return $x;
}

# Get the amount received by the passed address in the passed txid
sub get_tx_info {
	my $addr = shift;
	my $txid = shift;
	my $amt = 0;
	my $info = decode_json( $ua->get( "https://blockchain.info/rawtx/$txid" )->content );
	for( @{$info->{'out'}} ) { $amt = $_->{value}/100000000 if $_->{addr} eq $addr };
	return $amt;
}

# Get all transactions sent to the passed address since the passed txid
sub get_tx_list {
	my $addr = shift;
	my $txid = shift;
	my $stop = 0;
	my @txs = ();
	my $info = decode_json( $ua->get( "https://blockchain.info/rawaddr/$addr" )->content );
	for( @{$info->{'txs'}} ) {
		$stop = 1 if $_->{hash} eq $txid;
		push @txs, $_->{hash} unless $stop;
	}
	return @txs;
}
