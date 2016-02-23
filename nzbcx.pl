#!/usr/bin/perl
require '/var/www/tools/common.pl';

# Percentage over ticker price we want to know about
$margin = $ARGV[0];

# Minimum volume we want to know about
$minimum = $ARGV[1];

# Get the btc ticker NZD price
$src = $ua->get( "http://blockchain.info/ticker" )->content;
$btc = $src =~ /NZD.+?15m.+?([0-9.]{3,})/ ? $1 : 'ERROR';

# Get the NZBCX orders page, filter to ask rows, extract price => vol pairs
$src = $ua->get( "https://nzbcx.com/orderbook/BTCNZD" )->content;
$src =~ s/^.+?id\s*=\s*"live_asks".+?<tbody.*?>\s*(.+?)\s*<\/tbody>.+$/$1/s;
%asks = $src =~ />([0-9.]+)<.+?>([0-9.]+)</sg;

# Add up any volume that is within 25% of the ticker price
$out = '';
$some = 0;
for my $price ( keys %asks ) {
	if( $price < $btc * (1 + $margin / 100) ) {
		$volume = substr( $asks{$price}, 0, 5);
		$out .= "$volume @ " . dollar( $price ) . "\n";
		$some += $volume;
	}
}

# Send the info
if( $some >= $minimum ) {
	$out = "The BTC ticker price is NZD " . dollar( $btc ) . ".\nThere are $some BTC available within $margin\% of this price:\n$out";
	email( "aran\@organicdesign.co.nz", 'Some BTC available on NZBCX', $out );
}
