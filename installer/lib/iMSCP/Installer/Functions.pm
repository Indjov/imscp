=head1 NAME

 iMSCP::Installer::Functions - Functions for the i-MSCP installer

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright 2010-2017 by internet Multi Server Control Panel
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Installer::Functions;

use strict;
use warnings;
use autouse 'iMSCP::Stepper' => qw/ step /;
use Cwd;
use File::Basename;
use File::Find;
use File::Spec;
use iMSCP::Bootstrapper;
use iMSCP::Config;
use iMSCP::Debug;
use iMSCP::Dialog;
use iMSCP::Dir;
use iMSCP::EventManager;
use iMSCP::Execute;
use iMSCP::File;
use iMSCP::Getopt;
use iMSCP::Installer::Layout;
use iMSCP::LsbRelease;
use iMSCP::Rights;
use parent 'Exporter';

our @EXPORT_OK = qw/ Init Build Install /;

my $installerAdapterInstance;

=head1 DESCRIPTION

 Common functions for the i-MSCP installer

=head1 PUBLIC FUNCTIONS

=over 4

=item Init()

 Initialize installer

 - Install pre-required packages
 - Load layout file
 - Load config
 - Show welcome message if needed
 - Confirm distribution
 - Show warning message
 - Set runtime configuration parameters
 - Initialize event manager instance

 Return 0 on success, other on failure

=cut

sub Init
{
    my $rs = 0;
    
    $rs = _installPreRequiredPackages() unless $main::skippackages;
    $rs ||= _loadXmlLayoutFile();
    $rs ||= _loadConfig();
    return $rs if $rs;

    unless (iMSCP::Getopt->noprompt || $main::reconfigure ne 'none') {
        my $dialog = iMSCP::Dialog->getInstance();
        $rs = _showWelcomeMsg( $dialog ) unless $main::imscpConfig{'DISTRO_ID'};
        $rs ||= _confirmDist( $dialog ) unless $main::imscpConfig{'DISTRO_ID'};
        $rs ||= _showWarningMsg( $dialog );
        return $rs if $rs;
    }

    # Set distribution variables
    $main::imscpConfig{'DISTRO_ID'} = lc( iMSCP::LsbRelease->getInstance()->getId( 'short' ) );
    $main::imscpConfig{'DISTRO_CODENAME'} = lc( iMSCP::LsbRelease->getInstance()->getCodename( 'short' ) );
    $main::imscpConfig{'DISTRO_RELEASE'} = iMSCP::LsbRelease->getInstance()->getRelease( 'short', 'force_numeric' );

    $rs;
}

=item Build()

 Process build tasks

 Return int 0 on success, other on failure

=cut

sub Build
{
    newDebug( 'imscp-build.log' );

    if (!iMSCP::Getopt->preseed
        && grep(!$main::imscpConfig{"${_}_SERVER"}, qw/ HTTPD PO MTA FTPD NAMED SQL PHP /)
    ) {
        iMSCP::Getopt->noprompt( 0 );
        $main::skippackages = 0;
    }

    my $dialog = iMSCP::Dialog->getInstance();
    my $rs = _askInstallerMode( $dialog ) unless iMSCP::Getopt->noprompt || $main::buildonly || $main::reconfigure ne 'none';

    my @steps = (
        [ \&_checkRequirements, 'Checking for requirements' ],
        [ \&_buildDistFiles, 'Building distribution files' ],
        #[ \&_savePersistentData, 'Saving persistent data' ],
        #[ \&_cleanup, 'Processing cleanup tasks' ]
    );

    unshift @steps, [ \&_installDistPackages, 'Installing distribution packages' ] unless $main::skippackages;

    $rs ||= iMSCP::EventManager->getInstance()->trigger( 'preBuild', \@steps );
    $rs ||= getDistInstallerAdapter()->preBuild( \@steps );
    return $rs if $rs;

    my ($step, $nbSteps) = (1, scalar @steps);
    for (@steps) {
        $rs = step( @{$_}, $nbSteps, $step );
        error( 'An error occurred while performing build steps' ) if $rs && $rs != 50;
        return $rs if $rs;
        $step++;
    }

    iMSCP::Dialog->getInstance()->endGauge();

    $rs = iMSCP::EventManager->getInstance()->trigger( 'postBuild' );
    $rs ||= getDistInstallerAdapter()->postBuild();
    return $rs if $rs;

    undef $installerAdapterInstance;

    # Clean build directory (remove any .gitignore|empty-file)
    find(
        sub {
            return unless $_ eq '.gitignore' || $_ eq 'empty-file';
            unlink or fatal( sprintf( 'Could not remove %s file: %s', $File::Find::name, $! ) );
        },
        $iMSCP::Installer::Layout::DESTDIR
    ) unless grep($iMSCP::Installer::Layout::DESTDIR eq $_, ('', '/'));

    $rs = iMSCP::EventManager->getInstance()->trigger( 'afterPostBuild' );
    return $rs if $rs;

    my %confmap = (
        imscp    => \ %main::imscpConfig,
        imscpOld => \ %main::imscpOldConfig
    );

    # Write configuration
    my $destDir = File::Spec->catdir($iMSCP::Installer::Layout::DESTDIR, $iMSCP::Installer::Layout::sysconfdir);
    while( my ($name, $config) = each( %confmap ) ) {
        tie my %config, 'iMSCP::Config', fileName => "$destDir/imscp/$name.conf";
        @config{ keys %{$config} } = values %{$config};
        untie %config;
    }

    endDebug();
}

