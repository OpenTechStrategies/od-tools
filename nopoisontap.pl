#!/usr/bin/perl
# Used to disable networking when screen is locked (see organicdesign.co.nz/PoisonTap_solution
if( $ARGV[0] eq 'start' ) {
	system( "dbus-monitor --session \"type=signal,interface=org.gnome.SessionManager.Presence,member=StatusChanged\" | $0 &" );
} else {
	while( <> ) {
		`nmcli nm enable false` if /uint32 3/;
		`nmcli nm enable true` if /uint32 0/;
	}
}
