=head1 NAME

 iMSCP::Installer::Layout - Layout installation variables

 Based on GNU coding standards. See:
  https://www.gnu.org/prep/standards/html_node/DESTDIR.html
  https://www.gnu.org/prep/standards/html_node/Directory-Variables.html

=cut

package iMSCP::Installer::Layout;

use strict;
use warnings;
use vars qw/
    $DESTDIR $prefix $exec_prefix $bindir $sbindir $datarootdir $datadir
    $sysconfdir $localstatedir $runstatedir $libdir
/;

$DESTDIR = '';
$prefix = '/usr/local';
$exec_prefix = '@prefix@';
$bindir = '@prefix@/bin';
$sbindir = '@prefix@/sbin';
$datarootdir = '@prefix@/share';
$datadir = '@datarootdir@';
$sysconfdir = '@prefix@/etc';
$localstatedir = '@prefix@/var';
$runstatedir = '@localstatedir@/run';
$libdir = '@exec_prefix@/lib';

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