=item Install()

 Process install tasks

 Return int 0 on success, other otherwise

=cut

sub Install
{
    newDebug( 'imscp-setup.log' );

    {
        package main;
        require "$FindBin::Bin/engine/setup/imscp-setup-methods.pl";
    }

    # Not really the right place to do that job but we have not really
    # choice because this must be done before installation of new files
    my $serviceMngr = iMSCP::Service->getInstance();
    if ($serviceMngr->hasService( 'imscp_network' )) {
        $serviceMngr->remove( 'imscp_network' );
    }

    my $bootstrapper = iMSCP::Bootstrapper->getInstance();
    my @runningJobs = ();

    for ('imscp-backup-all', 'imscp-backup-imscp', 'imscp-dsk-quota', 'imscp-srv-traff', 'imscp-vrl-traff',
        'awstats_updateall.pl', 'imscp-disable-accounts', 'imscp'
    ) {
        next if $bootstrapper->lock( "/tmp/$_.lock", 'nowait' );
        push @runningJobs, $_,
    }

    if (@runningJobs) {
        iMSCP::Dialog->getInstance()->msgbox( <<"EOF" );

There are i-MSCP jobs currently running on your system.

You must wait until the end of these jobs.

Running jobs are: @runningJobs
EOF
        return 1;
    }

    undef @runningJobs;

    my @steps = (
        [ \&main::setupInstallFiles, 'Installing distribution files' ],
        [ \&main::setupSystemDirectories, 'Setting up system directories' ],
        [ \&main::setupBoot, 'Bootstrapping installer' ],
        [ \&main::setServerCapabilities, 'Setting up server capabilities' ],
        [ \&main::setupRegisterListeners, 'Registering servers/packages event listeners' ],
        [ \&main::setupDialog, 'Processing setup dialog' ],
        [ \&main::setupTasks, 'Processing setup tasks' ],
        [ \&main::setupDeleteBuildDir, 'Deleting build directory' ]
    );

    my $rs = iMSCP::EventManager->getInstance()->trigger( 'preInstall', \@steps );
    $rs ||= getDistInstallerAdapter()->preInstall( \@steps );
    return $rs if $rs;

    my $step = 1;
    my $nbSteps = scalar @steps;
    for (@steps) {
        $rs = step( @{$_}, $nbSteps, $step );
        error( 'An error occurred while performing installation steps' ) if $rs;
        return $rs if $rs;
        $step++;
    }

    iMSCP::Dialog->getInstance()->endGauge();

    $rs = iMSCP::EventManager->getInstance()->trigger( 'postInstall' );
    $rs ||= getDistInstallerAdapter()->postInstall();
    return $rs if $rs;

    require Net::LibIDN;
    Net::LibIDN->import( 'idn_to_unicode' );

    my $port = $main::imscpConfig{'BASE_SERVER_VHOST_PREFIX'} eq 'http://'
        ? $main::imscpConfig{'BASE_SERVER_VHOST_HTTP_PORT'}
        : $main::imscpConfig{'BASE_SERVER_VHOST_HTTPS_PORT'};
    my $vhost = idn_to_unicode( $main::imscpConfig{'BASE_SERVER_VHOST'}, 'utf-8' );

    iMSCP::Dialog->getInstance()->infobox( <<"EOF" );

\\Z1Congratulations\\Zn

i-MSCP has been successfully installed/updated.

Please connect to $main::imscpConfig{'BASE_SERVER_VHOST_PREFIX'}$vhost:$port and login with your administrator account.

Thank you for choosing i-MSCP.
EOF

    endDebug();
}

