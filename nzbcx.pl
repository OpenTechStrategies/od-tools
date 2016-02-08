#!/usr/bin/perl
use POSIX qw(strftime setsid);
use HTTP::Request;
use LWP::UserAgent;
$date = strftime( '%a%Y%m%d', localtime );

# Percentage over ticker price we want to know about
$margin = $ARGV[0];

# Minimum volume we want to know about
$minimum = $ARGV[1];

# Set up a client for making HTTP requests and don't bother verifying SSL certs
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
$ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; it; rv:1.8.1.14)' );

# Send an email
sub email {
	$to = shift;
	$subject = shift;
	$body = shift;
	$tmp = "/tmp/mail.txt";
	open FH,'>', $tmp;
	print FH $body;
	close FH;
	qx( mail -s "$subject" "$to" < $tmp );
	qx( rm -f $tmp );
}

# Return passed number formatted as dollars
sub dollar {
	my $x = (shift) + 0.0001;
	$x =~ s/^(.+?\...).+/$1/;
	$x =~ s/(\d)(?=\d\d\d\.)/$1,/;
	$x =~ s/(\d)(?=\d\d\d,)/$1,/;
	return "\$$x";
}

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
