#!/usr/bin/perl
use Cwd qw(realpath);
chdir $1 if realpath( $0 ) =~ m|^(.+)/|;

sub dollar {
	my $x = (shift) + 0.0001;
	$x =~ s/^(.+?\...).+/$1/;
	return $x;
}

# Get the current bitcoin price
$src = qx( wget -qO- http://blockchain.info/ticker );
$btc = $src =~ /USD.+?15m.+?([0-9.]{3,})/ ? $1 : 'ERROR';

# Load the last balance data
%hist = ();
if(-e "txchk.hist") {
	open FH, '<', "txchk.hist";
	while(<FH>) {
		/^\s*(.+)\s+(.+)\s*$/;
		$hist{$1} = $2;
	}
	close FH;
}

# Loop through each address in the config
$changed = 0;
open FH, '<', "txchk.conf";
while(<FH>) {
	
	/^\s*(.+)\s+(.+)\s*$/;
	($addr,$email) = ($1,$2);

	# Get the current balance of the address
	$bal = qx( wget -qO- https://blockchain.info/q/addressbalance/$addr );
	$bal =~ s/^([1-9])/$1./;

	# If it's more than the last amount, compose a message
	if( $bal > $hist{$addr} ) {
		$changed = 1;

		# Get the transaction amount
		$tx = $bal - $hist{$addr};
		$hist{$addr} = $bal;
		$txd = dollar( $tx * $btc );

		# Compose the message
		print "You received $tx BTC (\$$txd) to address $addr\n";

		# Mail the info
		$tmp = "/tmp/mail.txt";
		open MSG,'>', $tmp;
		print MSG $msg;
		close MSG;
		$email =~ s/@/\\@/;
		#qx( mail -s "Transaction received" $email < $tmp );
		qx( rm -f $tmp );
	}
}
close FH;

# Update the historical data if any's changed
if($changed) {
	open FH, '>', "txchk.hist";
	print FH "$_ " . $hist{$_} . "\n" for keys %hist;
	close FH;
}