=back

=head1 PRIVATE FUNCTIONS

=over 4

=item _installPreRequiredPackages()

 Trigger pre-required package installation tasks

 Return int 0 on success, other otherwise

=cut

sub _installPreRequiredPackages
{
    getDistInstallerAdapter()->installPreRequiredPackages();
}

=item _showWelcomeMsg(\%dialog)

 Show welcome message (only for fresh installation)

 Param iMSCP::Dialog \%dialog
 Return int 0 on success, other otherwise

=cut

sub _showWelcomeMsg
{
    my $dialog = shift;

    $dialog->msgbox( <<"EOF" );

\\Zb\\Z4i-MSCP - internet Multi Server Control Panel
============================================\\Zn\\ZB

Welcome to the i-MSCP setup dialog.

i-MSCP (internet Multi Server Control Panel) is an open-source software which allows to manage shared hosting environments on Linux servers.

i-MSCP aims to provide an easy-to-use Web interface for end-users, and to manage servers without any manual intervention on the filesystem.

i-MSCP was designed for professional Hosting Service Providers (HSPs), Internet Service Providers (ISPs) and IT professionals.

\\Zb\\Z4License\\Zn\\ZB

Unless otherwise stated all code is licensed under GPL 2.0 and has the following copyright:

        \\ZbCopyright 2010-2017 by i-MSCP Team - All rights reserved\\ZB

\\Zb\\Z4Credits\\Zn\\ZB

i-MSCP is a project of i-MSCP | internet Multi Server Control Panel.
i-MSCP and the i-MSCP logo are trademarks of the i-MSCP | internet Multi Server Control Panel project team.
EOF
}

=item _showWarningMsg(\%dialog)

 Show warning message

 Return 0 on success, other on failure or when user is aborting

=cut

sub _showWarningMsg
{
    my $dialog = shift;

    my $warning = '';
    if ($main::imscpConfig{'Version'} !~ /git/i) {
        $warning = <<"EOF";

Before continue, be sure to have read the errata file:

    \\Zbhttps://github.com/i-MSCP/imscp/blob/1.4.x/docs/1.4.x_errata.md\\ZB
EOF

    } else {
        $warning = <<"EOF";

The installer detected that you intends to install i-MSCP \\ZbGit\\ZB version.

We would remind you that the Git version can be highly unstable and that the i-MSCP team do not provides any support for it.

Before continue, be sure to have read the errata file:

    \\Zbhttps://github.com/i-MSCP/imscp/blob/1.4.x/docs/1.4.x_errata.md\\ZB
EOF
    }

    return 0 if $warning eq '';

    $dialog->set( 'yes-label', 'Continue' );
    $dialog->set( 'no-label', 'Abort' );
    return 50 if $dialog->yesno( <<"EOF", 'abort_by_default' );

\\Zb\\Z1WARNING - PLEASE READ CAREFULLY\\Zn\\ZB
$warning
You can now either continue or abort.
EOF

    $dialog->resetLabels();
    0;
}

=item _confirmDist(\%dialog)

 Distribution confirmation dialog (only for fresh installation)

 Param iMSCP::Dialog \%dialog
 Return 0 on success, other on failure on when user is aborting

=cut

sub _confirmDist
{
    my $dialog = shift;

    $dialog->infobox( "\nDetecting target distribution..." );

    my $lsbRelease = iMSCP::LsbRelease->getInstance();
    my $distID = $lsbRelease->getId( 'short' );
    my $distCodename = ucfirst($lsbRelease->getCodename( 'short' ));
    my $distRelease = $lsbRelease->getRelease( 'short' );

    if ($distID ne 'n/a' && $distCodename ne 'n/a' && $distID =~ /^(?:debian|ubuntu)$/i) {
        unless (-f "$FindBin::Bin/installer/Packages/".lc($distID).'-'.lc($distCodename).'.xml') {
            $dialog->msgbox( <<"EOF" );

\\Z1$distID $distCodename ($distRelease) not supported yet\\Zn

We are sorry but your $distID version is not supported.

Thanks for choosing i-MSCP.
EOF

            return 50;
        }

        my $rs = $dialog->yesno( <<"EOF" );

$distID $distCodename ($distRelease) has been detected. Is this ok?
EOF

        $dialog->msgbox( <<"EOF" ) if $rs;

\\Z1Distribution not supported\\Zn

We are sorry but the installer has failed to detect your distribution.

Only \\ZuDebian-like\\Zn operating systems are supported.

Thanks for choosing i-MSCP.
EOF

        return 50 if $rs;
    } else {
        $dialog->msgbox( <<"EOF" );

\\Z1Distribution not supported\\Zn

We are sorry but your distribution is not supported yet.

Only \\ZuDebian-like\\Zn operating systems are supported.

Thanks for choosing i-MSCP.
EOF

        return 50;
    }

    0;
}

