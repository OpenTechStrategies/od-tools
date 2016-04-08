#!/usr/bin/perl
#
# A simple script to be called on crontab to notify users by email when they receive bitcoin transactions
#
# It requires a file in the same directory called txchk.conf which has a bitcoin address and email address
# on each line, for exmaple:
# 18D9441cFFwRnoeTfezwSrZYbGKwGGymzh (Organic Design donations)		donations@organicdesign.co.nz
#
# NOTES:
# - The friendly name for the bitcoin address is optional
# - The email address is separated from the bitcoin address information by any number of tabs or spaces
# - The 'mail' command must be functional
# - Depends on libwww-perl and libjson-perl
#
# Author    : Aran Dunkley (http://www.organicdesign.co.nz/aran)
# License   : GPL (http://www.gnu.org/copyleft/gpl.html)
# Donations : 18D9441cFFwRnoeTfezwSrZYbGKwGGymzh
#
use JSON qw( decode_json );
use Cwd qw( realpath );
require '/var/www/tools/common.pl';

# Change to the directory the code's in
chdir $1 if realpath($0) =~ m|^(.+)/|;

# Use the supplied conf file or default to ./txchk.conf
$conf = "txchk.conf";
$conf = $ARGV[0] if $ARGV[0];

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
open FH, '<', $conf;
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
				$msg = "You received $tx BTC ($txd) to address $addr\n\n";
				$msg .= "The transaction ID is $txid\n\n";
				$msg .= "The current bitcoin price is " . dollar($btc) . " USD";

				# Send the message to the listed email address
				email( $email, "You received $tx BTC", $msg );
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

# Get the amount received by the passed address in the passed txid
sub get_tx_info {
	my $addr = shift;
	my $txid = shift;
	my $amt = 0;
	my $info = get_json( "https://blockchain.info/rawtx/$txid" );
	for( @{$info->{'out'}} ) { $amt = $_->{value}/100000000 if $_->{addr} eq $addr };
	return $amt;
}

# Get all transactions sent to the passed address (that are not change being sent back from the same address) since the passed txid
sub get_tx_list {
	my $addr = shift;
	my $txid = shift;
	my $stop = 0;
	my @txs = ();
	my $info = get_json( "https://blockchain.info/rawaddr/$addr?limit=10" );
	for( @{$info->{'txs'}} ) {
		$stop = 1 if $_->{hash} eq $txid;
		push @txs, $_->{hash} unless $stop or $_->{inputs}->[0]->{prev_out}->{addr} eq $addr;
	}
	return @txs;
}

# Get JSON data from passed URL retrying after a delay if invalid data returned and silently exiting if still unavailable
sub get_json {
	my $url = shift;
	for( 1 .. 2 ) {
		my $json = $ua->get( $url )->content;
		return decode_json( $json ) if $json =~ /^\{/;
		sleep 2;
	}
	exit;
}
