#!/usr/bin/perl
# http://www.perlmonks.org/?node_id=8991
my $lineending = "\n";
my $type = shift @ARGV;
if( $type =~ /unix/ )   { $lineending = "\012" }
elsif( $type =~ /dos/ ) { $lineending = "\015\012" }
elsif( $type =~ /mac/ ) { $lineending = "\015" }
else {
	print "Usage: $0 --unix|--dos|--mac\n";
	exit 1;
}
for my $file ( @ARGV ) {
	open FILE, $file or next;
	my @lines = <FILE>;
	close FILE;
	$lines[$_] =~ s/(\012|\015\012?)/$lineending/g for 0 .. $#lines;
	open FILE,">$file";
	print FILE @lines;
	close FILE;
}