=item _loadConfig()

 Load config

 Return int 0 on success, other on failure

=cut

sub _loadConfig
{
    my $lsbRelease = iMSCP::LsbRelease->getInstance();
    my $defaultDistConfFile = "$FindBin::Bin/config/debian/imscp.conf";
    my $distConfFile = "$FindBin::Bin/config/".lc( $lsbRelease->getId( 1 ) ).'/imscp.conf';
    my $newConfFile = -f $distConfFile ? $distConfFile : $defaultDistConfFile;

    # Load new configuration
    tie %main::imscpConfig, 'iMSCP::Config',
        fileName  => $newConfFile,
        readonly  => 1,
        temporary => 1;

    # Load old configuration
    if (-f "$iMSCP::Installer::Layout::sysconfdir/imscp/imscpOld.conf") {
        # imscpOld.conf file only exists on error
        tie %main::imscpOldConfig, 'iMSCP::Config',
            fileName => "$iMSCP::Installer::Layout::sysconfdir/imscp/imscpOld.conf",
            readonly => 1,
            temporary => 1;
    } elsif (-f "$iMSCP::Installer::Layout::sysconfdir/imscp/imscp.conf") {
        # On update there is one old imscp.conf file
        tie %main::imscpOldConfig, 'iMSCP::Config',
            fileName => "$iMSCP::Installer::Layout::sysconfdir/imscp/imscp.conf",
            readonly => 1,
            temporary => 1;
    } else {
        # On fresh installation there is not old conffile
        %main::imscpOldConfig = %main::imscpConfig;
    }

    if (tied(%main::imscpOldConfig)) {
        # Expand variables in configuration file
        for(keys %main::imscpConfig) {
            my $cval = $main::imscpConfig{$_};
            $main::imscpConfig{$_} = _expandVars($main::imscpConfig{$_});
            $main::imscpOldConfig{$_} = $main::imscpConfig{$_} if exists $main::imscpOldConfig{$_}
                && $cval ne $main::imscpConfig{$_};
        }

        (tied(%main::imscpOldConfig))->{'temporary'} = 0;

        debug('Merging old configuration with new configuration...');
        # Merge old configuration in new configuration, excluding upstream defined values
        while(my ($key, $value) = each(%main::imscpOldConfig)) {
            next if !exists $main::imscpConfig{$key} || $key =~ /^(?:BuildDate|Version|CodeName|THEME_ASSETS_VERSION)$/;
            $main::imscpConfig{$key} = $value;
        }
    }

    0;
}

=item _askInstallerMode(\%dialog)

 Asks for installer mode

 Param iMSCP::Dialog \%dialog
 Return int 0 on success, 50 otherwise

=cut

sub _askInstallerMode
{
    my $dialog = shift;

    $dialog->set( 'cancel-label', 'Abort' );

    my ($rs, $mode) = $dialog->radiolist( <<"EOF", [ 'auto', 'manual' ], 'auto' );

Please choose the installer mode:

See https://wiki.i-mscp.net/doku.php?id=start:installer#installer_modes for a full description of the installer modes.
 
EOF

    $main::buildonly = $mode eq 'manual' ? 1 : 0;
    $dialog->set( 'cancel-label', 'Back' );
    return 50 if $rs;
    0;
}

=item _installDistPackages()

 Trigger packages installation/uninstallation tasks from distro installer adapter

 Return int 0 on success, other on failure

=cut

sub _installDistPackages
{
    my $rs = getDistInstallerAdapter()->installPackages();
    $rs ||= getDistInstallerAdapter()->uninstallPackages();
}

