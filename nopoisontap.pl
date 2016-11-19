#!/usr/bin/perl
# Used to disable networking when screen is locked (see organicdesign.co.nz/PoisonTap_solution
if( $ARGV[0] eq 'start' ) {
	qx( dbus-monitor --session "type=signal,interface=org.gnome.SessionManager.Presence" | $0 & );
} else {
	while( <> ) {
		`nmcli nm enable false` if /uint32 3/;
		`nmcli nm enable true` if /uint32 0/;
	}
}
