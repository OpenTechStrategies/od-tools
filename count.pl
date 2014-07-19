#!/usr/bin/perl
#
# Usage: count.pl PATH LIMIT
#
# List the directories in PATH that contain more than LIMIT items
#
use File::Find;
sub count {
        return unless -d $_;
        $n = `ls "$_"|wc -l`;
        $d = `pwd`;
        chomp $d;
        print "$d/$_: $n" if $n > $ARGV[1];
}
find(\&count, $ARGV[0]);