=item _checkRequirements()

 Check for requirements

 Return undef if all requirements are met, throw a fatal error otherwise

=cut

sub _checkRequirements
{
    iMSCP::Requirements->new()->all();
}

=item _buildDistFiles

 Build distribution files

 Return int 0 on success, other on failure

=cut

sub _buildDistFiles
{
    my $rs = _buildConfigFiles();
    $rs ||= _buildEngineFiles();
    $rs ||= _buildFrontendFiles();
    $rs ||= _buildDaemon();
}

=item _loadXmlLayoutFile()

 Load layout.xml file

 Return int 0 on success, other on failure

=cut

sub _loadXmlLayoutFile
{
    unless (-f $main::installlayout) {
        error( sprintf( "File `%s' doesn't exists", $main::installlayout ) );
        return 1;
    }

    my $layout = eval {
        require XML::Simple;
        XML::Simple->new( ForceArray => 0, ForceContent => 0 )->XMLin( $main::installlayout );
    };
    if ($@) {
        error( sprintf("Couldn't load `%s' layout file: %s", $main::installlayout, $@));
        return 1;
    }

    {
        no strict 'refs';

        # Override default layout variables with those from layout.xml file
        while(my ($varname, $value) = each(%{$layout})) {
            unless (defined(${"iMSCP::Installer::Layout::$varname"})) {
                error(sprintf("Found unallowed `%s' layout variable in %s file", $varname, $main::installlayout));
                return 1;
            }

            ${"iMSCP::Installer::Layout::$varname"} = $value;
        }

        # Expand layout variables
        for my $varname (keys %{'iMSCP::Installer::Layout::'}) {
            ${"iMSCP::Installer::Layout::$varname"} = _expandVars(${"iMSCP::Installer::Layout::$varname"});
        }
    }

    unless (grep( $_ eq $iMSCP::Installer::Layout::DESTDIR, ('', '/'))) {
        # Make sure to start with clean $iMSCP::Installer::Layout::DESTDIR
        return iMSCP::Dir->new( dirname => $iMSCP::Installer::Layout::DESTDIR )->remove();
    }

    0;
}

=item _buildConfigFiles()

 Build configuration files

 Return int 0 on success, other on failure

=cut

sub _buildConfigFiles
{
    # Possible config directory paths
    my $defaultDistConfDir = "$FindBin::Bin/config/debian";
    my $distConfDir = "$FindBin::Bin/config/".lc( iMSCP::LsbRelease->getInstance()->getId( 'short' ) );

    # Determine config directory to use
    my $confDir = -d $distConfDir ? $distConfDir : $defaultDistConfDir;

    unless (chdir( $confDir )) {
        error( sprintf( 'Could not change directory to %s: %s', $confDir, $! ) );
        return 1;
    }

    # Determine main makefile.xml file to process
    my $file = -f "$distConfDir/makefile.xml" ? "$distConfDir/makefile.xml" : "$defaultDistConfDir/makefile.xml";

    my $rs = _processXmlMakefile( $file );
    return $rs if $rs;

    # Process each makefile.xml file found in config subdir
    for (iMSCP::Dir->new( dirname => $defaultDistConfDir )->getDirs()) {
        # Override subdir path if it is available in selected distribution config directory, else set it to default path

        $confDir = -d "$distConfDir/$_" ? "$distConfDir/$_" : "$defaultDistConfDir/$_";

        unless (chdir( $confDir )) {
            error( sprintf( 'Could not change directory to %s: %s', $confDir, $! ) );
            return 1;
        }

        $file = -f "$distConfDir/$_/makefile.xml"
            ? "$distConfDir/$_/makefile.xml" : "$defaultDistConfDir/$_/makefile.xml";

        next unless -f $file;

        $rs = _processXmlMakefile( $file );
        return $rs if $rs;
    }

    0;
}

=item _buildEngineFiles()

 Build engine files

 Return int 0 on success, other on failure

=cut

sub _buildEngineFiles
{
    unless (chdir "$FindBin::Bin/backend") {
        error( sprintf( 'Could not change dir to %s', "$FindBin::Bin/backend" ) );
        return 1;
    }

    _processXmlMakefile( "$FindBin::Bin/backend/makefile.xml" );
}

=item _buildFrontendFiles()

 Build frontEnd files

 Return int 0 on success, other on failure

=cut

