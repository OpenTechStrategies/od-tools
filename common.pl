#!/usr/bin/perl
#
# Common variables and subroutines needed by OD scripts
#
use POSIX qw(strftime setsid);
use HTTP::Request;
use LWP::UserAgent;
use Time::HiRes;
use Digest::MD5 qw( md5_base64 );
use JSON qw( decode_json );

$date = strftime( '%a%Y%m%d', localtime );

# Make a tmp string for filenames
$tmp = md5_base64( Time::HiRes::time . rand() );
$tmp =~ s/\W//g;
$tmp = substr( $tmp, 1, 5 );

# Set up a client for making HTTP requests and don't bother verifying SSL certs
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
$ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; it; rv:1.8.1.14)' );

# Output a comment to be appended to the email
$::out = '';
sub comment {
	my $comment = join '', @_;
	$::out .= "$comment\n";
}

# Return size of passed file in MB
sub size { return (int([stat shift]->[7]/104857.6+0.5)/10).'MB'; }

# Send an email
sub email {
	my $to = shift;
	my $subject = shift;
	my $body = shift;
	my $mailTmp = "/tmp/mail-$tmp.txt";
	open FH,'>', $mailTmp;
	print FH $body;
	close FH;
	qx( mail -s "$subject" "$to" < $mailTmp );
	qx( rm -f $mailTmp );
}

# Return passed number formatted as dollars
sub dollar {
	my $x = (shift) + 0.0001;
	$x =~ s/^(.+?\...).+/$1/;
	$x =~ s/(\d)(?=\d\d\d\.)/$1,/;
	$x =~ s/(\d)(?=\d\d\d,)/$1,/;
	return "\$$x";
}

# Return content of passed file
sub readFile {
	my $file = shift;
	if ( open FH, '<', $file ) {
		binmode FH;
		sysread FH, ( my $out ), -s $file;
		close FH;
		return $out;
	}
}

1;
