#!/usr/bin/perl
#
# Block IP addresses without host name that tried and connect more than ten times recently
#
%ip = ();
for( split /^/, `tail -n 500 /var/log/exim4/mainlog|grep "no host name found for IP address"` ) {
	$ip{$1}++ if /(\d+\.\d+\.\d+\.\d+)/;
}
for( keys %ip ) {
	if( $ip{$_} > 10 ) {
		qx( iptables -D INPUT -s $_ -p tcp --destination-port 25 -j DROP 2> /dev/null );
		qx( iptables -A INPUT -s $_ -p tcp --destination-port 25 -j DROP );
	}
}