sub _buildFrontendFiles
{
    my $destDir = File::Spec->catdir(
        $iMSCP::Installer::Layout::DESTDIR, $iMSCP::Installer::Layout::datadir, '/imscp/frontend'
    );

    iMSCP::Dir->new( dirname => "$FindBin::Bin/frontend" )->rcopy($destDir);
}

=item _buildDaemon()

 Build daemon

 Return int 0 on success, other on failure

=cut

sub _buildDaemon
{
    unless (chdir "$FindBin::Bin/daemon") {
        error( sprintf( "Couldn't change dir to %s", "$FindBin::Bin/daemon" ) );
        return 1;
    }

    my $destDir = File::Spec->catdir($iMSCP::Installer::Layout::DESTDIR, $iMSCP::Installer::Layout::sbindir);
    my $rs = execute( [ 'make', 'clean', 'imscp_daemon' ], \ my $stdout, \ my $stderr );
    debug( $stdout ) if $stdout;
    error( $stderr || 'Unknown error' ) if $rs;
    $rs ||= iMSCP::File->new( filename => 'imscp_daemon' )->copyFile($destDir);
    $rs ||= setRights(
        "$destDir/imscp_daemon", {
            user => $main::imscpConfig{'ROOT_USER'},
            group => $main::imscpConfig{'ROOT_GROUP'},
            mode => '0755'
        }
    )
}

=item _savePersistentData()

 Save persistent data

 Return int 0 on success, other on failure

=cut

sub _savePersistentData
{
    my $destdir = $iMSCP::Installer::Layout::DESTDIR;

    # Move old skel directory to new location
    iMSCP::Dir->new( dirname => "$iMSCP::Installer::Layout::sysconfdir/imscp/apache/skel" )->rcopy(
        "$iMSCP::Installer::Layout::sysconfdir/imscp/skel"
    ) if -d "$iMSCP::Installer::Layout::sysconfdir/imscp/apache/skel";

    iMSCP::Dir->new( dirname => "$iMSCP::Installer::Layout::sysconfdir/imscp/skel" )->rcopy(
        "$destdir$iMSCP::Installer::Layout::sysconfdir/imscp/skel"
    ) if -d "$iMSCP::Installer::Layout::sysconfdir/imscp/skel";

    # Move old listener files to new location
    iMSCP::Dir->new( dirname => "$iMSCP::Installer::Layout::sysconfdir/imscp/hooks.d" )->rcopy(
        "$iMSCP::Installer::Layout::sysconfdir/imscp/listeners.d"
    ) if -d "$iMSCP::Installer::Layout::sysconfdir/imscp/hooks.d";

    # Save ISP logos (new location)
    iMSCP::Dir->new( dirname => "$main::imscpConfig{'IMSCP_ROOT_DIR'}/gui/data/ispLogos" )->rcopy(
        "$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent/ispLogos"
    ) if -d "$main::imscpConfig{'ROOT_DIR'}/gui/data/ispLogos";

    # Save GUI logs
    iMSCP::Dir->new( dirname => "$main::imscpConfig{'ROOT_DIR'}/gui/data/logs" )->rcopy(
        "$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/logs"
    ) if -d "$main::imscpConfig{'ROOT_DIR'}/gui/data/logs";

    # Save persistent data
    iMSCP::Dir->new( dirname => "$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent" )->rcopy(
        "$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent"
    ) if -d "$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent";

    # Save software (older path ./gui/data/softwares) to new path (./gui/data/persistent/softwares)
    iMSCP::Dir->new( dirname => "$main::imscpConfig{'ROOT_DIR'}/gui/data/softwares" )->rcopy(
        "$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent/softwares"
    ) if -d "$main::imscpConfig{'ROOT_DIR'}/gui/data/softwares";

    # Save plugins
    iMSCP::Dir->new( dirname => "$main::imscpConfig{'PLUGINS_DIR'}" )->rcopy(
        "$destdir$main::imscpConfig{'PLUGINS_DIR'}"
    ) if -d $main::imscpConfig{'PLUGINS_DIR'};

    # Quick fix for #IP-1340 (Removes old filemanager directory which is no longer used)
    iMSCP::Dir->new( dirname => "$main::imscpConfig{'ROOT_DIR'}/gui/public/tools/filemanager" )->remove(

    ) if -d "$main::imscpConfig{'ROOT_DIR'}/gui/public/tools/filemanager";

    # Save tools
    iMSCP::Dir->new( dirname => "$main::imscpConfig{'ROOT_DIR'}/gui/public/tools" )->rcopy(
        "$destdir$main::imscpConfig{'ROOT_DIR'}/gui/public/tools"
    ) if -d "$main::imscpConfig{'ROOT_DIR'}/gui/public/tools";

    0;
}

