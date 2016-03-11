#!/usr/bin/perl
#
# Renews a list of Let's Encrypt domains specified in passed or default file
# Format of the list in the file is one per line, comments start line with "#"
#   domain-tld : @, www, sub-domain2, sub-domain3....
# Use optional "@" for naked domain
#
use File::Basename;
use Cwd qw(realpath);

# Get the conf file (defaults to letsencrypt-domains in same dir if no paramater supplied)
$conf = $ARGV[0];
$conf = realpath( dirname( __FILE__ ) ) . "/letsencrypt-domains" unless $conf;

# Read the domains file and format into -d params for the letsencrypt command
@domains = ();
open DOMAINS, '<', $conf or die "Couldn't read domains list!";
while(<DOMAINS>) {
	if( /^(.+?)\s*:\s*(.+?)\s*$/ ) {
		push @domains, '-d ' . ($_ eq '@' ? $1 : "$_.$1") for split /\s*,\s*/, $2;
	}
}
$domains = join ' ', @domains;

# Run the letsencrypt renewal command
$cmd = "letsencrypt-auto certonly --keep-until-expiring --expand --webroot -w /var/www/domains/letsencrypt $domains";
if( $ARGV[0] eq '--print' ) { print "\m\n$cmd\n" }
else { qx( $cmd ) }