=item _cleanup()

 Process cleanup tasks

 Return int 0 on success, other on failure

=cut

sub _cleanup
{
    for("$iMSCP::Installer::Layout::localstatedir/cache/imscp",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/apache/skel/alias/phptmp",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/apache/skel/subdomain/phptmp",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/apache/backup",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/apache/working",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/fcgi",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/hooks.d",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/init.d",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/nginx",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/php-fpm",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/postfix/backup",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/postfix/imscp",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/postfix/parts",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/postfix/working",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/skel/domain/domain_disable_page",
        "$iMSCP::Installer::Layout::localstatedir/log/imscp/imscp-arpl-msgr"
    ) {
        my $rs ||= iMSCP::Dir->new( dirname => $_ )->remove();
        return $rs if $rs;
    }

    for("$iMSCP::Installer::Layout::sysconfdir/imscp/vsftpd/imscp_allow_writeable_root.patch",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/vsftpd/imscp_pthread_cancel.patch",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/apache/parts/php5.itk.ini",
        "$iMSCP::Installer::Layout::sysconfdir/default/imscp_panel",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/frontend/php-fcgi-starter",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/listeners.d/README",
        '/usr/sbin/maillogconvert.pl',
        # Due to a mistake in previous i-MSCP versions (Upstart conffile copied into systemd confdir)
        "$iMSCP::Installer::Layout::sysconfdir/systemd/system/php5-fpm.override",
        "$iMSCP::Installer::Layout::sysconfdir/imscp/imscp.old.conf"
    ) {
        next unless -f;
        my $rs = iMSCP::File->new( filename => $_ )->delFile();
        return $rs if $rs;
    }

    0;
}

=item _processXmlMakefile($filepath)

 Process the given makefile.xml file

 Param string $filepath xml file path
 Return int 0 on success, other on failure

=cut

sub _processXmlMakefile
{
    my $file = shift;

    unless (-f $file) {
        error( sprintf( "File `%s' doesn't exists", $file ) );
        return 1;
    }

    my $data = eval {
        require XML::Simple;
        XML::Simple->new( ForceArray => 1, ForceContent => 1 )->XMLin( $file );
    };
    if ($@) {
        error( sprintf("Couldn't load `%s' file: %s", $file, $@));
        return 1;
    }

    my %nodeRoutines = (
        create_folder => \&_createFolder,
        copy_folder   => \&_copyFolder,
        copy_file     => \&_copyFile
    );

    for my $node(qw/ create_folder copy_folder copy_file /) {
        for (@{$data->{$node}}) {
            my $rs = $nodeRoutines{$node}->($_);
            return $rs if $rs;
        }
    }

    0;
}

=item _expandVars($string)

 Expand variables in the given string

 Param string $string string containing variables to expands
 Return string Expanded string or die on failure

=cut

sub _expandVars
{
    my $string = shift || '';

    {
        no strict 'refs';

        while (my ($varname) = $string =~ /\@([^\@]+)\@/g) {
            if (defined ${"iMSCP::Installer::Layout::$varname"}) {
                $string =~ s/\@$varname\@/${"iMSCP::Installer::Layout::$varname"}/g;
            } elsif (exists $main::imscpConfig{$varname}) {
                $string =~ s/\@$varname\@/$main::imscpConfig{$varname}/g;
            } else {
                die( sprintf("Couldn't expand `%s'variable. Variable not found.", '@'.$varname.'@') );
            }
        }

    }
    $string;
}

=item _createFolder(\%node)

 Process the given create_folder xml node

 Param hashref %node XML node
 Return int 0 on success, other on failure

=cut

sub _createFolder
{
    my $node = shift;

    $node->{'content'} = _expandVars( $node->{'content'} );
    my $dir = File::Spec->catdir($iMSCP::Installer::Layout::DESTDIR, $node->{'content'});

    iMSCP::Dir->new( dirname => $dir )->make(
        {
            user  => defined $node->{'user'} ? _expandVars( $node->{'owner'} ) : undef,
            group => defined $node->{'group'} ? _expandVars( $node->{'group'} ) : undef,
            mode  => defined $node->{'mode'} ? oct( $node->{'mode'} ) : undef
        }
    );
}

=item _copyFolder(\%node)

 Process the given copy_folder xml node

 Param hashref %node XML node
 Return int 0 on success, other on failure

=cut

sub _copyFolder
{
    my $node = shift;

    $node->{'content'} = _expandVars( $node->{'content'} );

    if (defined $node->{'if'}) {
        unless (eval _expandVars( $node->{'if'} )) {
            unless ($node->{'kept'}) {
                eval { iMSCP::Dir->new( dirname => $node->{'content'} )->remove() };
                if ($@) {
                    error("Couldn't delete `%s' directory: %s", $@);
                    return 1;
                }
            }

            return 0;
        }
    }

    my ($srcdir, $destdir) = File::Basename::fileparse( $node->{'content'} );
    $destdir = File::Spec->catdir($iMSCP::Installer::Layout::DESTDIR, $destdir, $srcdir);

    unless (-d $srcdir) {
        my $distId = lc( iMSCP::LsbRelease->getInstance()->getId( 'short' ) );
        ($srcdir = File::Spec->catdir(getcwd(), $srcdir)) =~ s/$distId/debian/;
    }

    my $dir = iMSCP::Dir->new( dirname => $srcdir );
    my $rs = $dir->rcopy($destdir);
    return $rs if $rs
        || (!defined $node->{'user'} && !defined $node->{'group'} && !defined $node->{'mode'}
        && !defined $node->{'dirmode'} && !defined $node->{'filemode'}
    );

    setRights(
        $destdir,
        {
            mode      => $node->{'mode'} // undef,
            dirmode   => $node->{'dirmode'} // undef,
            filemode  => $node->{'filemode'} // undef,
            user      => $node->{'user'},
            group     => $node->{'group'},
            recursive => 1
        }
    );
}

=item _copyFile(\%node)

 Process the given create_folder xml node

 Param hashref %node XML node
 Return int 0 on success, other on failure

=cut

sub _copyFile
{
    my $node = shift;

    $node->{'content'} = _expandVars( $node->{'content'} );

    if (defined $node->{'if'}) {
        unless (eval _expandVars( $node->{'if'} )) {
            if (!$node->{'kept'} && -f $node->{ 'content' }) {
                my $rs = iMSCP::File->new( filename => $node->{'content'} )->delFile();
                return $rs if $rs;
            }

            return 0;
        }
    }

    my ($srcfile, $destdir) = File::Basename::fileparse( $node->{'content'} );
    $destdir = File::Spec->catdir($iMSCP::Installer::Layout::DESTDIR, $destdir);

    eval { iMSCP::Dir->new( dirname => $destdir )->make() };
    if ($@) {
        error("Couldn't create `%s' directory: %s", $@);
        return 1;
    }

    unless (-f $srcfile) {
        my $distId = lc( iMSCP::LsbRelease->getInstance()->getId( 'short' ) );
        ($srcfile = File::Spec->catfile(getcwd(), $srcfile)) =~ s/$distId/debian/;
    }

    my $file = iMSCP::File->new( filename => $srcfile );
    my $rs = $file->copyFile($destdir);
    return $rs if $rs
        || (!defined $node->{'user'} && !defined $node->{'group'} && !defined $node->{'mode'});

    $file->{'filename'} = File::Spec->catfile($destdir, $srcfile);
    $rs = $file->mode( oct( $node->{'mode'} ) ) if defined $node->{'mode'};
    return $rs if $rs || (!defined $node->{'user'} && !defined $node->{'group'});

    $file->owner(
        (defined $node->{'user'} ? _expandVars( $node->{'user'} ) : - 1),
        (defined $node->{'group'} ? _expandVars( $node->{'group'} ) : - 1)
    );
}

=item getDistInstallerAdapter()

 Return distribution installer adapter instance

 Return iMSCP::Installer::Adapter::Abstract

=cut

sub getDistInstallerAdapter
{
    return $installerAdapterInstance if defined $installerAdapterInstance;

    my $adpater = 'iMSCP::Installer::Adapter::'
        .iMSCP::LsbRelease->getInstance()->getId( 'short' );

    eval "require $adpater";
    fatal( sprintf( 'Could not load %s : %s', $adpater, $@ ) ) if $@;

    $installerAdapterInstance = $adpater->new();
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
